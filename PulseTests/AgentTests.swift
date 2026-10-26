import Foundation
import Testing
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
        #expect(browser.activeTab === tab)
        #expect(agent.request(for: other) == nil)

        agent.answer(try #require(agent.request(for: tab)), allow: false)
        let result = await call.value
        #expect(result.isError)
        #expect(result.text.contains("didn't let you use this tab"))
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

    @Test(arguments: ["Send", "Pay now", "Delete repository", "Place order", "Post"])
    func confirmsClicksThatCantBeTakenBack(label: String) {
        #expect(Agent.needsConfirmation(label))
    }

    @Test(arguments: ["Search", "Sender settings", "Posted 3h ago", "Next", "Orders history"])
    func letsOrdinaryClicksThrough(label: String) {
        #expect(!Agent.needsConfirmation(label))
    }
}

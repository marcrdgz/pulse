import Foundation
import Observation
import WebKit

/// A question an AI agent's action waits on, shown over the tab it's about.
struct AgentRequest: Identifiable {
    enum Kind: Equatable {
        /// The first time an agent wants one of the user's own tabs.
        case useTab
        /// A click that looks like it sends, pays or deletes; holds the button's label.
        case confirm(String)
    }

    let id = UUID()
    let tabID: Tab.ID
    let kind: Kind
    fileprivate let respond: (Bool) -> Void
}

/// What the agent is doing in a tab, shown in the dock at the bottom of its page.
struct AgentActivity: Equatable {
    var status: String
    var isDone = false
}

struct AgentToolResult {
    let text: String
    var isError = false
}

private struct AgentError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Lets an AI agent on this Mac (Claude Code, Codex…) read and act in the user's tabs through MCP.
/// The user stays in charge: the agent asks before using one of their tabs and before clicks that
/// send, pay or delete; it never sees or types passwords; and they can take a tab back at any time.
@Observable
final class Agent {
    private(set) var requests: [AgentRequest] = []
    private(set) var activities: [Tab.ID: AgentActivity] = [:]
    /// Ticked in the sidebar until the user opens the tab, so finished work isn't missed.
    private(set) var finishedTabIDs: Set<Tab.ID> = []
    /// The connected client as people call it: "Claude", "Codex"…
    private(set) var name = "AI"

    @ObservationIgnored weak var browser: Browser?
    /// Tabs the user allowed, plus the ones the agent opened itself.
    @ObservationIgnored private var grantedTabIDs: Set<Tab.ID> = []
    @ObservationIgnored private var dockDismissals: [Tab.ID: Task<Void, Never>] = [:]

    /// The agent's own world: the page can't see or tamper with the element list kept between calls.
    private static let world = WKContentWorld.world(name: "PulseAgent")

    func clientDidConnect(name client: String?) {
        let client = client ?? ""
        let known = ["claude": "Claude", "codex": "Codex", "cursor": "Cursor", "chatgpt": "ChatGPT"]
        name = known.first { client.lowercased().contains($0.key) }?.value ?? (client.isEmpty ? "AI" : client)
    }

    // MARK: User decisions

    func request(for tab: Tab) -> AgentRequest? {
        requests.first { $0.tabID == tab.id }
    }

    func answer(_ request: AgentRequest, allow: Bool) {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        requests.remove(at: index)
        request.respond(allow)
    }

    /// Ends the agent's access to the tab; its next action there asks again.
    func takeOver(_ tab: Tab) {
        grantedTabIDs.remove(tab.id)
        denyRequests(in: tab)
        dockDismissals[tab.id]?.cancel()
        activities[tab.id] = nil
        tab.loadedWebView?.callAsyncJavaScript(AgentScripts.hidePointer, in: nil, in: Self.world, completionHandler: nil)
    }

    func tabWasShown(_ tab: Tab) {
        finishedTabIDs.remove(tab.id)
    }

    func tabWillClose(_ tab: Tab) {
        takeOver(tab)
        finishedTabIDs.remove(tab.id)
    }

    private func denyRequests(in tab: Tab) {
        let pending = requests.filter { $0.tabID == tab.id }
        requests.removeAll { $0.tabID == tab.id }
        pending.forEach { $0.respond(false) }
    }

    // MARK: Tools

    static let instructions = """
        Pulse is the user's web browser, and its tabs are signed in as them. Use list_tabs or open_tab \
        to get a tab, then read_page before clicking or typing: element numbers come from the latest \
        read_page of that tab. Pulse asks the user before you use one of their own tabs and before clicks \
        that send, pay or delete; if they decline, stop and tell them. Never ask for or type passwords: \
        ask the user to sign in. Call finish on each tab when you're done with it.
        """

    static let tools: [JSONObject] = [
        tool("list_tabs", "Lists the user's open tabs: id, title and URL.", [:]),
        tool("open_tab", "Opens a URL in a new background tab you can use without asking. Prefer it for browsing on your own.",
             ["url": text("The address to open.")]),
        tool("read_page", "Reads a tab: title, URL, its numbered buttons, links and fields, and the visible text. "
             + "The user is asked the first time you use one of their tabs.",
             ["tab_id": text("From list_tabs or open_tab.")]),
        tool("click", "Clicks a numbered element from the tab's latest read_page, then waits for the page to settle.",
             ["tab_id": text("From list_tabs or open_tab."), "element": number("The element's number.")]),
        tool("type_text", "Replaces the text of a numbered field or picks a menu option. It doesn't submit: click the form's button.",
             ["tab_id": text("From list_tabs or open_tab."), "element": number("The field's number."),
              "text": text("The text to enter, or the option to pick.")]),
        tool("navigate", "Loads a URL in a tab.", ["tab_id": text("From list_tabs or open_tab."), "url": text("The address to open.")]),
        tool("finish", "Hands a tab back to the user when you're done with it, showing a short summary in Pulse.",
             ["tab_id": text("From list_tabs or open_tab."), "summary": text("A few words on what you did or found.")]),
    ]

    func call(_ tool: String, arguments: JSONObject) async -> AgentToolResult {
        do {
            switch tool {
            case "list_tabs": return listTabs()
            case "open_tab": return try await openTab(at: url(in: arguments))
            case "read_page": return try await readPage(of: usableTab(arguments))
            case "click": return try await click(element(in: arguments), in: usableTab(arguments))
            case "type_text":
                return try await type(string("text", in: arguments), into: element(in: arguments), in: usableTab(arguments))
            case "navigate": return try await navigate(usableTab(arguments), to: url(in: arguments))
            case "finish": return try await finish(tab(in: arguments), summary: arguments["summary"] as? String)
            default: throw AgentError("Unknown tool \(tool).")
            }
        } catch let error as AgentError {
            return AgentToolResult(text: error.message, isError: true)
        } catch {
            return AgentToolResult(text: error.localizedDescription, isError: true)
        }
    }

    private func listTabs() -> AgentToolResult {
        guard let browser else { return AgentToolResult(text: "Pulse has no window open.", isError: true) }
        let lines = browser.everyTab.filter { $0.internalPage == nil }.map { tab in
            "- \(tab.id.uuidString): \(tab.displayTitle) — \(tab.url.absoluteString)"
                + (tab.id == browser.activeTabID ? " (in front)" : "")
        }
        return AgentToolResult(text: lines.isEmpty ? "No tabs are open." : "Open tabs:\n" + lines.joined(separator: "\n"))
    }

    private func openTab(at url: URL) async throws -> AgentToolResult {
        guard let browser else { throw AgentError("Pulse has no window open.") }
        let tab = browser.openTab(url: url, activate: false)
        grantedTabIDs.insert(tab.id)
        show("Opening \(url.displayHost ?? url.absoluteString)", in: tab)
        _ = await page(of: tab)
        return AgentToolResult(text: "Opened tab \(tab.id.uuidString): \(tab.displayTitle) — \(tab.url.absoluteString)")
    }

    private func readPage(of tab: Tab) async throws -> AgentToolResult {
        show("Reading \(tab.displayTitle)", in: tab)
        let page = try await run(AgentScripts.read, in: tab)
        let elements = page["elements"] as? [String] ?? []
        return AgentToolResult(text: """
            \(page["title"] as? String ?? "")
            \(page["url"] as? String ?? "")

            Buttons, links and fields, by number:
            \(elements.isEmpty ? "(none)" : elements.joined(separator: "\n"))

            Page text:
            \(page["text"] as? String ?? "")
            """)
    }

    private func click(_ element: Int, in tab: Tab) async throws -> AgentToolResult {
        let label = try await point(at: element, in: tab)
        show("Clicking “\(label)”", in: tab)
        if Self.needsConfirmation(label), !(await ask(.confirm(label), in: tab)) {
            throw AgentError("The user didn't let you click “\(label)”. Stop and ask them in your reply.")
        }
        try await run(AgentScripts.press, ["index": element], in: tab)
        await waitForPage(tab)
        return AgentToolResult(text: "Clicked “\(label)”. The page is now \(tab.url.absoluteString); read_page to see it.")
    }

    private func type(_ text: String, into element: Int, in tab: Tab) async throws -> AgentToolResult {
        let label = try await point(at: element, in: tab)
        show("Typing in “\(label)”", in: tab)
        try await run(AgentScripts.fill, ["index": element, "text": text], in: tab)
        return AgentToolResult(text: "Entered the text in “\(label)”.")
    }

    private func navigate(_ tab: Tab, to url: URL) async throws -> AgentToolResult {
        show("Opening \(url.displayHost ?? url.absoluteString)", in: tab)
        tab.load(url)
        await waitForPage(tab)
        return AgentToolResult(text: "Loaded \(tab.displayTitle) — \(tab.url.absoluteString)")
    }

    private func finish(_ tab: Tab, summary: String?) async throws -> AgentToolResult {
        grantedTabIDs.remove(tab.id)
        _ = try? await tab.loadedWebView?.callAsyncJavaScript(AgentScripts.hidePointer, contentWorld: Self.world)
        let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        activities[tab.id] = AgentActivity(status: summary.isEmpty ? "Done" : "Done · \(summary)", isDone: true)
        if !(browser?.visibleTabs.contains(tab) ?? false) { finishedTabIDs.insert(tab.id) }
        dockDismissals[tab.id] = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { activities[tab.id] = nil }
        }
        return AgentToolResult(text: "Handed the tab back to the user.")
    }

    /// Clicks with these words wait for the user, since what they do can't be taken back.
    static func needsConfirmation(_ label: String) -> Bool {
        let pattern = #"\b(send|pay|buy|purchase|order|checkout|check out|delete|remove|transfer|publish|post|submit|confirm|subscribe|unsubscribe|book|reserve|donate)\b"#
        return label.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Helpers

    private func tab(in arguments: JSONObject) throws -> Tab {
        guard let id = (arguments["tab_id"] as? String).flatMap(UUID.init(uuidString:)),
              let tab = browser?.everyTab.first(where: { $0.id == id })
        else { throw AgentError("No tab has that tab_id; call list_tabs.") }
        guard tab.internalPage == nil else { throw AgentError("That's one of Pulse's own pages, which agents can't use.") }
        return tab
    }

    /// The tab, once the user has allowed the agent to use it.
    private func usableTab(_ arguments: JSONObject) async throws -> Tab {
        let tab = try tab(in: arguments)
        if !grantedTabIDs.contains(tab.id) {
            guard await ask(.useTab, in: tab) else {
                throw AgentError("The user didn't let you use this tab. Don't retry; ask them in your reply.")
            }
            grantedTabIDs.insert(tab.id)
        }
        return tab
    }

    /// Brings the tab to the front so the user sees what they're answering.
    private func ask(_ kind: AgentRequest.Kind, in tab: Tab) async -> Bool {
        browser?.select(tab)
        return await withCheckedContinuation { continuation in
            requests.append(AgentRequest(tabID: tab.id, kind: kind) { continuation.resume(returning: $0) })
        }
    }

    private func show(_ status: String, in tab: Tab) {
        dockDismissals[tab.id]?.cancel()
        finishedTabIDs.remove(tab.id)
        activities[tab.id] = AgentActivity(status: status)
    }

    private func string(_ key: String, in arguments: JSONObject) throws -> String {
        guard let value = arguments[key] as? String else { throw AgentError("Missing \(key).") }
        return value
    }

    private func element(in arguments: JSONObject) throws -> Int {
        guard let element = (arguments["element"] as? NSNumber)?.intValue else { throw AgentError("Missing element.") }
        return element
    }

    /// Web addresses only: `file:` and Pulse's own pages stay out of the agent's reach.
    private func url(in arguments: JSONObject) throws -> URL {
        let input = try string("url", in: arguments)
        guard let url = AddressResolver.destination(for: input)?.url, ["http", "https"].contains(url.scheme ?? "")
        else { throw AgentError("Not a web address: \(input)") }
        return url
    }

    /// Moves the agent's pointer onto the element and returns its label.
    private func point(at element: Int, in tab: Tab) async throws -> String {
        let result = try await run(AgentScripts.point, ["index": element, "name": name], in: tab)
        return result["label"] as? String ?? "element \(element)"
    }

    @discardableResult
    private func run(_ script: String, _ arguments: JSONObject = [:], in tab: Tab) async throws -> JSONObject {
        let webView = await page(of: tab)
        let result = try await webView.callAsyncJavaScript(script, arguments: arguments, contentWorld: Self.world) as? JSONObject ?? [:]
        if let error = result["error"] as? String { throw AgentError(error) }
        return result
    }

    /// Background and sleeping tabs have no web view until shown; this loads one for the agent.
    private func page(of tab: Tab) async -> WKWebView {
        let wasLoaded = tab.loadedWebView != nil
        let webView = tab.webView
        // A view that was never on screen has no size, and pages laid out at zero width hide most of their content.
        if webView.window == nil, webView.frame.isEmpty { webView.frame = CGRect(x: 0, y: 0, width: 1280, height: 800) }
        if !wasLoaded { await waitForPage(tab) }
        return webView
    }

    private func waitForPage(_ tab: Tab) async {
        try? await Task.sleep(for: .milliseconds(300))
        let deadline = Date.now.addingTimeInterval(15)
        while tab.isLoading, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: JSONObject]) -> JSONObject {
        let required = properties.keys.filter { $0 != "summary" }.sorted()
        return ["name": name, "description": description,
                "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }

    private static func text(_ description: String) -> JSONObject { ["type": "string", "description": description] }
    private static func number(_ description: String) -> JSONObject { ["type": "integer", "description": description] }
}

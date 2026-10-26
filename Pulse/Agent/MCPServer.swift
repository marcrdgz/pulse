import Foundation
import Network
import Observation

typealias JSONObject = [String: Any]

/// A minimal MCP server over Streamable HTTP, reachable only from this Mac: each JSON-RPC request
/// arrives as a POST and gets a single JSON reply. None of the tools stream, so there are no
/// server-sent events and no `GET` stream.
@Observable
final class MCPServer {
    enum State: Equatable {
        case stopped
        case listening
        case failed(String)
    }

    static let port: UInt16 = 47821
    static var endpoint: String { "http://127.0.0.1:\(port)/mcp" }

    private(set) var state = State.stopped

    @ObservationIgnored private let agent: Agent
    /// Checked on every request, so a new key takes effect without restarting the server.
    @ObservationIgnored private let token: () -> String
    @ObservationIgnored private var listener: NWListener?

    init(agent: Agent, token: @escaping () -> String) {
        self.agent = agent
        self.token = token
    }

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        // Loopback only: other machines on the network never see the port.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerDidChange(to: state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    guard let self else { return connection.cancel() }
                    connection.start(queue: .main)
                    self.receive(on: connection, buffer: Data())
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    private func listenerDidChange(to newState: NWListener.State) {
        switch newState {
        case .ready:
            state = .listening
        case .failed(let error):
            listener?.cancel()
            listener = nil
            state = .failed(error.debugDescription)
        default:
            break
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            MainActor.assumeIsolated {
                var buffer = buffer
                if let content { buffer.append(content) }
                guard let self else { return connection.cancel() }
                if let request = HTTPRequest(buffer) {
                    Task {
                        let response = await self.response(to: request)
                        connection.send(content: response.data, completion: .contentProcessed { _ in connection.cancel() })
                    }
                } else if isComplete || error != nil || buffer.count > 4 * 1024 * 1024 {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    func response(to request: HTTPRequest) async -> HTTPResponse {
        // Browsers always send Origin on a POST, so this keeps web pages (including Pulse's own)
        // from driving the browser through a form or fetch to localhost.
        guard request.headers["origin"] == nil else { return HTTPResponse(status: 403) }
        // A DNS-rebinding page reaches this port under its own host name.
        guard ["127.0.0.1:\(Self.port)", "localhost:\(Self.port)"].contains(request.headers["host"] ?? "")
        else { return HTTPResponse(status: 403) }
        guard Self.isEqualInConstantTime(request.headers["authorization"] ?? "", "Bearer \(token())")
        else { return HTTPResponse(status: 401) }
        guard request.path == "/mcp" else { return HTTPResponse(status: 404) }
        guard request.method == "POST" else { return HTTPResponse(status: 405) }
        guard let reply = await reply(to: request.body) else { return HTTPResponse(status: 202) }
        return HTTPResponse(status: 200, body: reply)
    }

    /// The JSON-RPC reply to one message; `nil` for notifications, which get none.
    func reply(to body: Data) async -> Data? {
        guard let message = (try? JSONSerialization.jsonObject(with: body)) as? JSONObject,
              let method = message["method"] as? String
        else { return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]]) }
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? JSONObject ?? [:]

        var reply: JSONObject = ["jsonrpc": "2.0", "id": id]
        switch method {
        case "initialize":
            let client = params["clientInfo"] as? JSONObject
            agent.clientDidConnect(name: client?["name"] as? String)
            reply["result"] = [
                // Every revision so far is compatible with what this server uses, so echo the client's.
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "pulse", "version": Bundle.main.shortVersion],
                "instructions": Agent.instructions,
            ]
        case "ping":
            reply["result"] = [:]
        case "tools/list":
            reply["result"] = ["tools": Agent.tools]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let result = await agent.call(name, arguments: params["arguments"] as? JSONObject ?? [:])
            reply["result"] = ["content": [["type": "text", "text": result.text]], "isError": result.isError]
        default:
            reply["error"] = ["code": -32601, "message": "Method not found: \(method)"]
        }
        return Self.encode(reply)
    }

    /// So the time a wrong key takes to reject doesn't reveal how much of it was right.
    private static func isEqualInConstantTime(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = Array(lhs.utf8), rhs = Array(rhs.utf8)
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func encode(_ object: JSONObject) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}

/// An HTTP/1.1 request, parsed once the headers and the whole body have arrived.
struct HTTPRequest {
    let method: String
    let path: String
    /// Names lowercased.
    let headers: [String: String]
    let body: Data

    /// `nil` while `buffer` doesn't hold a complete request yet.
    init?(_ buffer: Data) {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buffer[..<end.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = headers["content-length"].flatMap(Int.init) ?? 0
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1].split(separator: "?", maxSplits: 1)[0])
        self.headers = headers
        self.body = Data(body.prefix(length))
    }
}

struct HTTPResponse {
    let status: Int
    var body: Data?

    var data: Data {
        let reason = [200: "OK", 202: "Accepted", 401: "Unauthorized", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed"][status] ?? ""
        var head = "HTTP/1.1 \(status) \(reason)\r\nConnection: close\r\nContent-Length: \(body?.count ?? 0)\r\n"
        if body != nil { head += "Content-Type: application/json\r\n" }
        return Data((head + "\r\n").utf8) + (body ?? Data())
    }
}

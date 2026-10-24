import AppKit
import Testing
@testable import Pulse

struct FaviconLoaderTests {
    @Test func sitesOnDifferentPortsOfOneHostKeepTheirOwnIcons() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubIconProtocol.self]
        let loader = FaviconLoader(session: URLSession(configuration: configuration))

        let first = await loader.favicon(forPage: URL(string: "http://localhost:3000/")!, declaredIconURL: nil)
        let second = await loader.favicon(forPage: URL(string: "http://localhost:5173/")!, declaredIconURL: nil)

        #expect(try #require(first).size.width == 1)
        #expect(try #require(second).size.width == 2)
    }
}

/// Serves a square PNG per port, sized by the port's position, so each origin's icon is recognizable.
private nonisolated final class StubIconProtocol: URLProtocol {
    private static let iconWidthsByPort = [3000: 1, 5173: 2]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let width = url.port.flatMap({ Self.iconWidthsByPort[$0] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: width, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bitmap.representation(using: .png, properties: [:])!)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

import Foundation
import Testing
@testable import MenuWatt

@Suite(.serialized)
@MainActor
struct UpdateCheckerTests {
    @Test
    func concurrentChecksShareOneRequestAndResult() async throws {
        let stub = UpdateResponseStub(status: 200, body: Self.release, delay: 0.1)
        let session = Self.session(stub)
        defer { session.invalidateAndCancel() }
        let checker = UpdateChecker(session: session)
        let first = Task { await checker.check() }
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while stub.requestCount == 0, ContinuousClock().now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(stub.requestCount == 1)
        #expect(checker.status == .checking)
        let second = Task { await checker.check() }
        let result = await first.value
        #expect(await second.value == result)
        #expect(result?.tagName == "v999.0.0")
        #expect(stub.requestCount == 1)
        #expect(checker.status == .updateAvailable(try #require(result)))
    }

    @Test
    func httpAndPayloadFailuresLeaveRetryAvailable() async {
        for (status, body) in [(403, "{}"), (200, "not json")] {
            let stub = UpdateResponseStub(status: status, body: body)
            let session = Self.session(stub)
            defer { session.invalidateAndCancel() }
            let checker = UpdateChecker(session: session)
            #expect(await checker.check() == nil)
            if case .failed = checker.status {} else { Issue.record("Expected failure: \(checker.status)") }
            stub.replace(status: 200, body: Self.release)
            #expect(await checker.check()?.tagName == "v999.0.0")
            #expect(stub.requestCount == 2)
        }
    }

    @Test
    func currentReleaseIsUpToDateAndNumericVersionOrderingIsStable() async {
        let versionSession = Self.session(UpdateResponseStub(status: 200, body: "{}"))
        defer { versionSession.invalidateAndCancel() }
        let checker = UpdateChecker(session: versionSession)
        #expect(checker.compareVersions("v1.10.0", current: "1.9.9") > 0)
        #expect(checker.compareVersions("1.1", current: "v1.1.0") == 0)
        #expect(checker.compareVersions("1.0.9", current: "1.1.0") < 0)
        let stub = UpdateResponseStub(status: 200, body: "{\"tag_name\":\"\(checker.currentVersion)\",\"html_url\":\"https://github.com/Ketchio-dev/MenuWatt/releases\"}")
        let session = Self.session(stub)
        defer { session.invalidateAndCancel() }
        let current = UpdateChecker(session: session)
        #expect(await current.check() == nil)
        #expect(current.status == .upToDate(currentVersion: current.currentVersion))
    }

    private static let release = "{\"tag_name\":\"v999.0.0\",\"html_url\":\"https://github.com/Ketchio-dev/MenuWatt/releases/tag/v999.0.0\",\"published_at\":\"2026-10-08T00:00:00Z\",\"body\":\"Test release\"}"

    private static func session(_ stub: UpdateResponseStub) -> URLSession {
        UpdateURLProtocol.stub = stub
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}

private final class UpdateResponseStub: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int
    private var body: String
    private var requests = 0
    let delay: TimeInterval
    init(status: Int, body: String, delay: TimeInterval = 0) {
        self.status = status; self.body = body; self.delay = delay
    }
    var requestCount: Int { lock.withLock { requests } }
    func replace(status: Int, body: String) { lock.withLock { self.status = status; self.body = body } }
    func response() -> (Int, Data) { lock.withLock { requests += 1; return (status, Data(body.utf8)) } }
}

private final class UpdateURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var stub: UpdateResponseStub!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let stub = Self.stub!
        let (status, data) = stub.response()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay) { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

import Foundation

/// 스위트별 독립 스텁 상태. NSLock으로 가드 — URLSession 로딩 스레드와 테스트 본문이 교차 접근한다.
final class StubStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: (@Sendable (URLRequest) -> (Int, Data))?
    private var _networkError: (any Error)?
    private var _capturedRequest: URLRequest?
    private var _capturedBody: Data?
    private var _responseHeaders: [String: String] = [:]

    var handler: (@Sendable (URLRequest) -> (Int, Data))? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }
    var networkError: (any Error)? {
        get { lock.withLock { _networkError } }
        set { lock.withLock { _networkError = newValue } }
    }
    var capturedRequest: URLRequest? {
        get { lock.withLock { _capturedRequest } }
        set { lock.withLock { _capturedRequest = newValue } }
    }
    var capturedBody: Data? {
        get { lock.withLock { _capturedBody } }
        set { lock.withLock { _capturedBody = newValue } }
    }
    /// Content-Type 외 추가 응답 헤더 (Retry-After 등)
    var responseHeaders: [String: String] {
        get { lock.withLock { _responseHeaders } }
        set { lock.withLock { _responseHeaders = newValue } }
    }

    func reset() {
        lock.withLock {
            _handler = nil
            _networkError = nil
            _capturedRequest = nil
            _capturedBody = nil
            _responseHeaders = [:]
        }
    }
}

/// 스위트별 서브클래스가 storage를 오버라이드 — static 공유로 인한 스위트 간 간섭 차단 (최종 리뷰 반영)
class StubURLProtocolBase: URLProtocol {
    class var storage: StubStorage {
        fatalError("서브클래스가 storage를 제공해야 한다")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let storage = Self.storage
        if let error = storage.networkError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        storage.capturedRequest = request
        storage.capturedBody = request.bodyData
        guard let handler = storage.handler else {
            // 핸들러 미설정 — 크래시 대신 명시적 에러 (기존 강제 언랩 제거)
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
                .merging(storage.responseHeaders) { _, extra in extra })!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class ClipnoteAPIStub: StubURLProtocolBase {
    nonisolated(unsafe) static let shared = StubStorage()
    override class var storage: StubStorage { shared }
}

final class AppModelStub: StubURLProtocolBase {
    nonisolated(unsafe) static let shared = StubStorage()
    override class var storage: StubStorage { shared }
}

final class NotionAPIStub: StubURLProtocolBase {
    nonisolated(unsafe) static let shared = StubStorage()
    override class var storage: StubStorage { shared }
}

final class NotionExporterStub: StubURLProtocolBase {
    nonisolated(unsafe) static let shared = StubStorage()
    override class var storage: StubStorage { shared }
}

final class GeminiAPIStub: StubURLProtocolBase {
    nonisolated(unsafe) static let shared = StubStorage()
    override class var storage: StubStorage { shared }
}

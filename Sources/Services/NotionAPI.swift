import Foundation

enum NotionAPIError: Error, Equatable, LocalizedError {
    case invalidToken        // 401
    case parentNotFound      // 404
    case rateLimited(after: Double)  // 429 — Retry-After(초), 헤더 없으면 기본값
    case api(Int, String)    // 기타 — Notion 에러 body의 message
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidToken: String(localized: "The Notion token isn't valid — check Settings")
        case .parentNotFound: String(localized: "Parent page not found — check the page ID and that your integration is connected (page ··· → Connections)")
        case .rateLimited: String(localized: "Notion rate limit reached — try again in a moment")   // 자동 재시도 소진 후
        case .api(let code, let message): String(localized: "Notion error") + " (HTTP \(code)) — \(message)"
        case .network: String(localized: "Couldn't reach Notion — check your network")
        }
    }
}

/// Notion 공식 API 클라이언트 (BYOT). 코어 export.py의 notion_request/notion_upload_image 포팅.
/// 토큰은 Authorization 헤더 세팅 외 어디에도 쓰지 않는다.
final class NotionAPI: Sendable {
    static let version = "2022-06-28"   // 코어와 동일 고정
    /// 429 재시도 횟수(최초 시도 제외). Notion 공식 한도는 초당 평균 3요청 — 이미지 다수 문서에서
    /// 짧게 튀는 429는 Retry-After만큼 기다리면 대부분 해소된다.
    static let maxRetries = 3
    /// Retry-After 헤더가 없거나 해석 불가일 때의 대기(초)와 상한 — 무한 대기 방지.
    static let defaultRetryDelay = 1.0
    static let maxRetryDelay = 30.0
    private static let base = URL(string: "https://api.notion.com/v1")!
    private let token: String
    private let session: URLSession
    private let retries: Int
    private let sleeper: @Sendable (Double) async -> Void

    init(token: String, session: URLSession = .shared,
         retries: Int = NotionAPI.maxRetries,
         sleeper: @escaping @Sendable (Double) async -> Void = { seconds in
             try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
         }) {
        self.token = token
        self.session = session
        self.retries = retries
        self.sleeper = sleeper
    }

    /// 429는 Retry-After(초)만큼 기다렸다가 재시도한다. 재시도 소진 시 .rateLimited를 던진다.
    private func request(path: String, jsonBody: [String: Any]? = nil,
                         rawBody: (data: Data, contentType: String)? = nil)
        async throws -> [String: Any] {
        for attempt in 0... {
            do {
                return try await send(path: path, jsonBody: jsonBody, rawBody: rawBody)
            } catch NotionAPIError.rateLimited(let retryAfter) where attempt < retries {
                await sleeper(retryAfter)
            }
        }
        throw NotionAPIError.rateLimited(after: Self.defaultRetryDelay)   // 도달 불가(for 0...는 무한)
    }

    private func send(path: String, jsonBody: [String: Any]? = nil,
                      rawBody: (data: Data, contentType: String)? = nil)
        async throws -> [String: Any] {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        } else if let rawBody {
            request.setValue(rawBody.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = rawBody.data
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NotionAPIError.network(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw NotionAPIError.api(0, "응답 해석 불가")
        }
        switch http.statusCode {
        case 200...299: break
        case 401: throw NotionAPIError.invalidToken
        case 404: throw NotionAPIError.parentNotFound
        case 429: throw NotionAPIError.rateLimited(after: Self.retryDelay(from: http))
        default: throw NotionAPIError.api(http.statusCode, Self.message(from: data))
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Retry-After(정수 초)를 [0, maxRetryDelay]로 클램프. 없거나 해석 불가면 기본값.
    static func retryDelay(from response: HTTPURLResponse) -> Double {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(raw.trimmingCharacters(in: .whitespaces)), seconds.isFinite
        else { return defaultRetryDelay }
        return min(max(seconds, 0), maxRetryDelay)
    }

    private static func message(from data: Data) -> String {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"]
            as? String ?? ""
    }

    func createFileUpload() async throws -> String {
        let object = try await request(path: "/file_uploads", jsonBody: [:])
        guard let id = object["id"] as? String else {
            throw NotionAPIError.api(200, "file_upload id 없음")
        }
        return id
    }

    /// 코어 notion_upload_image(export.py 228~241행)의 멀티파트 바디 조립부 포팅.
    /// 바이트 시퀀스(명시적 문자열 연결로 CRLF 이스케이프 실수 여지 제거 — 브리프 주의사항 반영):
    ///   --{boundary}\r\n
    ///   Content-Disposition: form-data; name="file"; filename="{filename}"\r\n
    ///   Content-Type: {mime}\r\n\r\n
    ///   {raw bytes}
    ///   \r\n--{boundary}--\r\n
    func sendFileUpload(id: String, data: Data, filename: String,
                        mime: String = "image/jpeg") async throws {
        let boundary = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let head = "--" + boundary + "\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"" + filename + "\"\r\n"
            + "Content-Type: " + mime + "\r\n\r\n"
        var body = Data(head.utf8)
        body.append(data)
        body.append(Data(("\r\n--" + boundary + "--\r\n").utf8))
        _ = try await request(path: "/file_uploads/\(id)/send",
                              rawBody: (body, "multipart/form-data; boundary=\(boundary)"))
    }

    func createPage(parentPageID: String, title: String,
                    children: [NotionBlock]) async throws -> (id: String, url: String?) {
        let object = try await request(path: "/pages", jsonBody: [
            "parent": ["page_id": parentPageID],
            "properties": ["title": ["title": NotionBlockBuilder.rich(title)]],
            "children": children,
        ])
        guard let id = object["id"] as? String else {
            throw NotionAPIError.api(200, "page id 없음")
        }
        return (id, object["url"] as? String)
    }

    func appendChildren(pageID: String, blocks: [NotionBlock]) async throws {
        _ = try await request(path: "/blocks/\(pageID)/children",
                              jsonBody: ["children": blocks])
    }
}

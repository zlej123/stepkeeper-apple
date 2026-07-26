import Foundation

enum StepkeeperAPIError: Error, Equatable, LocalizedError {
    case missingKey            // 401
    case badRequest(String)    // 422
    case rateLimited           // 429
    case modelFailure(String)  // 502 (모델 오류·계약 위반)
    case server(Int, String)   // 기타 상태코드
    case network(String)       // 연결 실패
    case invalidResponse       // 200이지만 해석 불가

    var errorDescription: String? {
        switch self {
        case .missingKey: "설정에서 Gemini API 키를 입력하세요"
        case .badRequest(let detail): "URL 또는 요청 값 문제 — \(detail)"
        case .rateLimited: "Gemini 무료 한도 도달 — 잠시 후 다시 시도해 주세요"
        case .modelFailure(let detail): "분석에 실패했습니다 — 다시 시도해 주세요 (\(detail))"
        case .server(let code, let detail): "서버 오류 (HTTP \(code)) — \(detail)"
        case .network: "서버에 연결할 수 없습니다 — 서버 URL을 확인하세요"
        case .invalidResponse: "서버 응답을 해석하지 못했습니다"
        }
    }
}

struct AnalyzeResult: Sendable {
    var videoId: String
    var analysis: Analysis
    /// 서버가 준 analysis 객체 그대로(모델에 없는 `_model` 등 보존) — analysis.json 저장용
    var rawAnalysis: Data
}

final class StepkeeperAPI: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func analyze(videoURL: String, profile: String, language: String,
                 maxGuides: Int = Settings.maxGuides, duration: Int,
                 geminiKey: String) async throws -> AnalyzeResult {
        var request = URLRequest(url: baseURL.appending(path: "/v1/analyze"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180   // Gemini 분석은 영상 길이에 따라 수십 초
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(geminiKey, forHTTPHeaderField: "X-Gemini-Key")
        let body: [String: Any] = [
            "url": videoURL, "profile": profile, "language": language,
            "max_guides": maxGuides, "duration": duration,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StepkeeperAPIError.network(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw StepkeeperAPIError.invalidResponse
        }
        switch http.statusCode {
        case 200: break
        case 401: throw StepkeeperAPIError.missingKey
        case 422: throw StepkeeperAPIError.badRequest(Self.detail(from: data))
        case 429: throw StepkeeperAPIError.rateLimited
        case 502: throw StepkeeperAPIError.modelFailure(Self.detail(from: data))
        default: throw StepkeeperAPIError.server(http.statusCode, Self.detail(from: data))
        }

        guard let envelope = try? JSONDecoder().decode(AnalyzeEnvelope.self, from: data),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawAnalysisObject = object["analysis"],
              let rawAnalysis = try? JSONSerialization.data(withJSONObject: rawAnalysisObject)
        else { throw StepkeeperAPIError.invalidResponse }
        return AnalyzeResult(videoId: envelope.videoId,
                             analysis: envelope.analysis, rawAnalysis: rawAnalysis)
    }

    /// 원탭 이상 신고 — X-Gemini-Key 불필요, analysis는 rawAnalysis 원본 병합
    func submitReport(_ report: IssueReport) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/v1/reports"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let analysisObject = (try? JSONSerialization.jsonObject(with: report.rawAnalysis)) ?? [String: Any]()
        let body: [String: Any] = [
            "url": report.url,
            "video_id": report.videoId,
            "reason": report.reason.rawValue,
            "note": report.note,
            "profile": report.profile,
            "language": report.language,
            "analysis": analysisObject,
            "picks": report.picks,
            "client": report.client,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StepkeeperAPIError.network(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw StepkeeperAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw StepkeeperAPIError.server(http.statusCode, Self.detail(from: data))
        }
    }

    /// FastAPI 에러 body {"detail": <string|object>}에서 사람이 읽을 문자열 추출
    private static func detail(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        if let text = detail as? String { return text }
        if let encoded = try? JSONSerialization.data(withJSONObject: detail),
           let text = String(data: encoded, encoding: .utf8) { return text }
        return ""
    }
}

import Foundation

/// 직접 Gemini 분석 (BYOK, 서버 없이) — 확장 bg.js analyzeDirect 포팅.
/// 키는 x-goog-api-key 헤더 세팅 외 어디에도 쓰지 않는다.
final class GeminiAPI: Sendable {
    static let model = "gemini-flash-lite-latest"   // v1 결정: 설정 비노출
    private static let base = "https://generativelanguage.googleapis.com/v1beta/models"
    private let session: URLSession
    private let assets: Bundle

    init(session: URLSession = .shared, assets: Bundle = .main) {
        self.session = session
        self.assets = assets
    }

    struct AssetMissing: Error { let name: String }

    private func asset(_ name: String, ext: String, subdirectory: String) throws -> String {
        guard let url = assets.url(forResource: name, withExtension: ext,
                                   subdirectory: subdirectory) else {
            throw AssetMissing(name: "\(subdirectory)/\(name).\(ext)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// bg.js buildPrompt와 동일 치환 (전체 치환)
    func buildPrompt(profile: String, duration: Int, language: String,
                     maxGuides: Int) throws -> String {
        let rules = try asset("rules", ext: "md", subdirectory: "skill-core/engine")
        let prompt = try asset("prompt", ext: "md", subdirectory: "skill-core/\(profile)")
        return prompt
            .replacingOccurrences(of: "{{RULES}}", with: rules)
            .replacingOccurrences(of: "{DURATION}", with: MarkdownBuilder.hms(duration))
            .replacingOccurrences(of: "{OUTPUT_LANGUAGE}", with: language)
            .replacingOccurrences(of: "{MAX_VISUAL_GUIDES}", with: String(maxGuides))
    }

    /// bg.js loadSchema와 동일 — 메타 키 제거
    func loadSchema(profile: String) throws -> [String: Any] {
        let text = try asset("schema", ext: "json", subdirectory: "skill-core/\(profile)")
        guard var schema = try JSONSerialization.jsonObject(with: Data(text.utf8))
            as? [String: Any] else {
            throw AssetMissing(name: "skill-core/\(profile)/schema.json (parse failed)")
        }
        schema.removeValue(forKey: "$schema")
        schema.removeValue(forKey: "$comment")
        schema.removeValue(forKey: "title")
        return schema
    }

    func analyze(videoURL: String, profile: String, language: String,
                 maxGuides: Int = Settings.maxGuides, duration: Int,
                 geminiKey: String) async throws -> AnalyzeResult {
        let prompt = try buildPrompt(profile: profile, duration: duration,
                                     language: language, maxGuides: maxGuides)
        let schema = try loadSchema(profile: profile)
        var request = URLRequest(
            url: URL(string: "\(Self.base)/\(Self.model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(geminiKey, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "contents": [["parts": [
                ["file_data": ["file_uri": videoURL]],
                ["text": prompt],
            ]]],
            "generationConfig": [
                "response_mime_type": "application/json",
                "response_json_schema": schema,
                "temperature": 0.2,
            ],
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
        if http.statusCode == 429 { throw StepkeeperAPIError.rateLimited }
        guard (200...299).contains(http.statusCode) else {
            throw StepkeeperAPIError.modelFailure("Gemini error (HTTP \(http.statusCode))")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let rawObject = try? JSONSerialization.jsonObject(with: Data(text.utf8))
                  as? [String: Any],
              let videoId = YouTubeURL.videoID(from: videoURL)
        else { throw StepkeeperAPIError.invalidResponse }

        let (analysis, raw) = try AnalysisNormalizer.normalized(
            rawObject: rawObject, duration: duration, profile: profile, language: language)
        return AnalyzeResult(videoId: videoId, analysis: analysis, rawAnalysis: raw)
    }
}

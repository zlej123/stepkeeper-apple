import CryptoKit
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

    /// 코어 analyze.asset_digest와 동일 — rules.md + prompt.md + schema.json 원본 바이트의
    /// sha256 앞 12자. 이 분석이 어떤 프롬프트·스키마로 만들어졌는지 추적하는 근거 (리뷰 #6).
    /// 순서·대상 파일이 코어와 다르면 digest가 갈라져 무의미해진다 — 바꿀 때 코어와 함께.
    func assetDigest(profile: String) -> String? {
        var hasher = SHA256()
        guard let rules = assets.url(forResource: "rules", withExtension: "md",
                                     subdirectory: "skill-core/engine"),
              let rulesData = try? Data(contentsOf: rules) else { return nil }
        hasher.update(data: rulesData)
        for (name, ext) in [("prompt", "md"), ("schema", "json")] {
            if let url = assets.url(forResource: name, withExtension: ext,
                                    subdirectory: "skill-core/\(profile)"),
               let data = try? Data(contentsOf: url) {
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined().prefix(12)
            .lowercased()
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

    /// 구조화 출력 요청 1회 — analyze()와 autoPick()이 공유한다 (에러 매핑·응답 해석 동일).
    func generateJSON(parts: [[String: Any]], schema: [String: Any],
                      geminiKey: String) async throws -> [String: Any] {
        var request = URLRequest(
            url: URL(string: "\(Self.base)/\(Self.model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(geminiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": parts]],
            "generationConfig": [
                "response_mime_type": "application/json",
                "response_json_schema": schema,
                "temperature": 0.2,
            ],
        ])

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
              let responseParts = content["parts"] as? [[String: Any]],
              let text = responseParts.first?["text"] as? String,
              let decoded = try? JSONSerialization.jsonObject(with: Data(text.utf8))
                  as? [String: Any]
        else { throw StepkeeperAPIError.invalidResponse }
        return decoded
    }

    func analyze(videoURL: String, profile: String, language: String,
                 maxGuides: Int = Settings.maxGuides, duration: Int,
                 geminiKey: String) async throws -> AnalyzeResult {
        let prompt = try buildPrompt(profile: profile, duration: duration,
                                     language: language, maxGuides: maxGuides)
        let schema = try loadSchema(profile: profile)
        var rawObject = try await generateJSON(
            parts: [["file_data": ["file_uri": videoURL]], ["text": prompt]],
            schema: schema, geminiKey: geminiKey)
        if let digest = assetDigest(profile: profile) {
            rawObject["_asset_digest"] = digest    // 코어·서버와 같은 메타 (리뷰 #6)
        }
        guard let videoId = YouTubeURL.videoID(from: videoURL) else {
            throw StepkeeperAPIError.invalidResponse
        }

        let (analysis, raw) = try AnalysisNormalizer.normalized(
            rawObject: rawObject, duration: duration, profile: profile, language: language)
        return AnalyzeResult(videoId: videoId, analysis: analysis, rawAnalysis: raw)
    }
}

/// 코어 autopick.py 포팅 — 가이드별 후보 3장을 Gemini vision에 보내 하나(또는 none)를 고르게 한다.
/// 프롬프트·스키마는 코어와 동일하게 유지하되, 사용자에게 보여줄 reason만 문서 언어로 받는다.
extension GeminiAPI {
    struct AutoPick: Sendable, Equatable {
        var slot: String     // "before" | "center" | "after" | "none"
        var reason: String
    }

    static let autoPickPrompt = """
    당신은 시각 가이드용 대표 프레임을 고르는 검수자입니다.
    각 가이드마다 후보 3장(before/center/after)이 순서대로 첨부됩니다.
    가이드의 '보여야 할 것'이 실제로 가장 명확하게 보이는 후보 하나를 고르세요.
    세 장 모두에서 그것이 보이지 않으면 반드시 "none"을 고르세요 — 억지로 고르지 않습니다.
    각 선택에 한 문장 근거(reason)를 답하세요. JSON만 출력합니다.
    """

    /// [String: Any]는 non-Sendable이라 static let으로 둘 수 없다 (Swift 6) — 호출마다 조립
    static var autoPickSchema: [String: Any] { [
        "type": "object",
        "required": ["picks"],
        "properties": ["picks": [
            "type": "array",
            "items": [
                "type": "object",
                "required": ["guide_id", "slot", "reason"],
                "properties": [
                    "guide_id": ["type": "string"],
                    "slot": ["enum": ["before", "center", "after", "none"]],
                    "reason": ["type": "string"],
                ],
            ],
        ]],
    ] }

    /// 후보가 하나도 없는 가이드는 질문에서 빼고, 모델이 빠뜨린 가이드는 "none"으로 채운다
    /// (코어와 동일한 안전 기본값 — 억지 선택 대신 링크 폴백).
    func autoPick(captures: [(guideId: String, phrase: String, whatToShow: String,
                              guideText: String, candidates: [(slot: String, jpeg: Data)])],
                  language: String, geminiKey: String) async throws -> [String: AutoPick] {
        var parts: [[String: Any]] = [["text": Self.autoPickPrompt
            + "\nreason은 \(language) 언어로 작성하세요."]]
        var asked: [String] = []
        for capture in captures where capture.candidates.count == 3 {
            asked.append(capture.guideId)
            parts.append(["text": """
            [\(capture.guideId)] 표현: \(capture.phrase)
            보여야 할 것: \(capture.whatToShow)
            가이드: \(capture.guideText)
            """])
            for candidate in capture.candidates {
                parts.append(["text": "\(capture.guideId) 후보 \(candidate.slot):"])
                parts.append(["inline_data": ["mime_type": "image/jpeg",
                                              "data": candidate.jpeg.base64EncodedString()]])
            }
        }
        guard !asked.isEmpty else { return [:] }

        let object = try await generateJSON(parts: parts, schema: Self.autoPickSchema,
                                            geminiKey: geminiKey)
        var picks: [String: AutoPick] = [:]
        let valid: Set<String> = ["before", "center", "after", "none"]
        for item in (object["picks"] as? [[String: Any]]) ?? [] {
            guard let id = item["guide_id"] as? String, asked.contains(id),
                  let slot = item["slot"] as? String, valid.contains(slot) else { continue }
            picks[id] = AutoPick(slot: slot, reason: (item["reason"] as? String) ?? "")
        }
        for id in asked where picks[id] == nil {
            picks[id] = AutoPick(slot: "none", reason: "")
        }
        return picks
    }
}

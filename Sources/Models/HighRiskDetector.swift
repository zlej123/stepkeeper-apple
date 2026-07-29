import Foundation

/// 고위험 도메인(의료·전기·가스 등) 감지 — 코어 contract.py와 같은 자산
/// (skill-core/engine/highrisk.json)을 읽어 같은 판정을 낸다 (외부 리뷰 3차 P1-3).
///
/// 직접 Gemini 모드는 서버 계약 검증을 거치지 않으므로, 표시는 서버 warnings가 아니라
/// **로컬 감지**에 의존한다 — 어느 경로로 분석했든 같은 고지가 뜬다.
enum HighRiskDetector {
    static let keywords: [String] = {
        guard let url = Bundle.main.url(forResource: "highrisk", withExtension: "json",
                                        subdirectory: "skill-core/engine"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["keywords"] as? [String] else { return [] }
        return list
    }()

    /// 제목·분류·요약에서 매칭된 키워드 (없으면 빈 배열). 오탐을 감수하고 넓게 잡는다 —
    /// 고지는 분석을 막지 않는다.
    static func hits(in texts: String?...) -> [String] {
        let blob = texts.compactMap { $0 }.joined(separator: " ").lowercased()
        guard !blob.isEmpty else { return [] }
        return keywords.filter { blob.contains($0.lowercased()) }
    }
}

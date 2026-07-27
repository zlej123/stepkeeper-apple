import Foundation

/// 문서 화면이 그리는 **본문** 라벨. 코어 템플릿(skill-core/<profile>/template[.<lang>].md)과 같은
/// 규칙으로 **문서의 출력 언어**를 따른다 — 시스템 언어를 따르는 UI 크롬(툴바·안내 메시지)과 다르다.
/// 한국어로 만든 문서를 영어 기기에서 열어도 본문은 한국어로 남아야 하고, 그 반대도 마찬가지다.
struct DocumentStrings: Sendable {
    var ingredients: String          // 요리 프로파일의 재료 절 제목
    var materials: String            // 범용 프로파일의 준비물 절 제목
    var steps: String                // 순서 절 제목
    var category: String             // 분류 라벨
    var sourceLink: String           // Notion·PDF 상단의 원본 영상 링크 문구
    var guidePrefix: @Sendable (String) -> String   // 가이드 문구 접두사
    var seeAt: @Sendable (String?) -> String        // 타임스탬프 링크 문구 (nil = 시각 불명)
    var source: @Sendable (String) -> String        // 출처 줄

    static let english = DocumentStrings(
        ingredients: "Ingredients", materials: "What you need",
        steps: "Steps", category: "Category", sourceLink: "Watch on YouTube",
        guidePrefix: { phrase in "What '\(phrase)' looks like:" },
        seeAt: { time in time.map { "▶ See it in the video at \($0)" } ?? "▶ See it in the video" },
        source: { title in "From \(title) — kept with stepkeeper" })

    static let korean = DocumentStrings(
        ingredients: "준비 재료", materials: "준비물",
        steps: "순서", category: "분류", sourceLink: "YouTube 원본",
        guidePrefix: { phrase in "'\(phrase)' 기준:" },
        seeAt: { time in time.map { "▶ 영상 \($0)에서 직접 확인" } ?? "▶ 영상에서 직접 확인" },
        source: { title in "출처: \(title) — stepkeeper로 생성" })

    static let japanese = DocumentStrings(
        ingredients: "材料", materials: "用意するもの",
        steps: "手順", category: "カテゴリ", sourceLink: "YouTube で見る",
        guidePrefix: { phrase in "「\(phrase)」とは:" },
        seeAt: { time in time.map { "▶ 動画の \($0) で確認" } ?? "▶ 動画で確認" },
        source: { title in "出典: \(title) — stepkeeper で作成" })

    /// 번역본이 없는 언어는 영어 (코어 load_template의 폴백과 동일)
    static func forLanguage(_ language: String) -> DocumentStrings {
        switch language {
        case "ko": korean
        case "ja": japanese
        default: english
        }
    }

    /// 요리 프로파일은 "Ingredients", 그 외는 "What you need"
    func needsTitle(isRecipe: Bool, servings: String?) -> String {
        let base = isRecipe ? ingredients : materials
        guard isRecipe, let servings, !servings.isEmpty else { return base }
        return "\(base) (\(servings))"
    }

    /// 요리 프로파일의 순서 절 제목은 코어의 한국어("조리 순서")·일본어("作り方") 템플릿에서만 다르다
    func stepsTitle(isRecipe: Bool) -> String {
        guard isRecipe else { return steps }
        if self == .korean { return "조리 순서" }
        if self == .japanese { return "作り方" }
        return steps
    }
}

extension DocumentStrings: Equatable {
    static func == (lhs: DocumentStrings, rhs: DocumentStrings) -> Bool {
        lhs.ingredients == rhs.ingredients && lhs.materials == rhs.materials
            && lhs.steps == rhs.steps && lhs.category == rhs.category
    }
}

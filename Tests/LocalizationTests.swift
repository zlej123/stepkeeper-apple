import Testing
import Foundation
@testable import stepkeeper

/// 앱 UI는 **시스템 언어**(String Catalog), 문서 본문은 **문서 언어**(DocumentStrings)를 따른다.
/// 이 둘이 섞이면 "영어 기기에서 한국어 문서를 열었더니 본문까지 영어" 같은 회귀가 난다.
struct LocalizationTests {
    @Test func koreanCatalogIsBundledAndTranslates() throws {
        let path = try #require(Bundle.main.path(forResource: "ko", ofType: "lproj"),
                                "ko 번역이 번들에 없음 — Localizable.xcstrings가 리소스로 안 들어갔다")
        let korean = try #require(Bundle(path: path))
        // 소스 문자열(영어)이 키다
        #expect(korean.localizedString(forKey: "Save key", value: nil, table: nil) == "키 저장")
        #expect(korean.localizedString(forKey: "Make document", value: nil, table: nil) == "문서 만들기")
        #expect(korean.localizedString(forKey: "Add your Gemini API key in Settings",
                                       value: nil, table: nil) == "설정에서 Gemini API 키를 입력하세요")
    }

    @Test func baseLanguageIsEnglish() throws {
        let development = try #require(Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDevelopmentRegion") as? String)
        #expect(development == "en")
    }

    @Test func documentStringsFollowDocumentLanguageNotSystem() {
        let korean = DocumentStrings.forLanguage("ko")
        let english = DocumentStrings.forLanguage("en")
        #expect(korean.steps == "순서")
        #expect(korean.guidePrefix("한입 크기") == "'한입 크기' 기준:")
        #expect(korean.source("영상") == "출처: 영상 — stepkeeper로 생성")
        #expect(english.steps == "Steps")
        #expect(english.guidePrefix("bite-sized") == "What 'bite-sized' looks like:")
        let japanese = DocumentStrings.forLanguage("ja")
        #expect(japanese.steps == "手順")
        #expect(japanese.guidePrefix("一口大") == "「一口大」とは:")
        #expect(japanese.stepsTitle(isRecipe: true) == "作り方")   // 코어 recipe/template.ja.md
        // 번역본이 없는 언어는 코어 load_template과 같이 영어로 (한국어로 새지 않는다)
        #expect(DocumentStrings.forLanguage("de").steps == "Steps")
        #expect(DocumentStrings.forLanguage("").steps == "Steps")
    }

    @Test func recipeAndGenericTitlesMatchCoreTemplates() {
        let korean = DocumentStrings.korean, english = DocumentStrings.english
        #expect(korean.needsTitle(isRecipe: true, servings: "2인분") == "준비 재료 (2인분)")
        #expect(korean.needsTitle(isRecipe: false, servings: nil) == "준비물")
        #expect(korean.stepsTitle(isRecipe: true) == "조리 순서")     // 코어 recipe/template.ko.md
        #expect(english.needsTitle(isRecipe: true, servings: "2 servings") == "Ingredients (2 servings)")
        #expect(english.needsTitle(isRecipe: false, servings: nil) == "What you need")
        #expect(english.stepsTitle(isRecipe: true) == "Steps")        // 코어 recipe/template.md
    }

    @Test func timestampFallbackKeepsLinkWithoutTime() {
        #expect(DocumentStrings.english.seeAt(nil) == "▶ See it in the video")
        #expect(DocumentStrings.english.seeAt("1:23") == "▶ See it in the video at 1:23")
        #expect(DocumentStrings.korean.seeAt(nil) == "▶ 영상에서 직접 확인")
        #expect(DocumentStrings.korean.seeAt("1:23") == "▶ 영상 1:23에서 직접 확인")
    }
}

import Testing
import Foundation
@testable import stepkipper

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
        #expect(korean.localizedString(forKey: "2. Click \"Create API key\"",
                                       value: nil, table: nil) == "2. \"API 키 만들기\" 클릭")
    }

    @Test func interpolatedRuntimeKeysTranslateAndFormat() throws {
        let path = try #require(Bundle.main.path(forResource: "ko", ofType: "lproj"))
        let korean = try #require(Bundle(path: path))

        let analyzing = korean.localizedString(
            forKey: "Analyzing the video… (%@, %@)", value: nil, table: nil)
        #expect(String(format: analyzing, "1:02", "recipe") == "영상 분석 중… (1:02, recipe)")

        let capturing = korean.localizedString(
            forKey: "Capturing frames… %lld/%lld", value: nil, table: nil)
        #expect(String(format: capturing, Int64(2), Int64(5)) == "장면 캡처 중… 2/5")

        let length = korean.localizedString(forKey: "Length %@", value: nil, table: nil)
        #expect(String(format: length, "1:02") == "길이 1:02")

        let failed = korean.localizedString(forKey: "%@ capture failed", value: nil, table: nil)
        #expect(String(format: failed, "1:02") == "1:02 캡처 실패")
    }

    @Test func pickerAccessibilityVocabularyIsTranslated() throws {
        let path = try #require(Bundle.main.path(forResource: "ko", ofType: "lproj"))
        let korean = try #require(Bundle(path: path))
        #expect(korean.localizedString(forKey: "Before", value: nil, table: nil) == "이전 장면")
        #expect(korean.localizedString(forKey: "Key moment", value: nil, table: nil) == "핵심 장면")
        #expect(korean.localizedString(forKey: "After", value: nil, table: nil) == "이후 장면")
        #expect(korean.localizedString(forKey: "Use video link instead",
                                       value: nil, table: nil) == "대신 영상 링크 사용")
        #expect(korean.localizedString(forKey: "Selected", value: nil, table: nil) == "선택됨")
        #expect(korean.localizedString(forKey: "Not selected",
                                       value: nil, table: nil) == "선택 안 됨")
    }

    @Test func completionAndGeminiRecoveryStringsAreTranslated() throws {
        let path = try #require(Bundle.main.path(forResource: "ko", ofType: "lproj"))
        let korean = try #require(Bundle(path: path))
        let expected = [
            ("Close", "닫기"),
            ("Saved to Recent", "최근 문서에 저장됨"),
            ("Open Settings", "설정 열기"),
            ("Edit URL", "URL 수정"),
            ("Doesn't fit\nuse a link", "부적합\n링크 사용"),
            ("Saved.\nOpen stepkipper to start the analysis.",
             "저장됐습니다.\nstepkipper를 열면 분석이 시작됩니다."),
            ("stepkipper server (optional)", "stepkipper 서버 (선택)"),
            ("— Written by the report button in the stepkipper app.",
             "— 이 메일은 stepkipper 앱의 이상 신고 버튼으로 작성됐습니다."),
            ("Gemini rejected this API key — check it in Settings",
             "Gemini가 이 API 키를 거부했습니다 — 설정에서 확인하세요"),
            ("Gemini denied access — check API access and key restrictions",
             "Gemini 접근이 거부되었습니다 — API 사용 설정과 키 제한을 확인하세요"),
            ("Couldn't reach Gemini — check your internet connection",
             "Gemini에 연결할 수 없습니다 — 인터넷 연결을 확인하세요"),
        ]
        for (key, translation) in expected {
            #expect(korean.localizedString(forKey: key, value: nil, table: nil) == translation)
        }
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
        #expect(korean.source("영상") == "출처: 영상 — stepkipper로 생성")
        #expect(english.steps == "Steps")
        #expect(english.guidePrefix("bite-sized") == "What 'bite-sized' looks like:")
        #expect(english.source("Video") == "From Video — kept with stepkipper")
        let japanese = DocumentStrings.forLanguage("ja")
        #expect(japanese.steps == "手順")
        #expect(japanese.guidePrefix("一口大") == "「一口大」とは:")
        #expect(japanese.stepsTitle(isRecipe: true) == "作り方")   // 코어 recipe/template.ja.md
        #expect(japanese.source("動画") == "出典: 動画 — stepkipper で作成")
        // 번역본이 없는 언어는 코어 load_template과 같이 영어로 (한국어로 새지 않는다)
        #expect(DocumentStrings.forLanguage("de").steps == "Steps")
        #expect(DocumentStrings.forLanguage("").steps == "Steps")
    }

    @Test func bundledSkillCoreKeepsStepkipperBrandAfterSync() throws {
        let legacyPhrases = [
            "kept with stepkeeper",
            "stepkeeper로 생성",
            "stepkeeper で作成",
        ]
        for profile in ["generic", "recipe"] {
            for language in ["", "ko", "ja"] {
                let template = try Templates.load(profile: profile, language: language)
                #expect(template.contains("stepkipper"))
                for phrase in legacyPhrases {
                    #expect(!template.contains(phrase))
                }
            }
            let schemaURL = try #require(Bundle.main.url(
                forResource: "schema", withExtension: "json",
                subdirectory: "skill-core/\(profile)"))
            let schema = try String(contentsOf: schemaURL, encoding: .utf8)
            #expect(schema.contains("stepkipper \(profile) analysis result"))
        }
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

struct AutoPickStringsTests {
    /// 보간이 들어간 문구는 키가 형식 지정자로 바뀐다 — 카탈로그 키와 어긋나면 영어로 새어나온다.
    @Test func interpolatedStatLineIsTranslated() throws {
        let path = try #require(Bundle.main.path(forResource: "ko", ofType: "lproj"))
        let korean = try #require(Bundle(path: path))
        let format = korean.localizedString(
            forKey: "You kept %lld of %lld AI picks", value: nil, table: nil)
        #expect(format != "You kept %lld of %lld AI picks")     // 번역이 실제로 있다
        #expect(String(format: format, 3, 5) == "AI 선택 5개 중 3개를 그대로 뒀습니다")
    }
}

struct HighRiskDetectorTests {
    /// 코어 contract.py와 같은 자산(skill-core/engine/highrisk.json)이 번들에 있고,
    /// 같은 키워드로 같은 판정을 낸다 (외부 리뷰 3차 P1-3 — 직접 Gemini 모드도 커버).
    @Test func bundledAssetDetectsSameKeywordsAsCore() {
        #expect(!HighRiskDetector.keywords.isEmpty)   // 자산 누락 시 감지가 조용히 꺼진다
        #expect(HighRiskDetector.hits(in: "콘센트 전기 배선 교체하기") == ["전기 배선"])
        #expect(!HighRiskDetector.hits(in: "Repairing the Circuit Breaker panel").isEmpty)
        #expect(HighRiskDetector.hits(in: "돼지고기 김치볶음", "요리", "간단한 레시피").isEmpty)
        #expect(HighRiskDetector.hits(in: nil, nil).isEmpty)
    }
}

import Testing
import Foundation
@testable import stepkeeper

struct MarkdownBuilderGoldenTests {
    struct GoldenCase: Codable {
        var videoId: String
        var imageRefs: [String: String]
        enum CodingKeys: String, CodingKey {
            case videoId = "video_id"
            case imageRefs = "image_refs"
        }
    }

    @Test func hmsMatchesCore() {
        #expect(MarkdownBuilder.hms(0) == "0:00")
        #expect(MarkdownBuilder.hms(59) == "0:59")
        #expect(MarkdownBuilder.hms(754) == "12:34")
        #expect(MarkdownBuilder.hms(3700) == "61:40")   // 시간 단위 없음 — 코어와 동일
    }

    // recipe-en: _output_language에 따라 템플릿(문서 뼈대)이 바뀌는지 코어 출력과 대조
    @Test(arguments: ["generic-mixed", "generic-links-only", "recipe-mixed", "recipe-en"])
    func matchesCoreRenderOutput(caseName: String) throws {
        let sub = "Fixtures/golden/\(caseName)"
        let analysis = try JSONDecoder().decode(
            Analysis.self, from: Bundle.fixtureData("analysis", subdirectory: sub))
        let golden = try JSONDecoder().decode(
            GoldenCase.self, from: Bundle.fixtureData("case", subdirectory: sub))
        let expected = String(
            data: try Bundle.fixtureData("expected", ext: "md", subdirectory: sub),
            encoding: .utf8)!
        let out = try MarkdownBuilder.markdown(
            videoId: golden.videoId, analysis: analysis, imageRefs: golden.imageRefs)
        #expect(out == expected)
    }
}

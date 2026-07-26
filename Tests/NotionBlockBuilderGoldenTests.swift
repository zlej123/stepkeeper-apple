import Testing
import Foundation
@testable import stepkeeper

struct NotionBlockBuilderGoldenTests {
    // recipe-en: Notion 절 제목도 문서 언어를 따르는지 코어 출력과 대조
    @Test(arguments: ["generic-mixed", "generic-links-only", "recipe-mixed", "recipe-en"])
    func matchesCoreBlocks(caseName: String) throws {
        let sub = "Fixtures/golden/\(caseName)"
        let analysis = try JSONDecoder().decode(
            Analysis.self, from: Bundle.fixtureData("analysis", subdirectory: sub))
        let golden = try JSONDecoder().decode(
            MarkdownBuilderGoldenTests.GoldenCase.self,
            from: Bundle.fixtureData("case", subdirectory: sub))
        let expected = try JSONSerialization.jsonObject(
            with: Bundle.fixtureData("expected-notion", subdirectory: sub)) as! NSArray

        let imageIds = Dictionary(uniqueKeysWithValues:
            golden.imageRefs.keys.map { ($0, "fake-\($0)") })
        let produced = NotionBlockBuilder.blocks(
            analysis: analysis, videoId: golden.videoId, imageUploadIds: imageIds)
        // Swift 딕셔너리 → JSON 왕복 후 NSArray 동등 비교 (키 순서 무관, 값·구조 단위)
        let roundTripped = try JSONSerialization.jsonObject(
            with: JSONSerialization.data(withJSONObject: produced)) as! NSArray
        #expect(roundTripped == expected)
    }
}

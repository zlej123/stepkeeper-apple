import Testing
import Foundation
@testable import stepkipper

struct AnalysisNormalizerTests {
    @Test func convertsTimeStrings() {
        #expect(AnalysisNormalizer.mmssToSec("12:34") == 754)
        #expect(AnalysisNormalizer.mmssToSec("1:02") == 62)
        #expect(AnalysisNormalizer.mmssToSec("0:00") == 0)
        #expect(AnalysisNormalizer.mmssToSec(30) == 30)          // 이미 숫자
        #expect(AnalysisNormalizer.mmssToSec(nil) == nil)
        #expect(AnalysisNormalizer.mmssToSec("abc") == nil)
    }

    @Test func normalizesDictAndInjectsMeta() throws {
        let rawObject: [String: Any] = [
            "title": "제목", "summary": "요약", "category": "생활",
            "materials": [["name": "글루건", "amount": "1개"]],
            "steps": [["id": 1, "summary": "s", "detail": "d",
                       "t_start": "0:05", "t_end": "0:20"]],
            "visual_guides": [
                ["id": "vg-1", "step_id": 1, "source_phrase": "sp", "phrase": "p",
                 "type": "state", "what_to_show": "w",
                 "best_visual_timestamp": "0:12", "guide_text": "g", "importance": 0.9],
                ["id": "vg-2", "step_id": 1, "source_phrase": "sp", "phrase": "p",
                 "type": "state", "what_to_show": "w",
                 "best_visual_timestamp": NSNull(), "guide_text": "g", "importance": 0.5],
            ],
        ]
        let (analysis, raw) = try AnalysisNormalizer.normalized(
            rawObject: rawObject, duration: 90, profile: "generic", language: "ko")
        #expect(analysis.steps[0].tStart == 5 && analysis.steps[0].tEnd == 20)
        #expect(analysis.visualGuides[0].bestVisualTimestamp == 12)
        #expect(analysis.visualGuides[1].bestVisualTimestamp == nil)
        #expect(analysis.duration == 90 && analysis.profile == "generic")
        let rawDict = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        #expect(rawDict["_output_language"] as? String == "ko")   // 메타 주입 보존
    }
}

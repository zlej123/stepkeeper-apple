import Testing
import Foundation
@testable import stepkeeper

@MainActor
struct CapturePipelineTests {
    private func makeModel(root: URL) -> AppModel {
        let keychain = KeychainStore(service: "stepkeeper.tests.capture-\(UUID().uuidString)")
        try? keychain.save("test-key")
        let defaults = UserDefaults(suiteName: "stepkeeper.tests.capture")!
        defaults.removePersistentDomain(forName: "stepkeeper.tests.capture")
        Settings.registerDefaults(defaults)
        return AppModel(keychain: keychain, documentStore: DocumentStore(root: root),
                        defaults: defaults)
    }
    private func makeResult() throws -> AnalyzeResult {
        let data = try Bundle.fixtureData("analyze-response")
        let envelope = try JSONDecoder().decode(AnalyzeEnvelope.self, from: data)
        let raw = try JSONSerialization.data(withJSONObject:
            (try JSONSerialization.jsonObject(with: data) as! [String: Any])["analysis"]!)
        return AnalyzeResult(videoId: envelope.videoId,
                             analysis: envelope.analysis, rawAnalysis: raw)
    }
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])

    @Test func defaultPicksPrefersCenterElseNone() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let result = try makeResult()
        let vg1 = result.analysis.visualGuides[0]   // vg-1
        let vg2 = result.analysis.visualGuides[1]   // vg-2 — center 실패 케이스로 사용
        model.captures = [
            GuideCapture(guide: vg1, candidates: [
                CaptureCandidate(slot: "before", time: 20, jpeg: jpeg),
                CaptureCandidate(slot: "center", time: 30, jpeg: jpeg),
                CaptureCandidate(slot: "after", time: 56, jpeg: jpeg),
            ]),
            GuideCapture(guide: vg2, candidates: [
                CaptureCandidate(slot: "before", time: 4, jpeg: nil),
                CaptureCandidate(slot: "center", time: 10, jpeg: nil),
                CaptureCandidate(slot: "after", time: 21, jpeg: nil),
            ]),
        ]
        let picks = model.defaultPicks()
        #expect(picks["vg-1"] == "center")
        #expect(picks["vg-2"] == "none")
    }

    @Test func finishPickingSavesPickedImageAndLinksOthers() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let result = try makeResult()
        model.pendingResult = result
        model.captures = [GuideCapture(guide: result.analysis.visualGuides[0], candidates: [
            CaptureCandidate(slot: "before", time: 20, jpeg: nil),
            CaptureCandidate(slot: "center", time: 30, jpeg: jpeg),
            CaptureCandidate(slot: "after", time: 56, jpeg: nil),
        ])]

        await model.finishPicking(picks: ["vg-1": "center"])

        guard case .done(let meta) = model.stage else {
            Issue.record("stage=\(model.stage)"); return
        }
        let doc = model.document(id: meta.id)!
        #expect(doc.markdown.contains("![요만큼](vg-1.jpg)"))
        #expect(doc.picks["vg-1"] == "center")
        let image = doc.folder.appendingPathComponent("vg-1.jpg")
        #expect(try Data(contentsOf: image) == jpeg)
        // vg-2는 timestamp null — 이미지도 ?t= 링크도 없어야 함 (골든과 동일 규칙)
        #expect(!doc.markdown.contains("vg-2.jpg"))
    }

    @Test func finishPickingWithNoneFallsBackToLink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let result = try makeResult()
        model.pendingResult = result
        model.captures = [GuideCapture(guide: result.analysis.visualGuides[0], candidates: [
            CaptureCandidate(slot: "center", time: 30, jpeg: jpeg),
        ])]

        await model.finishPicking(picks: ["vg-1": "none"])

        guard case .done(let meta) = model.stage else {
            Issue.record("stage=\(model.stage)"); return
        }
        let doc = model.document(id: meta.id)!
        #expect(doc.markdown.contains("▶ [영상 0:30에서 직접 확인](https://youtu.be/dQw4w9WgXcQ?t=30)"))
        #expect(!FileManager.default.fileExists(
            atPath: doc.folder.appendingPathComponent("vg-1.jpg").path))
    }
}

import Testing
import Foundation
@testable import clipnote

struct DocumentStoreTests {
    private func makeStore() throws -> (DocumentStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipnote-tests-\(UUID().uuidString)")
        return (DocumentStore(root: root), root)
    }
    private func sampleAnalysis() throws -> (Analysis, Data) {
        let data = try Bundle.fixtureData("analyze-response")
        let envelope = try JSONDecoder().decode(AnalyzeEnvelope.self, from: data)
        let raw = try JSONSerialization.data(
            withJSONObject: (try JSONSerialization.jsonObject(with: data) as! [String: Any])["analysis"]!)
        return (envelope.analysis, raw)
    }

    /// 폴더 내보내기는 비동기로 바뀌었다 — 결과 메시지 계약(성공 nil / 실패 문자열)과 실제 복사 검증
    @Test func exportCopiesFolderAndReportsFailure() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let meta = try store.save(videoId: "exp0000000A", title: "내보내기", analysis: analysis,
                                  rawAnalysis: raw, picks: ["vg-1": "center"],
                                  images: ["vg-1.jpg": Data([0xFF, 0xD8])], markdown: "# 문서")
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        #expect(await ExportHelper.copyFolder(from: store.folderURL(id: meta.id),
                                              to: destination, name: meta.id) == nil)
        let copied = destination.appendingPathComponent(meta.id)
        #expect(FileManager.default.fileExists(atPath: copied.appendingPathComponent("document.md").path))
        #expect(FileManager.default.fileExists(atPath: copied.appendingPathComponent("vg-1.jpg").path))
        // 같은 이름으로 다시 내보내면 덮어쓴다 (기존 폴더 제거 후 복사)
        #expect(await ExportHelper.copyFolder(from: store.folderURL(id: meta.id),
                                              to: destination, name: meta.id) == nil)

        let missing = root.appendingPathComponent("없는폴더", isDirectory: true)
        let message = await ExportHelper.copyFolder(from: missing, to: destination, name: "x")
        #expect(message?.hasPrefix("저장 실패:") == true)
    }

    @Test func listSkipsBrokenFoldersButKeepsGoodOnes() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let good = try store.save(videoId: "ok00000000A", title: "정상", analysis: analysis,
                                  rawAnalysis: raw, picks: [:], images: [:], markdown: "#")
        // meta.json이 없는 폴더와 깨진 JSON 폴더 — 둘 다 목록을 막지 않아야 한다
        let empty = root.appendingPathComponent("no-meta")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let corrupt = root.appendingPathComponent("bad-meta")
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: corrupt.appendingPathComponent("meta.json"))

        let listed = try store.list()
        #expect(listed.map(\.id) == [good.id])
    }

    @Test func saveWritesAllFilesAndListLoadsBack() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        let meta = try store.save(
            videoId: "dQw4w9WgXcQ", title: analysis.title, analysis: analysis,
            rawAnalysis: raw, picks: ["vg-1": "center", "vg-2": "none"],
            images: ["vg-1.jpg": jpeg], markdown: "## 문서\n")

        #expect(meta.id.hasPrefix("dQw4w9WgXcQ-"))
        let folder = store.folderURL(id: meta.id)
        for name in ["document.md", "meta.json", "analysis.json", "picks.json", "vg-1.jpg"] {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path),
                    "missing \(name)")
        }
        #expect(try Data(contentsOf: folder.appendingPathComponent("vg-1.jpg")) == jpeg)

        let listed = try store.list()
        #expect(listed.count == 1 && listed[0].title == "테스트 하우투 영상")

        let doc = try store.load(id: meta.id)
        #expect(doc.analysis == analysis)
        #expect(doc.picks == ["vg-1": "center", "vg-2": "none"])
        #expect(doc.markdown == "## 문서\n")

        try store.delete(id: meta.id)
        #expect(try store.list().isEmpty)
    }

    @Test func savedAnalysisJSONPreservesUnknownKeys() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let meta = try store.save(videoId: "v", title: "t", analysis: analysis,
                                  rawAnalysis: raw, picks: [:], images: [:], markdown: "m\n")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf:
            store.folderURL(id: meta.id).appendingPathComponent("analysis.json"))) as! [String: Any]
        #expect(saved["_model"] as? String == "gemini-flash-lite-latest")
    }

    @Test func listSortsByCreatedAtDescending() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let first = try store.save(videoId: "aaaaaaaaaaa", title: "먼저", analysis: analysis,
                                   rawAnalysis: raw, picks: [:], images: [:], markdown: "1\n")
        let second = try store.save(videoId: "bbbbbbbbbbb", title: "나중", analysis: analysis,
                                    rawAnalysis: raw, picks: [:], images: [:], markdown: "2\n")
        #expect(first.id != second.id)   // 같은 초에 저장돼도 id 유일
        let listed = try store.list()
        #expect(listed.first?.title == "나중")
    }

    @Test func sameSecondSavesGetUniqueIDs() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try store.save(videoId: "dQw4w9WgXcQ", title: "1", analysis: analysis,
                                   rawAnalysis: raw, picks: [:], images: [:], markdown: "1\n", now: t)
        let second = try store.save(videoId: "dQw4w9WgXcQ", title: "2", analysis: analysis,
                                    rawAnalysis: raw, picks: [:], images: [:], markdown: "2\n", now: t)
        #expect(first.id != second.id)
        #expect(second.id == "\(first.id)-2")
        #expect(try store.list().count == 2)
    }

    @Test func listOrdersBySubSecondTimeNotVideoId() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        // 알파벳 내림차순이면 zzz가 먼저 — 시간순(나중 저장 aaa)이 이겨야 한다
        _ = try store.save(videoId: "zzzzzzzzzzz", title: "먼저", analysis: analysis,
                           rawAnalysis: raw, picks: [:], images: [:], markdown: "1\n", now: t)
        _ = try store.save(videoId: "aaaaaaaaaaa", title: "나중", analysis: analysis,
                           rawAnalysis: raw, picks: [:], images: [:], markdown: "2\n",
                           now: t.addingTimeInterval(0.05))
        let listed = try store.list()
        #expect(listed.map(\.title) == ["나중", "먼저"])
        let doc = try store.load(id: listed[0].id)   // load의 meta/folder 라운드트립 보완 검증
        #expect(doc.meta.title == "나중")
        #expect(doc.folder.lastPathComponent == listed[0].id)
    }
}

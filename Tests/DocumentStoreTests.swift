import Testing
import Foundation
@testable import stepkipper

struct DocumentStoreTests {
    private func makeStore() throws -> (DocumentStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkipper-tests-\(UUID().uuidString)")
        return (DocumentStore(root: root), root)
    }
    private func sampleAnalysis() throws -> (Analysis, Data) {
        let data = try Bundle.fixtureData("analyze-response")
        let envelope = try JSONDecoder().decode(AnalyzeEnvelope.self, from: data)
        let raw = try JSONSerialization.data(
            withJSONObject: (try JSONSerialization.jsonObject(with: data) as! [String: Any])["analysis"]!)
        return (envelope.analysis, raw)
    }

    /// 기존 내보내기를 덮어쓰지 않고 실제 선택한 유일 이름을 돌려준다.
    @Test func exportCopiesFolderWithoutOverwritingAndReportsFailure() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let meta = try store.save(videoId: "exp0000000A", title: "내보내기", analysis: analysis,
                                  rawAnalysis: raw, picks: ["vg-1": "center"],
                                  images: ["vg-1.jpg": Data([0xFF, 0xD8])], markdown: "# 문서")
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        #expect(await ExportHelper.copyFolder(from: store.folderURL(id: meta.id),
                                              to: destination, name: meta.id)
                == .success(name: meta.id))
        let copied = destination.appendingPathComponent(meta.id)
        #expect(FileManager.default.fileExists(atPath: copied.appendingPathComponent("document.md").path))
        #expect(FileManager.default.fileExists(atPath: copied.appendingPathComponent("vg-1.jpg").path))

        // 사용자가 첫 내보내기를 수정했어도 다음 내보내기가 보존해야 한다.
        let preserved = Data("사용자 수정본".utf8)
        try preserved.write(to: copied.appendingPathComponent("document.md"))
        #expect(await ExportHelper.copyFolder(from: store.folderURL(id: meta.id),
                                              to: destination, name: meta.id)
                == .success(name: "\(meta.id)-2"))
        #expect(try Data(contentsOf: copied.appendingPathComponent("document.md")) == preserved)
        #expect(FileManager.default.fileExists(atPath: destination
            .appendingPathComponent("\(meta.id)-2/document.md").path))

        let missing = root.appendingPathComponent("없는폴더", isDirectory: true)
        let result = await ExportHelper.copyFolder(from: missing, to: destination, name: "x")
        guard case .failure(let message) = result else {
            Issue.record("없는 원본 폴더 내보내기가 성공함")
            return
        }
        #expect(message.contains(":"))
    }

    @Test func concurrentExportsChooseDistinctNames() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let meta = try store.save(videoId: "race000000A", title: "경합", analysis: analysis,
                                  rawAnalysis: raw, picks: [:], images: [:], markdown: "# 경합")
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let results: [ExportHelper.Result] = await withTaskGroup(
            of: ExportHelper.Result.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await ExportHelper.copyFolder(
                        from: store.folderURL(id: meta.id), to: destination, name: meta.id)
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let names = results.compactMap { result -> String? in
            guard case .success(let name) = result else { return nil }
            return name
        }

        #expect(names.count == 6)
        #expect(Set(names).count == 6)
        #expect(Set(names) == Set([
            meta.id, "\(meta.id)-2", "\(meta.id)-3",
            "\(meta.id)-4", "\(meta.id)-5", "\(meta.id)-6",
        ]))
        for name in names {
            #expect(FileManager.default.fileExists(atPath:
                destination.appendingPathComponent(name)
                    .appendingPathComponent("document.md").path))
        }
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

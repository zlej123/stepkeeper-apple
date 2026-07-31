import Testing
import Foundation
@testable import stepkipper

@Suite(.serialized)
struct ShareInboxTests {
    private func reset() {
        ShareInbox.defaults?.removeObject(forKey: ShareInbox.urlKey)
    }

    @Test func fifoKeepsEveryShareInOrder() {
        reset(); defer { reset() }
        // 회귀 방지 (리뷰 3차 P2): 예전엔 단일 값이라 두 번째 공유가 첫 번째를 조용히 덮어썼다
        ShareInbox.push("https://youtu.be/video000001")
        ShareInbox.push("https://youtu.be/video000002")
        #expect(ShareInbox.pendingCount == 2)
        #expect(ShareInbox.pop() == "https://youtu.be/video000001")
        #expect(ShareInbox.pop() == "https://youtu.be/video000002")
        #expect(ShareInbox.pop() == nil)
    }

    @Test func duplicateShareIsKeptOnce() {
        reset(); defer { reset() }
        ShareInbox.push("https://youtu.be/video000001")
        ShareInbox.push("https://youtu.be/video000001")   // 같은 영상 연타
        #expect(ShareInbox.pendingCount == 1)
    }

    @Test func capacityDropsOldestFirst() {
        reset(); defer { reset() }
        for index in 0..<(ShareInbox.capacity + 3) {
            ShareInbox.push("https://youtu.be/video\(String(format: "%06d", index))")
        }
        #expect(ShareInbox.pendingCount == ShareInbox.capacity)
        #expect(ShareInbox.pop() == "https://youtu.be/video000003")   // 가장 오래된 3개가 밀려남
    }

    @Test @MainActor
    func automaticPickupStartsOnlyFromIdleAndNeverConsumesBlockedWork() async {
        reset(); defer { reset() }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkipper-share-policy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            keychain: InMemorySecretStore(nil),
            documentStore: DocumentStore(root: root))
        let done = DocumentMeta(
            id: "done", title: "Done", videoId: "video000001",
            profile: "generic", language: "ko", createdAt: .now)
        let blockedStages: [FlowStage] = [
            .analyzing(duration: 90),
            .picking,
            .failed("Keep this error visible"),
            .done(done),
        ]

        for (index, blockedStage) in blockedStages.enumerated() {
            let url = "blocked-\(index)"
            ShareInbox.push(url)
            model.stage = blockedStage

            #expect(model.startNextShared(trigger: .automatic) == false)
            #expect(model.stage == blockedStage)
            #expect(ShareInbox.pop() == url)
        }

        ShareInbox.push("idle-start")
        model.stage = .idle
        #expect(model.startNextShared(trigger: .automatic))
        #expect(model.stage == .loadingPlayer)
        #expect(ShareInbox.pendingCount == 0)
        await Task.yield()
    }

    @Test @MainActor
    func userInitiatedPickupBlocksInProgressButAllowsTerminalStages() async {
        reset(); defer { reset() }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkipper-share-policy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(
            keychain: InMemorySecretStore(nil),
            documentStore: DocumentStore(root: root))

        ShareInbox.push("keep-while-busy")
        model.stage = .capturing(current: 1, total: 3)
        #expect(model.startNextShared() == false)
        #expect(model.stage == .capturing(current: 1, total: 3))
        #expect(ShareInbox.pop() == "keep-while-busy")

        let terminalStages: [FlowStage] = [
            .failed("The user saw this error"),
            .done(DocumentMeta(
                id: "done", title: "Done", videoId: "video000001",
                profile: "generic", language: "ko", createdAt: .now)),
        ]
        for (index, terminalStage) in terminalStages.enumerated() {
            ShareInbox.push("terminal-start-\(index)")
            model.stage = terminalStage

            #expect(model.startNextShared())
            #expect(model.stage == .loadingPlayer)
            #expect(ShareInbox.pendingCount == 0)
            // URL/키 검사까지 Task를 진행시켜 다음 terminal 상태 테스트가 명시적 시작 조건을 갖게 한다.
            await Task.yield()
        }
    }
}

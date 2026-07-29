import Testing
import Foundation
@testable import stepkeeper

@Suite(.serialized)
struct ShareInboxTests {
    private func reset() {
        ShareInbox.defaults?.removeObject(forKey: ShareInbox.urlKey)
        ShareInbox.defaults?.removeObject(forKey: ShareInbox.legacyURLKey)
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

    @Test func legacySingleValueIsAbsorbedFirst() {
        reset(); defer { reset() }
        // 구 버전 확장이 남긴 단일 값은 큐 맨 앞으로 흡수된다 (업그레이드 직후 공유 유실 방지)
        ShareInbox.defaults?.set("https://youtu.be/legacy00001", forKey: ShareInbox.legacyURLKey)
        ShareInbox.push("https://youtu.be/video000001")
        #expect(ShareInbox.pop() == "https://youtu.be/legacy00001")
        #expect(ShareInbox.pop() == "https://youtu.be/video000001")
        #expect(ShareInbox.defaults?.string(forKey: ShareInbox.legacyURLKey) == nil)
    }
}

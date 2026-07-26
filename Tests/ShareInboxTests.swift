import Testing
import Foundation
@testable import stepkeeper

struct ShareInboxTests {
    @Test func pushPopRoundTripAndDrain() {
        ShareInbox.defaults?.removeObject(forKey: ShareInbox.urlKey)
        #expect(ShareInbox.pop() == nil)
        ShareInbox.push("https://youtu.be/4ioPBiTWm3M")
        #expect(ShareInbox.pop() == "https://youtu.be/4ioPBiTWm3M")
        #expect(ShareInbox.pop() == nil)   // 소비 후 비어야 함
    }
}

import Testing
import Foundation
@testable import stepkeeper

@MainActor
struct NotionExportTrackerTests {
    @Test func preventsDuplicateInFlight() {
        let id = "doc-\(UUID().uuidString)"
        #expect(NotionExportTracker.begin(id))
        #expect(!NotionExportTracker.begin(id))   // 진행 중 재시작 차단
        NotionExportTracker.end(id)
        #expect(NotionExportTracker.begin(id))    // 종료 후 재시작 허용
        NotionExportTracker.end(id)
    }
}

import Testing
@testable import stepkipper

struct YouTubeURLTests {
    @Test func parsesCommonForms() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=4ioPBiTWm3M") == "4ioPBiTWm3M")
        #expect(YouTubeURL.videoID(from: "https://m.youtube.com/watch?v=4ioPBiTWm3M&t=10") == "4ioPBiTWm3M")
        #expect(YouTubeURL.videoID(from: "https://youtu.be/4ioPBiTWm3M?si=abc") == "4ioPBiTWm3M")
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/shorts/4ioPBiTWm3M") == "4ioPBiTWm3M")
    }
    @Test func rejectsInvalid() {
        #expect(YouTubeURL.videoID(from: "https://example.com/watch?v=abc") == nil)
        #expect(YouTubeURL.videoID(from: "그냥 텍스트") == nil)
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=short") == nil)
    }
    @Test func rejectsOverlongIDAndForeignDomain() {
        // 강화① 뒤경계: id가 11자를 초과해 이어지면 거부
        #expect(YouTubeURL.videoID(from: "https://youtu.be/4ioPBiTWm3MX") == nil)
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=4ioPBiTWm3MXtra") == nil)
        // 강화② 도메인 확인: 정규식은 매치되지만 유튜브 도메인이 아니면 거부
        #expect(YouTubeURL.videoID(from: "https://example.com/watch?v=4ioPBiTWm3M") == nil)
    }
}

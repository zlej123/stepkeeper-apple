import Testing
@testable import clipnote

struct NotionPageIDTests {
    @Test func normalizesURLDashedAndRawInputs() {
        // 노션 페이지 URL (제목 슬러그 + 32자 hex)
        #expect(NotionPageID.normalize(
            "https://www.notion.so/myspace/Recipe-Notes-0123456789abcdef0123456789abcdef")
            == "0123456789abcdef0123456789abcdef")
        // 하이픈 UUID 형식
        #expect(NotionPageID.normalize("01234567-89ab-cdef-0123-456789abcdef")
            == "0123456789abcdef0123456789abcdef")
        // 순수 32자 hex (대문자 → 소문자)
        #expect(NotionPageID.normalize("0123456789ABCDEF0123456789ABCDEF")
            == "0123456789abcdef0123456789abcdef")
        // 공백 포함 입력
        #expect(NotionPageID.normalize("  0123456789abcdef0123456789abcdef\n")
            == "0123456789abcdef0123456789abcdef")
    }
    @Test func rejectsInvalidInputs() {
        #expect(NotionPageID.normalize("") == nil)
        #expect(NotionPageID.normalize("그냥 텍스트") == nil)
        #expect(NotionPageID.normalize("12345") == nil)                    // 너무 짧음
        #expect(NotionPageID.normalize("0123456789abcdef0123456789abcdeg") == nil)  // g는 hex 아님
        // 33자 이상 hex 덩어리는 어느 32자를 뜻하는지 알 수 없으므로 통째로 거부한다
        // (앞 경계가 없으면 한 글자 밀린 32자를 잘라내 조용히 틀린 ID를 만들었다)
        #expect(NotionPageID.normalize("00123456789abcdef0123456789abcdef") == nil)
        #expect(NotionPageID.normalize("0123456789abcdef0123456789abcdef0") == nil)
    }
    @Test func urlWithQueryPicksPageIDNotViewID() {
        // URL 끝 쿼리(v=뷰ID)가 아니라 경로의 페이지 ID를 잡아야 한다 — 경로가 앞이므로 첫 매치 사용 검증
        #expect(NotionPageID.normalize(
            "https://www.notion.so/myspace/Notes-0123456789abcdef0123456789abcdef?pvs=4")
            == "0123456789abcdef0123456789abcdef")
    }
}

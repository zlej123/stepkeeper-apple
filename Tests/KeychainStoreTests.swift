import Testing
import Foundation
@testable import stepkeeper

struct KeychainStoreTests {
    /// macOS 제외 이유: ad-hoc 서명 테스트 호스트가 로그인 키체인에 **매 실행 새 서비스명**으로
    /// 항목을 만들기 때문에 항목마다 접근 승인 창이 뜬다("항상 허용"은 그 항목에만 적용되므로
    /// 다음 실행에서 또 뜬다). 헤드리스에서는 응답할 수 없어 러너가 멈춘다.
    /// iOS 시뮬레이터는 프롬프트 없이 실제 키체인 왕복을 검증하므로 커버리지는 유지된다.
    @Test(.enabled(if: !ProcessInfo.processInfo.isMacOS))
    func roundTripSaveLoadOverwriteDelete() throws {
        let store = KeychainStore(service: "stepkeeper.tests.\(UUID().uuidString)")
        defer { try? store.delete() }

        #expect(try store.load() == nil)
        try store.save("key-1")
        #expect(try store.load() == "key-1")
        try store.save("key-2")                 // 덮어쓰기
        #expect(try store.load() == "key-2")
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()                      // 없는 항목 삭제도 에러 아님
    }
}

extension ProcessInfo {
    /// 컴파일 타임 #if 대신 런타임 판정 — @Test 트레이트 조건에 쓰려면 표현식이어야 한다.
    var isMacOS: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

struct KeychainMigrationGuardTests {
    /// 테스트 실행 중에는 절대 실제 키체인을 건드리지 않는다 — macOS 테스트 러너가
    /// 구 항목 접근 승인창에서 멈추던 원인이었다.
    @Test func skipsMigrationUnderTests() {
        #expect(KeychainStore.isRunningTests)
        let defaults = UserDefaults(suiteName: "stepkeeper.tests.\(UUID().uuidString)")!
        KeychainStore.migrateLegacyItems(defaults: defaults)
        // 테스트 감지로 조기 반환하므로 "이미 이전함" 플래그조차 남지 않는다
        #expect(defaults.bool(forKey: "stepkeeper.keychain-migrated") == false)
    }
}

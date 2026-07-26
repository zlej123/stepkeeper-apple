import Foundation
import Security

/// Gemini 키 등 비밀 값 저장 (kSecClassGenericPassword).
/// 키 값은 로그·에러 메시지에 절대 포함하지 않는다.
struct KeychainStore: Sendable {
    var service: String
    var account: String = "default"

    static let geminiKey = KeychainStore(service: "stepkeeper.gemini-key")
    static let notionToken = KeychainStore(service: "stepkeeper.notion-token")

    /// clipnote → stepkeeper 개명 전에 저장된 항목. 앱 시작 시 1회 이전한다.
    /// (제거 시점: 사용자 기반이 새 이름으로 넘어간 뒤 — 그전까지 지우면 기존 사용자가 키를 다시 넣어야 한다)
    static let legacyPairs = [
        (legacy: KeychainStore(service: "clipnote.gemini-key"), current: geminiKey),
        (legacy: KeychainStore(service: "clipnote.notion-token"), current: notionToken),
    ]

    private static let migrationDoneKey = "stepkeeper.keychain-migrated"

    /// 구 서비스명에 값이 있고 새 이름이 비어 있으면 옮긴다. 실패해도 앱 동작을 막지 않는다
    /// (사용자는 설정에서 다시 입력할 수 있고, 구 항목은 지우지 않으므로 데이터 손실도 없다).
    ///
    /// **딱 한 번만** 시도한다. macOS에서 다른 앱(구 번들 ID)이 만든 항목을 읽으면 키체인 접근
    /// 승인창이 뜨는데, 매 실행 시도하면 거부한 사용자에게 창이 계속 뜬다.
    /// 테스트 실행 중에는 아예 건너뛴다 — 테스트 호스트도 앱을 띄우므로 헤드리스 러너가 승인창에서 멈춘다.
    static func migrateLegacyItems(defaults: UserDefaults = .standard) {
        guard !isRunningTests, !defaults.bool(forKey: migrationDoneKey) else { return }
        defaults.set(true, forKey: migrationDoneKey)
        migrateLegacyItemsNow()
    }

    /// XCTest·Swift Testing 양쪽에서 참 — 테스트 번들이 주입되면 이 환경변수/심볼이 생긴다.
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// 이전 로직 본체 (1회 가드 없이 — 테스트에서 직접 호출)
    static func migrateLegacyItemsNow() {
        for pair in legacyPairs {
            guard let value = try? pair.legacy.load(), !value.isEmpty,
                  (try? pair.current.load()) ?? nil == nil else { continue }
            guard (try? pair.current.save(value)) != nil else { continue }
            try? pair.legacy.delete()
        }
    }

    struct UnexpectedStatus: Error, Equatable { let status: OSStatus }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            // 두 호출자가 동시에 notFound를 보고 둘 다 add하면 패자가 duplicate를 받는다 —
            // 항목은 이미 존재하므로 update로 마무리한다 (upsert 의미 유지).
            if addStatus == errSecDuplicateItem {
                let retry = SecItemUpdate(
                    baseQuery as CFDictionary,
                    [kSecValueData as String: data] as CFDictionary)
                guard retry == errSecSuccess else { throw UnexpectedStatus(status: retry) }
            } else if addStatus != errSecSuccess {
                throw UnexpectedStatus(status: addStatus)
            }
        } else if status != errSecSuccess {
            throw UnexpectedStatus(status: status)
        }
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw UnexpectedStatus(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UnexpectedStatus(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

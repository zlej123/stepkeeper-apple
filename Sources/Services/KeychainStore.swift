import Foundation
import Security

/// 비밀 값 저장소. 테스트는 인메모리 구현을 주입해 **실제 키체인을 건드리지 않는다** —
/// ad-hoc 서명 macOS 테스트 호스트가 키체인 항목에 접근하면 승인 창이 떠서 러너가 멈춘다.
protocol SecretStoring: Sendable {
    func save(_ value: String) throws
    func load() throws -> String?
    func delete() throws
}

/// Gemini 키 등 비밀 값 저장 (kSecClassGenericPassword).
/// 키 값은 로그·에러 메시지에 절대 포함하지 않는다.
struct KeychainStore: SecretStoring {
    var service: String
    var account: String = "default"

    static let geminiKey = KeychainStore(service: "stepkipper.gemini-key")
    static let notionToken = KeychainStore(service: "stepkipper.notion-token")

    /// XCTest·Swift Testing 양쪽에서 참 — 테스트 번들이 주입되면 이 환경변수/심볼이 생긴다.
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    struct UnexpectedStatus: Error, Equatable { let status: OSStatus }

    /// 운영 항목(앱이 실제로 쓰는 서비스명)인가. 테스트 중에는 이 항목들에 접근하지 않는다:
    /// 테스트 호스트가 앱 UI를 띄우면 HomeView·SettingsView가 키 유무를 확인하는데,
    /// ad-hoc 서명은 빌드마다 달라서 **이전 빌드가 만든 항목**을 읽는 순간 승인 창이 뜨고
    /// 헤드리스 러너가 거기서 멈춘다. 테스트가 만든 항목(랜덤 서비스명)은 그대로 동작한다.
    private var isProductionItem: Bool {
        service == Self.geminiKey.service || service == Self.notionToken.service
    }
    private var blockedInTests: Bool { Self.isRunningTests && isProductionItem }

    func save(_ value: String) throws {
        if blockedInTests { return }
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
        if blockedInTests { return nil }
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
        if blockedInTests { return }
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

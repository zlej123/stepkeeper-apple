import Foundation
@testable import stepkeeper

/// 테스트 전용 비밀 저장소 — 실제 키체인을 쓰지 않는다.
/// (macOS 테스트 호스트가 키체인에 접근하면 승인 창이 떠 헤드리스 러너가 멈춘다)
final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(_ initial: String? = nil) { value = initial }

    func save(_ newValue: String) throws { lock.withLock { value = newValue } }
    func load() throws -> String? { lock.withLock { value } }
    func delete() throws { lock.withLock { value = nil } }
}

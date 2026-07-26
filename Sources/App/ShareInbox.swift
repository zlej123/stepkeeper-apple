import Foundation

/// 공유 확장 → 본체 앱 URL 전달 (스펙 4.7). 확장은 push만, 앱은 활성화 시 pop.
enum ShareInbox {
    static let groupID = "group.com.stepkeeper.shared"
    static let urlKey = "pendingURL"

    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    static func push(_ url: String) {
        defaults?.set(url, forKey: urlKey)
    }

    static func pop() -> String? {
        guard let defaults, let url = defaults.string(forKey: urlKey) else { return nil }
        defaults.removeObject(forKey: urlKey)
        return url
    }
}

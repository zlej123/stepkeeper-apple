import Foundation

/// 공유 확장 → 본체 앱 URL 전달 (스펙 4.7). 확장은 push만, 앱은 활성화 시 pop.
///
/// FIFO 큐 (외부 리뷰 3차 P2): 예전에는 URL 하나만 저장해서, 앱을 열기 전에 두 영상을
/// 공유하면 첫 요청이 조용히 덮어써졌다. 이제 배열로 쌓고 앞에서부터 꺼낸다 —
/// 하나를 분석하는 동안 나머지는 남아 있고, 홈 화면이 대기 개수를 보여준다.
enum ShareInbox {
    static let groupID = "group.com.stepkeeper.shared"
    static let urlKey = "pendingURLs"          // [String] (FIFO)
    static let legacyURLKey = "pendingURL"     // 구 버전 단일 값 — pop 시 흡수

    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    /// 큐 상한 — 공유를 수십 번 눌러도 무한히 쌓이지 않게. 초과분은 가장 오래된 것부터 버린다.
    static let capacity = 10

    static func push(_ url: String) {
        guard let defaults else { return }
        var queue = defaults.stringArray(forKey: urlKey) ?? []
        guard !queue.contains(url) else { return }   // 같은 영상 연타는 한 번만
        queue.append(url)
        if queue.count > capacity { queue.removeFirst(queue.count - capacity) }
        defaults.set(queue, forKey: urlKey)
    }

    static func pop() -> String? {
        guard let defaults else { return nil }
        var queue = defaults.stringArray(forKey: urlKey) ?? []
        // 개명/구버전 확장이 남긴 단일 값 흡수 (한 번 실행되면 사라진다)
        if let legacy = defaults.string(forKey: legacyURLKey) {
            defaults.removeObject(forKey: legacyURLKey)
            if !queue.contains(legacy) { queue.insert(legacy, at: 0) }
        }
        guard !queue.isEmpty else { return nil }
        let url = queue.removeFirst()
        defaults.set(queue, forKey: urlKey)
        return url
    }

    /// 대기 중 개수 (홈 화면 표시용)
    static var pendingCount: Int {
        defaults?.stringArray(forKey: urlKey)?.count ?? 0
    }
}

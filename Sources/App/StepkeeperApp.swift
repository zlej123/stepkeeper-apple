import SwiftUI

@main
struct StepkeeperApp: App {
    init() {
        Settings.registerDefaults()
        // clipnote 시절에 저장된 키를 새 서비스명으로 이전 (1회성, 실패해도 앱은 계속 뜬다)
        KeychainStore.migrateLegacyItems()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["STEPKEEPER_SPIKE"] == "1" {
                SpikeCaptureView()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}

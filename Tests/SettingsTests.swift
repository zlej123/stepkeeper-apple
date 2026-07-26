import Testing
import Foundation
@testable import stepkeeper

struct SettingsTests {
    @Test func registersDefaults() {
        let suite = UserDefaults(suiteName: "stepkeeper.tests.settings")!
        suite.removePersistentDomain(forName: "stepkeeper.tests.settings")
        Settings.registerDefaults(suite)
        #expect(suite.string(forKey: Settings.serverURLKey) == "")   // v1.3: 직접 모드 기본
        #expect(suite.string(forKey: Settings.languageKey) == "ko")
        #expect(suite.bool(forKey: Settings.linkModeKey) == false)
    }
}

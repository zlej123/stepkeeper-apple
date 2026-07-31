import Testing
import Foundation
@testable import stepkipper

struct SettingsTests {
    @Test func registersDefaults() {
        let suite = UserDefaults(suiteName: "stepkipper.tests.settings")!
        suite.removePersistentDomain(forName: "stepkipper.tests.settings")
        Settings.registerDefaults(suite)
        #expect(suite.string(forKey: Settings.serverURLKey) == "")   // v1.3: 직접 모드 기본
        #expect(suite.string(forKey: Settings.languageKey) == "ko")
        #expect(suite.bool(forKey: Settings.linkModeKey) == false)
    }
}

import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            HomeView(model: model)
        }
        .task {
            #if DEBUG
            if let url = ProcessInfo.processInfo.environment["STEPKEEPER_E2E_URL"] {
                if let server = ProcessInfo.processInfo.environment["STEPKEEPER_SERVER_URL"] {
                    UserDefaults.standard.set(server, forKey: Settings.serverURLKey)
                }
                try? KeychainStore.geminiKey.save("e2e-stub-key")
                if ProcessInfo.processInfo.environment["STEPKEEPER_LINK_MODE"] == "1" {
                    UserDefaults.standard.set(true, forKey: Settings.linkModeKey)
                }
                model.autoContinue = true
                await model.start(urlString: url)
            }
            #endif
            // 콜드 스타트 픽업: onChange(initial: false)는 첫 렌더 시점의 .active를 놓친다 (리뷰 반영)
            pickupSharedURL()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pickupSharedURL() }
        }
    }

    private func pickupSharedURL() {
        guard let url = ShareInbox.pop() else { return }
        model.autoContinue = false
        Task { await model.start(urlString: url) }
    }
}

#Preview {
    ContentView()
}

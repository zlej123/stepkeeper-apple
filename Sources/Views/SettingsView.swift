import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.serverURLKey) private var serverURL = Settings.defaultServerURL
    @AppStorage(Settings.languageKey) private var language = Settings.defaultLanguage
    @AppStorage(Settings.linkModeKey) private var linkMode = false
    @AppStorage(Settings.reportServerURLKey) private var reportServerURL = ""
    @State private var geminiKey = ""
    @State private var keySavedAt: Date?
    @State private var keySaveError: String?
    @AppStorage(Settings.notionParentPageKey) private var notionParentPage = ""
    @State private var notionToken = ""
    @State private var notionSavedAt: Date?
    @State private var notionSaveError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Key from AI Studio", text: $geminiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Save key") {
                        do {
                            try KeychainStore.geminiKey.save(
                                geminiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                            keySaveError = nil
                            keySavedAt = Date()
                        } catch {
                            keySavedAt = nil
                            keySaveError = String(localized: "Couldn't save — try again")
                        }
                    }
                    .disabled(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if keySavedAt != nil {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    }
                    if let keySaveError {
                        Label(keySaveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                    }
                    if geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 8) {
                            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                                Label("Get a free key at AI Studio", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.borderedProminent)
                            Text("← one minute, no card")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        DisclosureGroup("How to get a key") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("1. Go to aistudio.google.com/apikey with your Google account")
                                Text("2. Click \"Create API key\"")
                                Text("3. Copy the key (it starts with AIza)")
                                Text("4. Paste it above and tap Save key — free, no card needed")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        }
                        .font(.callout)
                    } else {
                        Link("Get a free key at AI Studio (no card)",
                             destination: URL(string: "https://aistudio.google.com/apikey")!)
                            .font(.callout)
                    }
                } header: { Text("Gemini API key") } footer: {
                    Text("The key stays in this device's Keychain and is only used for analysis requests.")
                }
                Section("Analysis") {
                    Picker("Document language", selection: $language) {
                        Text("한국어").tag("ko")
                        Text("English").tag("en")
                        Text("日本語").tag("ja")
                    }
                    Toggle("Link mode", isOn: $linkMode)
                    Text("Link mode: no frame capture — every guide becomes a YouTube timestamp link.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    TextField("Server URL", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } header: { Text("stepkeeper server (optional)") } footer: {
                    Text("Leave empty to call Gemini directly, with no server (the default). To use a dev server, enter its URL — on a real device that's your Mac's LAN IP (e.g. http://192.168.0.10:8787).")
                }
                Section {
                    TextField("Report collector URL", text: $reportServerURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } header: { Text("Issue reports (optional)") } footer: {
                    Text("Leave empty to send to the analysis server. Release builds ship with a default collector.")
                }
                Section {
                    SecureField("Notion integration token", text: $notionToken)
                        .textFieldStyle(.roundedBorder)
                    Button("Save token") {
                        do {
                            try KeychainStore.notionToken.save(
                                notionToken.trimmingCharacters(in: .whitespacesAndNewlines))
                            notionSaveError = nil
                            notionSavedAt = Date()
                        } catch {
                            notionSavedAt = nil
                            notionSaveError = String(localized: "Couldn't save — try again")
                        }
                    }
                    .disabled(notionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if notionSavedAt != nil {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    }
                    if let notionSaveError {
                        Label(notionSaveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                    }
                    TextField("Parent page (paste a URL or ID)", text: $notionParentPage)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Link("Create an integration",
                         destination: URL(string: "https://www.notion.so/my-integrations")!)
                        .font(.callout)
                } header: { Text("Notion export") } footer: {
                    Text("Create an integration, then add it to the target page under ··· → Connections. Uploads fail until you do.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                geminiKey = (try? KeychainStore.geminiKey.load()) ?? ""
                notionToken = (try? KeychainStore.notionToken.load()) ?? ""
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}

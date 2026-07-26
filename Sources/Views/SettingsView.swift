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
                    SecureField("AI Studio에서 발급한 키", text: $geminiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("키 저장") {
                        do {
                            try KeychainStore.geminiKey.save(
                                geminiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                            keySaveError = nil
                            keySavedAt = Date()
                        } catch {
                            keySavedAt = nil
                            keySaveError = "저장 실패 — 다시 시도해 주세요"
                        }
                    }
                    .disabled(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if keySavedAt != nil {
                        Label("저장됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    }
                    if let keySaveError {
                        Label(keySaveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                    }
                    if geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 8) {
                            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                                Label("AI Studio에서 무료 키 발급", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.borderedProminent)
                            Text("← 여기를 눌러 1분 발급")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        DisclosureGroup("키 발급 방법 보기") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("1. 구글 계정으로 aistudio.google.com/apikey 접속")
                                Text("2. \"API 키 만들기(Create API key)\" 클릭")
                                Text("3. 생성된 키 복사 (AIza로 시작)")
                                Text("4. 위 칸에 붙여넣고 '키 저장' — 무료, 카드 등록 불필요")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        }
                        .font(.callout)
                    } else {
                        Link("AI Studio에서 무료 키 발급 (카드 불필요)",
                             destination: URL(string: "https://aistudio.google.com/apikey")!)
                            .font(.callout)
                    }
                } header: { Text("Gemini API 키") } footer: {
                    Text("키는 이 기기의 Keychain에만 저장되고 분석 요청에만 사용됩니다.")
                }
                Section("분석") {
                    Picker("문서 언어", selection: $language) {
                        Text("한국어").tag("ko")
                        Text("English").tag("en")
                        Text("日本語").tag("ja")
                    }
                    Toggle("링크 모드", isOn: $linkMode)
                    Text("링크 모드: 화면 캡처 없이 모든 가이드를 유튜브 타임스탬프 링크로 넣습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    TextField("서버 URL", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } header: { Text("stepkeeper 서버 (선택)") } footer: {
                    Text("비워두면 서버 없이 Gemini를 직접 호출합니다(기본). 개발용 서버를 쓰려면 URL 입력 — 실기기에서는 Mac의 LAN IP (예: http://192.168.0.10:8787)")
                }
                Section {
                    TextField("신고 수집 서버 URL", text: $reportServerURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } header: { Text("이상 신고 (선택)") } footer: {
                    Text("비워두면 분석 서버로 보냅니다. 일반 배포판에는 기본 수집기가 내장됩니다.")
                }
                Section {
                    SecureField("Notion 통합 토큰", text: $notionToken)
                        .textFieldStyle(.roundedBorder)
                    Button("토큰 저장") {
                        do {
                            try KeychainStore.notionToken.save(
                                notionToken.trimmingCharacters(in: .whitespacesAndNewlines))
                            notionSaveError = nil
                            notionSavedAt = Date()
                        } catch {
                            notionSavedAt = nil
                            notionSaveError = "저장 실패 — 다시 시도해 주세요"
                        }
                    }
                    .disabled(notionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if notionSavedAt != nil {
                        Label("저장됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    }
                    if let notionSaveError {
                        Label(notionSaveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                    }
                    TextField("부모 페이지 (URL 또는 ID 붙여넣기)", text: $notionParentPage)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Link("통합(integration) 만들기",
                         destination: URL(string: "https://www.notion.so/my-integrations")!)
                        .font(.callout)
                } header: { Text("Notion 내보내기") } footer: {
                    Text("통합을 만들고, 대상 페이지의 ··· 메뉴 → 연결에서 그 통합을 추가해야 업로드할 수 있습니다.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("설정")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
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

import SwiftUI

/// 원탭 이상 신고 시트 — submit 클로저가 실제 전송을 수행하고, 실패 메시지(성공 시 nil)를 반환한다.
struct ReportSheet: View {
    let submit: (ReportReason, String) async -> String?
    @State private var reason: ReportReason = .candidates
    @State private var note = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var done = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $reason) {
                    ForEach(ReportReason.allCases) { reason in
                        Text(reason.label).tag(reason)
                    }
                }
                Section("Note (optional)") {
                    TextEditor(text: $note).frame(minHeight: 80)
                }
                Section {
                    if done {
                        Label("Sent — thanks, this helps.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            sending = true
                            errorMessage = nil
                            Task {
                                errorMessage = await submit(reason, note)
                                sending = false
                                if errorMessage == nil {
                                    done = true
                                    try? await Task.sleep(for: .seconds(1))
                                    dismiss()
                                }
                            }
                        } label: {
                            if sending { ProgressView() } else { Text("Send") }
                        }
                        .disabled(sending)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                    }
                } footer: {
                    // 수집기 설정 여부에 따라 실제 동작이 달라지므로 고지 문구도 그에 맞춘다
                    Text(ReportCollector.resolveURL() == nil
                         ? "Your mail app opens with the video URL, reason, and note filled in. You can review it before sending."
                         : "The video URL, the analysis, and your picks are sent to the developer's server.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Report an issue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}

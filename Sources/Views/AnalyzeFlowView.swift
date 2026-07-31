import SwiftUI

struct AnalyzeFlowView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false

    /// 캡처가 끝난 단계(선택·조립·완료)에선 플레이어를 숨겨 화면 전체를 내준다 (UX 피드백 반영).
    /// bridge가 WKWebView를 소유하므로 뷰 트리에서 빠져도 상태는 유지된다.
    private var showsPlayer: Bool {
        switch model.stage {
        case .picking, .building, .done, .failed: false
        default: true
        }
    }

    private var isPicking: Bool {
        if case .picking = model.stage { true } else { false }
    }

    private var dismissalLabel: LocalizedStringKey {
        switch model.stage {
        case .done, .failed: "Close"
        default: "Cancel"
        }
    }

    var body: some View {
        Group {
            if isPicking {
                CandidatePickerView(model: model)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        if showsPlayer {
                            PlayerWebView(bridge: model.bridge)
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        stageView
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
            }
        }
        .padding(.horizontal)
        .navigationTitle("Analysis")
        // 시스템 back은 model.reset()을 건너뛰어 분석이 화면 밖에서 계속될 수 있다.
        // 단일 Cancel/Close 경로로 상태와 화면 수명을 함께 끝낸다.
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(dismissalLabel) { model.reset(); dismiss() }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    @ViewBuilder private var stageView: some View {
        switch model.stage {
        case .idle:
            Text("Waiting").foregroundStyle(.secondary)
        case .loadingPlayer:
            ProgressView("Loading the player…")
        case .readyToAnalyze(let duration, let title):
            VStack(spacing: 10) {
                Text(title).font(.callout).lineLimit(2)
                Text("Length \(MarkdownBuilder.hms(duration))").font(.caption).foregroundStyle(.secondary)
                Picker("Profile", selection: Binding(
                    get: { model.profileOverride ?? model.detectedProfile },
                    set: { model.profileOverride = $0 })) {
                    Text("General").tag("generic")
                    Text("Cooking").tag("recipe")
                }
                .pickerStyle(.segmented)
                if !HighRiskDetector.hits(in: title).isEmpty {
                    // 분석 시작 전 경고 (리뷰 3차: "분석 시작 전과 저장 문서 상단에")
                    Label(String(localized: "This looks like a safety-critical topic — the document will carry a warning."),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button("Start analysis") { Task { await model.confirmAnalyze() } }
                    .buttonStyle(.borderedProminent)
            }
        case .analyzing(let duration):
            ProgressView("Analyzing the video… (\(MarkdownBuilder.hms(duration)), \(model.profile))")
        case .capturing(let current, let total):
            ProgressView("Capturing frames… \(current)/\(total)")
        case .autoPicking:
            ProgressView("AI is picking the frames…")
        case .picking:
            CandidatePickerView(model: model)
        case .building:
            ProgressView("Building the document…")
        case .done(let meta):
            VStack(spacing: 10) {
                Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(meta.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Saved to Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // value 기반 링크는 이 뷰가 isPresented로 푸시된 브랜치라 루트 List의
                // String 목적지 등록을 못 봐서 활성화되지 않는다 → 목적지 직접 지정으로 우회
                if let document = model.document(id: meta.id) {
                    NavigationLink("Open document") { DocumentView(document: document) }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .failed(let failure):
            VStack(spacing: 10) {
                Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
                    .multilineTextAlignment(.center)
                switch failure.recovery {
                case .closeOnly:
                    Button("Edit URL") {
                        model.reset()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                case .settingsAndRetry:
                    Button("Open Settings") { showSettings = true }
                        .buttonStyle(.borderedProminent)
                    Button("Try again") { Task { await model.retry() } }
                        .buttonStyle(.bordered)
                case .retryAnalysis, .retryBuild:
                    Button("Try again") { Task { await model.retry() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

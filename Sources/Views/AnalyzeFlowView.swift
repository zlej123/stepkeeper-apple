import SwiftUI

struct AnalyzeFlowView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// 캡처가 끝난 단계(선택·조립·완료)에선 플레이어를 숨겨 화면 전체를 내준다 (UX 피드백 반영).
    /// bridge가 WKWebView를 소유하므로 뷰 트리에서 빠져도 상태는 유지된다.
    private var showsPlayer: Bool {
        switch model.stage {
        case .picking, .building, .done: false
        default: true
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if showsPlayer {
                PlayerWebView(bridge: model.bridge)
                    .frame(minHeight: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            stageView
            Spacer()
        }
        .padding()
        .navigationTitle("Analysis")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { model.reset(); dismiss() }
            }
        }
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
                Button("Start analysis") { Task { await model.confirmAnalyze() } }
                    .buttonStyle(.borderedProminent)
            }
        case .analyzing(let duration):
            ProgressView("Analyzing the video… (\(MarkdownBuilder.hms(duration)), \(model.profile))")
        case .capturing(let current, let total):
            ProgressView("Capturing frames… \(current)/\(total)")
        case .picking:
            CandidatePickerView(model: model)
        case .building:
            ProgressView("Building the document…")
        case .done(let meta):
            VStack(spacing: 10) {
                Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                // value 기반 링크는 이 뷰가 isPresented로 푸시된 브랜치라 루트 List의
                // String 목적지 등록을 못 봐서 활성화되지 않는다 → 목적지 직접 지정으로 우회
                if let document = model.document(id: meta.id) {
                    NavigationLink("Open document") { DocumentView(document: document) }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await model.retry() } }
            }
        }
    }
}

import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel
    @State private var urlText = ""
    @State private var documents: [DocumentMeta] = []
    @State private var hasKey = false
    @State private var showSettings = false
    @State private var flowActive = false

    var body: some View {
        List {
            if !hasKey {
                Section {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Add your Gemini API key in Settings first", systemImage: "key.fill")
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    .foregroundStyle(.orange)
                    .listRowBackground(KeyNudgeBackground())
                }
            }
            Section("New document") {
                TextField("YouTube URL", text: $urlText)
                    .autocorrectionDisabled()
                HStack {
                    Button("Paste") { if let s = Pasteboard.string { urlText = s } }
                    Spacer()
                    Button("Make document") {
                        flowActive = true
                        Task { await model.start(urlString: urlText) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(YouTubeURL.videoID(from: urlText) == nil)
                }
            }
            Section("Recent") {
                if documents.isEmpty {
                    Text("No documents yet").foregroundStyle(.secondary)
                }
                ForEach(documents) { meta in
                    NavigationLink(value: meta.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meta.title).lineLimit(1)
                            Text(meta.createdAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet { model.deleteDocument(id: documents[index].id) }
                    documents = model.documents()
                }
            }
        }
        .navigationTitle("stepkeeper")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: refresh) { SettingsView() }
        .navigationDestination(isPresented: $flowActive) { AnalyzeFlowView(model: model) }
        .navigationDestination(for: String.self) { id in
            if let doc = model.document(id: id) {
                DocumentView(document: doc)
            } else {
                Text("Couldn't open that document")
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: model.stage) { _, newStage in
            if case .loadingPlayer = newStage { flowActive = true }   // E2E·공유 진입 자동 표시
            if case .failed = newStage { flowActive = true }   // 진입 전 실패(키 미설정 공유 등)도 에러+재시도 화면으로 (최종 리뷰 Important 3)
            if case .done = newStage { documents = model.documents() }
        }
    }

    private func refresh() {
        documents = model.documents()
        hasKey = ((try? KeychainStore.geminiKey.load()) ?? "").isEmpty == false
    }
}

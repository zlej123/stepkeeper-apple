import SwiftUI

struct DocumentView: View {
    let document: SavedDocument
    @State private var pickingFolder = false
    @State private var exportMessage: String?
    @State private var exportingNotion = false
    @State private var notionPageURL: URL?   // onAppear에서 meta의 저장값으로 초기화
    @State private var reporting = false

    private var analysis: Analysis { document.analysis }
    private var isRecipe: Bool { document.meta.profile == "recipe" }
    /// 본문 라벨은 문서를 만든 언어를 따른다 (툴바·안내 문구는 시스템 언어)
    private var docStrings: DocumentStrings { .forLanguage(document.meta.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 안전 고지 — 코어와 같은 자산으로 로컬 감지 (분석 경로와 무관하게 뜬다)
                if !HighRiskDetector.hits(in: analysis.title, analysis.category,
                                          analysis.summary).isEmpty {
                    Label(String(localized: "This looks like a safety-critical topic (medical, electrical, gas…). Treat this document as reference only — don't follow it without expert guidance."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text("\(isRecipe ? "🍳" : "📋") \(analysis.title)").font(.title2.bold())
                Text(analysis.summary).foregroundStyle(.secondary)
                if !isRecipe, let category = analysis.category, !category.isEmpty {
                    Text("**\(docStrings.category):** \(category)")
                }
                Text("■ " + docStrings.needsTitle(isRecipe: isRecipe,
                                                  servings: analysis.servings)).font(.headline)
                ForEach(analysis.materials, id: \.name) { material in
                    Text("• \(material.name) \(material.amount)")
                }
                Text("■ " + docStrings.stepsTitle(isRecipe: isRecipe)).font(.headline)
                ForEach(analysis.steps, id: \.id) { step in
                    stepSection(step)
                }
                Divider()
                Link(docStrings.source(analysis.title),
                     destination: URL(string: "https://youtu.be/\(document.meta.videoId)")!)
                    .font(.footnote)
                if exportingNotion {
                    ProgressView("Uploading to Notion…")
                }
                if let notionPageURL {
                    Link("Open in Notion", destination: notionPageURL)
                        .font(.callout)
                }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding()
        }
        .onAppear {
            if notionPageURL == nil, let saved = document.meta.notionPageURL {
                notionPageURL = URL(string: saved)
            }
        }
        .navigationTitle(analysis.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // 공유만 노출하고 나머지는 오버플로 메뉴로 — 아이폰 좁은 툴바에서 4버튼이 밀집했다
                ShareLink(items: shareItems) { Label("Share", systemImage: "square.and.arrow.up") }
                Menu {
                    Button { pickingFolder = true } label: {
                        Label("Save to a folder", systemImage: "folder")
                    }
                    Button {
                        exportToNotion()
                    } label: {
                        Label("Send to Notion", systemImage: "arrow.up.doc")
                    }
                    .disabled(exportingNotion)
                    Divider()
                    Button {
                        // 수집기가 없어도 시트를 연다 — 보내기 시 메일 앱으로 폴백
                        reporting = true
                    } label: {
                        Label("This document looks wrong", systemImage: "flag")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let directory) = result {
                let folder = document.folder
                let id = document.meta.id
                exportMessage = String(localized: "Saving to the folder…")
                Task {
                    exportMessage = await ExportHelper.copyFolder(
                        from: folder, to: directory, name: id)
                        ?? String(localized: "Saved to") + " \(directory.lastPathComponent)/\(id)"
                }
            }
        }
        .sheet(isPresented: $reporting) {
            ReportSheet { reason, note in
                await submitReport(reason: reason, note: note)
            }
        }
    }

    @ViewBuilder private func stepSection(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(step.id). \(step.summary)").font(.body.bold())
            Text(step.detail)
            ForEach(analysis.visualGuides.filter { $0.stepId == step.id }, id: \.id) { guide in
                guideRow(guide)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private func guideRow(_ guide: VisualGuide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("💡 *\(docStrings.guidePrefix(guide.phrase))* \(guide.guideText)")
                .font(.callout)
            let imageURL = document.folder.appendingPathComponent("\(guide.id).jpg")
            if let pick = document.picks[guide.id], pick != "none",
               FileManager.default.fileExists(atPath: imageURL.path) {
                LocalImage(url: imageURL).frame(maxHeight: 240)
            } else {
                // md(코어 패리티)와 정렬: timestamp가 없어도 영상 링크는 항상 제공한다 (리뷰 반영)
                let ts = guide.bestVisualTimestamp
                Link(docStrings.seeAt(ts.map { MarkdownBuilder.hms($0) }),
                     destination: URL(string: ts.map { "https://youtu.be/\(document.meta.videoId)?t=\($0)" }
                                      ?? "https://youtu.be/\(document.meta.videoId)")!)
                    .font(.callout)
            }
        }
        .padding(.leading, 12)
    }

    private var shareItems: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: document.folder, includingPropertiesForKeys: nil)) ?? []
        let md = files.filter { $0.pathExtension == "md" }
        let jpgs = files.filter { $0.pathExtension == "jpg" }.sorted { $0.path < $1.path }
        return md + jpgs
    }

    private func exportToNotion() {
        notionPageURL = nil
        guard let token = try? KeychainStore.notionToken.load(), !token.isEmpty,
              let parent = NotionPageID.normalize(
                UserDefaults.standard.string(forKey: Settings.notionParentPageKey) ?? "") else {
            exportMessage = String(localized: "Add your Notion token and parent page in Settings")
            return
        }
        guard NotionExportTracker.begin(document.meta.id) else {
            exportMessage = String(localized: "This document is already uploading to Notion")
            return
        }
        exportingNotion = true
        let exporter = NotionExporter(api: NotionAPI(token: token), parentPageID: parent)
        let target = document
        let store = try? DocumentStore(root: DocumentStore.defaultRoot())
        Task {
            defer { NotionExportTracker.end(target.meta.id) }
            do {
                // 이전 시도의 페이지가 있으면 교체 — 재시도가 중복 페이지를 만들지 않는다.
                // 생성 직후 meta에 기록해, 이후 단계가 실패해도 다음 재시도가 이어받는다.
                let url = try await exporter.export(
                    document: target, replacingPageID: target.meta.notionPageID,
                    onPageCreated: { pageID, pageURL in
                        var meta = target.meta
                        meta.notionPageID = pageID
                        meta.notionPageURL = pageURL
                        try? store?.updateMeta(meta)
                    })
                notionPageURL = url
                exportMessage = String(localized: "Uploaded to Notion")
            } catch {
                exportMessage = (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "Notion export failed")
            }
            exportingNotion = false
        }
    }

    private func submitReport(reason: ReportReason, note: String) async -> String? {
        guard let raw = try? Data(contentsOf:
            document.folder.appendingPathComponent("analysis.json")) else {
            return String(localized: "Couldn't read the original analysis")
        }
        let report = IssueReport(
            url: "https://m.youtube.com/watch?v=\(document.meta.videoId)",
            videoId: document.meta.videoId, reason: reason, note: note,
            profile: document.meta.profile, language: document.meta.language,
            rawAnalysis: raw, picks: document.picks, client: IssueReport.clientTag)
        // 수집기가 없으면 메일 앱으로 폴백
        guard let serverURL = ReportCollector.resolveURL() else {
            return ReportMailer.compose(report) ? nil
                : String(localized: "Couldn't open your mail app — the report was copied to the clipboard")
        }
        do {
            try await StepkeeperAPI(baseURL: serverURL).submitReport(report)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn't send the report")
        }
    }
}

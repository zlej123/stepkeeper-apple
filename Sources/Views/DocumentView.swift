import SwiftUI

struct DocumentView: View {
    let document: SavedDocument
    @State private var pickingFolder = false
    @State private var exportMessage: String?
    @State private var exportingNotion = false
    @State private var notionPageURL: URL?
    @State private var reporting = false

    private var analysis: Analysis { document.analysis }
    private var isRecipe: Bool { document.meta.profile == "recipe" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(isRecipe ? "🍳" : "📋") \(analysis.title)").font(.title2.bold())
                Text(analysis.summary).foregroundStyle(.secondary)
                if !isRecipe, let category = analysis.category, !category.isEmpty {
                    Text("**분류:** \(category)")
                }
                Text(isRecipe
                     ? "■ 준비 재료\(analysis.servings.map { " (\($0))" } ?? "")"
                     : "■ 준비물").font(.headline)
                ForEach(analysis.materials, id: \.name) { material in
                    Text("• \(material.name) \(material.amount)")
                }
                Text(isRecipe ? "■ 조리 순서" : "■ 순서").font(.headline)
                ForEach(analysis.steps, id: \.id) { step in
                    stepSection(step)
                }
                Divider()
                Link("출처: \(analysis.title) — stepkeeper로 생성",
                     destination: URL(string: "https://youtu.be/\(document.meta.videoId)")!)
                    .font(.footnote)
                if exportingNotion {
                    ProgressView("Notion 업로드 중…")
                }
                if let notionPageURL {
                    Link("Notion에서 열기", destination: notionPageURL)
                        .font(.callout)
                }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding()
        }
        .navigationTitle(analysis.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // 공유만 노출하고 나머지는 오버플로 메뉴로 — 아이폰 좁은 툴바에서 4버튼이 밀집했다
                ShareLink(items: shareItems) { Label("공유", systemImage: "square.and.arrow.up") }
                Menu {
                    Button { pickingFolder = true } label: {
                        Label("폴더로 저장", systemImage: "folder")
                    }
                    Button {
                        exportToNotion()
                    } label: {
                        Label("Notion으로 보내기", systemImage: "arrow.up.doc")
                    }
                    .disabled(exportingNotion)
                    Divider()
                    Button {
                        // 수집기가 없어도 시트를 연다 — 보내기 시 메일 앱으로 폴백
                        reporting = true
                    } label: {
                        Label("문서가 이상해요", systemImage: "flag")
                    }
                } label: {
                    Label("더 보기", systemImage: "ellipsis.circle")
                }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let directory) = result {
                let folder = document.folder
                let id = document.meta.id
                exportMessage = "폴더로 저장 중…"
                Task {
                    exportMessage = await ExportHelper.copyFolder(
                        from: folder, to: directory, name: id)
                        ?? "저장 완료: \(directory.lastPathComponent)/\(id)"
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
            Text("💡 *'\(guide.phrase)' 기준:* \(guide.guideText)")
                .font(.callout)
            let imageURL = document.folder.appendingPathComponent("\(guide.id).jpg")
            if let pick = document.picks[guide.id], pick != "none",
               FileManager.default.fileExists(atPath: imageURL.path) {
                LocalImage(url: imageURL).frame(maxHeight: 240)
            } else {
                // md(코어 패리티)와 정렬: timestamp가 없어도 영상 링크는 항상 제공한다 (리뷰 반영)
                let ts = guide.bestVisualTimestamp
                Link(ts.map { "▶ 영상 \(MarkdownBuilder.hms($0))에서 직접 확인" } ?? "▶ 영상에서 직접 확인",
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
            exportMessage = "설정에서 Notion 토큰과 부모 페이지를 입력하세요"
            return
        }
        guard NotionExportTracker.begin(document.meta.id) else {
            exportMessage = "이 문서는 Notion 업로드가 진행 중입니다"
            return
        }
        exportingNotion = true
        let exporter = NotionExporter(api: NotionAPI(token: token), parentPageID: parent)
        let target = document
        Task {
            defer { NotionExportTracker.end(target.meta.id) }
            do {
                let url = try await exporter.export(document: target)
                notionPageURL = url
                exportMessage = "Notion 업로드 완료"
            } catch {
                exportMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Notion 내보내기에 실패했습니다"
            }
            exportingNotion = false
        }
    }

    private func submitReport(reason: ReportReason, note: String) async -> String? {
        guard let raw = try? Data(contentsOf:
            document.folder.appendingPathComponent("analysis.json")) else {
            return "분석 원본을 읽지 못했습니다"
        }
        let report = IssueReport(
            url: "https://m.youtube.com/watch?v=\(document.meta.videoId)",
            videoId: document.meta.videoId, reason: reason, note: note,
            profile: document.meta.profile, language: document.meta.language,
            rawAnalysis: raw, picks: document.picks, client: IssueReport.clientTag)
        // 수집기가 없으면 메일 앱으로 폴백
        guard let serverURL = ReportCollector.resolveURL() else {
            return ReportMailer.compose(report) ? nil
                : "메일 앱을 열지 못했습니다 — 신고 내용을 클립보드에 복사했습니다"
        }
        do {
            try await StepkeeperAPI(baseURL: serverURL).submitReport(report)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "신고 전송에 실패했습니다"
        }
    }
}

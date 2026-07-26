import SwiftUI

/// 스펙 5.3: 가이드별 3후보 + "부적합(링크 사용)", center 기본 선택. 자동 선택 없음(사용자 확정 필수).
struct CandidatePickerView: View {
    @Bindable var model: AppModel
    @State private var picks: [String: String] = [:]
    @State private var reporting = false
    @State private var reportNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("가이드별로 의미가 가장 잘 보이는 장면을 고르세요")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(model.captures) { capture in
                    guideCard(capture)
                }
                Button("문서 만들기") {
                    Task { await model.finishPicking(picks: picks) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button {
                    // 수집기가 없어도 시트를 연다 — 보내기 시 메일 앱으로 폴백
                    reportNotice = nil
                    reporting = true
                } label: {
                    Label("후보가 이상해요", systemImage: "flag")
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                if let reportNotice {
                    Text(reportNotice).font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $reporting) {
            ReportSheet { reason, note in
                await model.submitIssueReport(reason: reason, note: note, picks: picks)
            }
        }
        .onAppear { if picks.isEmpty { picks = model.defaultPicks() } }
    }

    @ViewBuilder private func guideCard(_ capture: GuideCapture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(capture.guide.id) · \(capture.guide.phrase)").font(.headline)
            Text(capture.guide.guideText).font(.caption).foregroundStyle(.secondary)
            if capture.failed {
                Label("캡처 실패 — 링크로 대체됩니다", systemImage: "link")
                    .font(.callout).foregroundStyle(.orange)
            } else {
                // 적응형 그리드(아이폰 2열) — 가로 4분할 대비 썸네일 약 2배 (UX 피드백 반영)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(capture.candidates, id: \.slot) { candidate in
                        candidateCell(guideId: capture.guide.id, candidate: candidate)
                    }
                    noneCell(guideId: capture.guide.id)
                }
            }
        }
    }

    @ViewBuilder private func candidateCell(guideId: String, candidate: CaptureCandidate) -> some View {
        if candidate.jpeg == nil {
            // 슬롯 단위 실패는 자리표시로 남긴다 — 셀이 그냥 사라지면 후보가 몇 개였는지 알 수 없다
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("\(MarkdownBuilder.hms(candidate.time)) 캡처 실패")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        } else if let jpeg = candidate.jpeg {
            Button {
                picks[guideId] = candidate.slot
            } label: {
                VStack(spacing: 4) {
                    JPEGImage(data: jpeg)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                            picks[guideId] == candidate.slot ? Color.red : Color.secondary.opacity(0.3),
                            lineWidth: picks[guideId] == candidate.slot ? 3 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("\(MarkdownBuilder.hms(candidate.time)) (\(candidate.slot))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("이 장면 선택") { picks[guideId] = candidate.slot }
            } preview: {
                // 길게 누르면 원본 크기 확대 미리보기 (비-resizable Image = 고유 크기 기준)
                #if os(macOS)
                if let image = NSImage(data: jpeg) { Image(nsImage: image) }
                #else
                if let image = UIImage(data: jpeg) { Image(uiImage: image) }
                #endif
            }
        }
    }

    private func noneCell(guideId: String) -> some View {
        Button {
            picks[guideId] = "none"
        } label: {
            VStack {
                Text("부적합\n링크 사용").font(.caption).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                picks[guideId] == "none" ? Color.red : Color.secondary.opacity(0.3),
                lineWidth: picks[guideId] == "none" ? 3 : 1))
        }
        .buttonStyle(.plain)
    }
}

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
                Text("Pick the frame that shows what each phrase means")
                    .font(.callout).foregroundStyle(.secondary)
                if !model.autoPicks.isEmpty {
                    Label("AI pre-selected a frame for each guide — change any you disagree with",
                          systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let notice = model.autoPickNotice {
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(model.captures) { capture in
                    guideCard(capture)
                }
                Button {
                    // 수집기가 없어도 시트를 연다 — 보내기 시 메일 앱으로 폴백
                    reportNotice = nil
                    reporting = true
                } label: {
                    Label("These frames look wrong", systemImage: "flag")
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                if let reportNotice {
                    Text(reportNotice).font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical)
            // 하단 고정 CTA와 마지막 신고 UI 사이에 시각적 여유를 둔다.
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    Label {
                        Text(verbatim: "\(selectedGuideCount)/\(totalGuideCount)")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: allGuidesSelected
                              ? "checkmark.circle.fill"
                              : "checkmark.circle")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(allGuidesSelected ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(Text("Selected"))
                    .accessibilityValue(Text(verbatim: "\(selectedGuideCount)/\(totalGuideCount)"))

                    Spacer(minLength: 8)

                    Button("Make document") {
                        Task { await model.finishPicking(picks: picks) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!allGuidesSelected)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(.regularMaterial)
        }
        .sheet(isPresented: $reporting) {
            ReportSheet { reason, note in
                await model.submitIssueReport(reason: reason, note: note, picks: picks)
            }
        }
        .onAppear { if picks.isEmpty { picks = model.suggestedPicks() } }
    }

    private var totalGuideCount: Int {
        model.captures.count
    }

    private var selectedGuideCount: Int {
        model.captures.count(where: hasValidPick)
    }

    private var allGuidesSelected: Bool {
        totalGuideCount > 0 && selectedGuideCount == totalGuideCount
    }

    private func hasValidPick(for capture: GuideCapture) -> Bool {
        guard let pick = picks[capture.guide.id] else { return false }
        if pick == "none" { return true }
        return capture.candidates.contains { $0.slot == pick && $0.jpeg != nil }
    }

    @ViewBuilder private func guideCard(_ capture: GuideCapture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(capture.guide.id) · \(capture.guide.phrase)").font(.headline)
            Text(capture.guide.guideText).font(.caption).foregroundStyle(.secondary)
            // AI가 왜 그 장면을 골랐는지 — 사용자가 판단을 뒤집을 근거가 된다
            if let pick = model.autoPicks[capture.guide.id], !pick.reason.isEmpty {
                Label(pick.reason, systemImage: "sparkles")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if capture.failed {
                Label("Capture failed — a link will be used instead", systemImage: "link")
                    .font(.callout).foregroundStyle(.orange)
            } else {
                // 적응형 그리드(아이폰 2열) — 가로 4분할 대비 썸네일 약 2배 (UX 피드백 반영)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(capture.candidates, id: \.slot) { candidate in
                        candidateCell(
                            guideId: capture.guide.id,
                            guidePhrase: capture.guide.phrase,
                            candidate: candidate)
                    }
                    noneCell(
                        guideId: capture.guide.id,
                        guidePhrase: capture.guide.phrase,
                        timestamp: capture.guide.bestVisualTimestamp)
                }
            }
        }
    }

    @ViewBuilder private func candidateCell(
        guideId: String,
        guidePhrase: String,
        candidate: CaptureCandidate
    ) -> some View {
        if candidate.jpeg == nil {
            // 슬롯 단위 실패는 자리표시로 남긴다 — 셀이 그냥 사라지면 후보가 몇 개였는지 알 수 없다
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("\(MarkdownBuilder.hms(candidate.time)) capture failed")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        } else if let jpeg = candidate.jpeg {
            let selected = picks[guideId] == candidate.slot
            let position = positionLabel(for: candidate.slot)
            let time = MarkdownBuilder.hms(candidate.time)
            Button {
                picks[guideId] = candidate.slot
            } label: {
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        JPEGImage(data: jpeg)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                                selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: selected ? 3 : 1))
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .font(.title3)
                                .padding(6)
                                .accessibilityHidden(true)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(verbatim: "\(position) · \(time)")
                        .font(.caption2)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(guidePhrase), \(position), \(time)"))
            .accessibilityValue(selected ? Text("Selected") : Text("Not selected"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Select this frame for the guide")
            .contextMenu {
                Button("Pick this frame") { picks[guideId] = candidate.slot }
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

    private func noneCell(guideId: String, guidePhrase: String, timestamp: Int?) -> some View {
        let selected = picks[guideId] == "none"
        let linkLabel = String(localized: "Use video link instead")
        let time = timestamp.map(MarkdownBuilder.hms)
        let accessibilityLabel = [guidePhrase, linkLabel, time].compactMap { $0 }.joined(separator: ", ")
        return Button {
            picks[guideId] = "none"
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("Doesn't fit\nuse a link")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    if let time {
                        Text(verbatim: time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                    selected ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: selected ? 3 : 1))
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.title3)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityValue(selected ? Text("Selected") : Text("Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Use the timestamped video link for this guide")
    }

    private func positionLabel(for slot: String) -> String {
        switch slot {
        case "before": String(localized: "Before")
        case "center": String(localized: "Key moment")
        case "after": String(localized: "After")
        default: String(localized: "Candidate frame")
        }
    }
}

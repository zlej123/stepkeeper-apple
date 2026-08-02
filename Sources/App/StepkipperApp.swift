import SwiftUI

#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
#endif

@main
struct StepkipperApp: App {
    init() {
        Settings.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["STEPKIPPER_UI_SCENARIO"] == "picker" {
                DebugUIScenarioView()
            } else if ProcessInfo.processInfo.environment["STEPKIPPER_SPIKE"] == "1" {
                SpikeCaptureView()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}

#if DEBUG
/// 네트워크·Keychain 없이 실제 SwiftUI 화면을 Simulator에서 점검하는 개발 전용 진입점.
/// `SIMCTL_CHILD_STEPKIPPER_UI_SCENARIO=picker`로 실행한다. Release에는 컴파일되지 않는다.
@MainActor
private struct DebugUIScenarioView: View {
    @State private var model: AppModel

    init() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkipper-picker-preview-\(UUID().uuidString)")
        let model = AppModel(documentStore: DocumentStore(root: root))
        model.captures = Self.makeCaptures()
        model.stage = .picking
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            AnalyzeFlowView(model: model)
        }
    }

    private static func makeCaptures() -> [GuideCapture] {
        (1...5).map { index in
            let center = index * 24
            let guide = VisualGuide(
                id: "vg-\(index)",
                stepId: index,
                sourcePhrase: "핵심 동작 \(index)",
                phrase: "핵심 동작 \(index)",
                type: "action",
                whatToShow: "동작 전후가 구분되는 장면",
                bestVisualTimestamp: center,
                guideText: "가장 이해하기 쉬운 장면을 고르세요.",
                importance: 1
            )
            let candidates = [
                CaptureCandidate(slot: "before", time: center - 1,
                                 jpeg: makeJPEG(red: 0.30, green: 0.55, blue: 0.95)),
                CaptureCandidate(slot: "center", time: center,
                                 jpeg: makeJPEG(red: 0.28, green: 0.72, blue: 0.52)),
                CaptureCandidate(slot: "after", time: center + 1,
                                 jpeg: makeJPEG(red: 0.94, green: 0.58, blue: 0.28)),
            ]
            return GuideCapture(guide: guide, candidates: candidates)
        }
    }

    private static func makeJPEG(red: CGFloat, green: CGFloat, blue: CGFloat) -> Data? {
        let width = 640
        let height = 360
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(CGColor(gray: 1, alpha: 0.18))
        context.fill(CGRect(
            x: 0,
            y: CGFloat(height) / 2,
            width: CGFloat(width),
            height: CGFloat(height) / 2
        ))

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.78,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif

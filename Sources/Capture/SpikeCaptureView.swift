#if DEBUG
import SwiftUI
import CoreGraphics
import ImageIO

struct SpikeResult: Codable {
    struct Frame: Codable { var t: Int; var bytes: Int; var luminanceStdDev: Double; var ok: Bool }
    var platform: String
    var videoID: String
    var duration: Int
    var title: String
    var frames: [Frame]
    var ok: Bool
}

@MainActor
final class SpikeRunner: ObservableObject {
    @Published var status = "대기"
    @Published var images: [CGImage] = []
    let bridge = PlayerBridge()
    static let videoID = "4ioPBiTWm3M"  // 코어 README 데모 영상
    static let times = [10, 30, 60]

    func run() async {
        do {
            Self.keepWindowVisible()
            Self.log("run 시작 — 플레이어 로드")
            status = "플레이어 로드 중"
            bridge.load(videoID: Self.videoID)
            try await Task.sleep(for: .seconds(3))
            Self.log("메타데이터 대기 시작")
            // 타임아웃 90초: 스킵 불가 광고(56~137초 실측)가 본편 메타데이터를 지연시킬 수 있다.
            let meta = try await bridge.waitForMetadata(expecting: Self.videoID, timeout: 90)
            Self.log("메타데이터 획득: \(meta.duration)s — prime 시작")
            status = "메타데이터: \(meta.duration)s — 프레임 디코딩 유도"
            try await bridge.primePlayer()
            Self.log("prime 완료 — 캡처 시작")
            var frames: [SpikeResult.Frame] = []
            for t in Self.times {
                Self.keepWindowVisible()
                status = "캡처 중 t=\(t)s"
                Self.log("캡처 t=\(t)s")
                let data = try await bridge.captureFrame(at: t)
                let std = Self.luminanceStdDev(jpeg: data) ?? 0
                frames.append(.init(t: t, bytes: data.count, luminanceStdDev: std, ok: std > 8))
                if let img = Self.cgImage(jpeg: data) { images.append(img) }
                try Self.write(data, name: "frame-\(t).jpg")
            }
            let result = SpikeResult(
                platform: Self.platformName, videoID: Self.videoID,
                duration: meta.duration, title: meta.title,
                frames: frames, ok: frames.allSatisfy(\.ok) && frames.count == Self.times.count)
            let json = try JSONEncoder().encode(result)
            try Self.write(json, name: "result.json")
            status = result.ok ? "성공 — result.json 저장됨" : "실패 — 프레임 검증 미달"
        } catch is CancellationError {
            // SwiftUI가 씬 활성화 과정에서 .task를 취소·재시작할 수 있다(iOS 실측) —
            // 취소된 시도가 error result.json으로 실제 결과를 덮어쓰지 않게 한다.
            Self.log("run 취소됨")
            status = "취소됨 — 재시작 대기"
        } catch {
            Self.log("run 실패: \(error)")
            status = "실패: \(error.localizedDescription)"
            // 실패 원인 기록용 페이지 상태 프로브 (spike-capture.md 증거)
            let probe = (try? await bridge.probePageState()) ?? "probe unavailable"
            if let json = try? JSONEncoder().encode(
                ["error": String(describing: error), "platform": Self.platformName, "page": probe]) {
                try? Self.write(json, name: "result.json")
            }
        }
    }

    static var platformName: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }

    /// macOS 실측: 창이 가려지면 visibilityState=hidden → 유튜브가 본편 재생을 시작하지 않고
    /// 페이지 타이머도 스로틀된다. 14+에선 백그라운드 앱의 activate가 거부될 수 있어
    /// orderFrontRegardless + floating 레벨로 스파이크 동안 창을 확실히 노출시킨다.
    static func keepWindowVisible() {
        #if os(macOS)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first {
            window.level = .floating
            window.orderFrontRegardless()
        }
        #endif
    }

    static func spikeDir() throws -> URL {
        #if os(macOS)
        // 예방적 어댑테이션(macOS): ad-hoc 서명은 리빌드마다 해시(LC_UUID)가 바뀌어 macOS가
        // Documents 폴더 접근을 매번 "최초 요청"으로 취급할 수 있고, 그때 뜨는 TCC 동의
        // 대화상자는 비대화형 실행에서 응답 주체가 없어 FileManager 호출이 막힐 수 있다.
        // (이 세션의 실제 행 원인은 별도로 진단됨 — 아래 참고. 이 변경은 확인되지 않은 채로
        // 남겨둔 리스크를 선제 제거하는 차원 — spike-capture.md의 "macOS 진단" 절 참고.)
        // 스파이크 산출물은 사용자 문서가 아니므로 TCC 게이트가 없는 Caches로 우회.
        let base = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #else
        let base = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #endif
        let dir = base.appendingPathComponent("spike", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(_ data: Data, name: String) throws {
        try data.write(to: spikeDir().appendingPathComponent(name))
    }

    /// 스파이크 진행 위치 추적용 브레드크럼 (status.log) — 화면 접근 없이 실패 지점을 특정한다.
    static func log(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        guard let dir = try? spikeDir(), let data = line.data(using: .utf8) else { return }
        let url = dir.appendingPathComponent("status.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    static func cgImage(jpeg: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// 8x8로 다운샘플한 그레이스케일 휘도의 표준편차 — 순흑/단색 프레임 판별
    static func luminanceStdDev(jpeg: Data) -> Double? {
        guard let image = cgImage(jpeg: jpeg) else { return nil }
        let w = 8, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let values = pixels.map(Double.init)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return variance.squareRoot()
    }
}

struct SpikeCaptureView: View {
    @StateObject private var runner = SpikeRunner()
    var body: some View {
        VStack(spacing: 12) {
            Text("M0 캡처 스파이크").font(.headline)
            Text(runner.status).font(.callout).foregroundStyle(.secondary)
            PlayerWebView(bridge: runner.bridge).frame(minHeight: 220)
            HStack {
                ForEach(Array(runner.images.enumerated()), id: \.offset) { _, img in
                    Image(img, scale: 1, label: Text("frame"))
                        .resizable().scaledToFit().frame(height: 70)
                }
            }
        }
        .padding()
        .task {
            if ProcessInfo.processInfo.environment["STEPKIPPER_SPIKE"] == "1" { await runner.run() }
        }
        .toolbar { Button("실행") { Task { await runner.run() } } }
    }
}
#endif

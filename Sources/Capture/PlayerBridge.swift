import WebKit

enum PlayerError: Error, LocalizedError, Equatable {
    case loadFailed(String), metadataTimeout, seekTimeout(Int), captureFailed(String), emptyFrame
    var errorDescription: String? {
        switch self {
        case .loadFailed(let m): return "플레이어 로드 실패: \(m)"
        case .metadataTimeout: return "영상 정보를 가져오지 못했습니다"
        case .seekTimeout(let t): return "장면 이동 시간 초과 (\(t)s)"
        case .captureFailed(let m): return "캡처 실패: \(m)"
        case .emptyFrame: return "빈 프레임"
        }
    }
}

@MainActor
final class PlayerBridge: NSObject, ObservableObject {
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        #if os(iOS)
        // macOS WKWebViewConfiguration에는 allowsInlineMediaPlayback가 없다(TARGET_OS_IPHONE 전용 API) — 브리프 코드에서 컴파일러가 강제한 어댑테이션.
        config.allowsInlineMediaPlayback = true
        #endif
        config.mediaTypesRequiringUserActionForPlayback = []
        // 런타임 강제 어댑테이션(macOS 실측): atDocumentEnd(DOMContentLoaded)는 유튜브 데스크톱
        // 페이지에서 20초+ 지연돼 브리지가 제때 생기지 않았다. 스크립트는 호출 시점에만 DOM을
        // 조회하므로 atDocumentStart 주입이 안전하다.
        config.userContentController.addUserScript(WKUserScript(
            source: CaptureScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
    }

    func load(videoID: String) {
        #if os(macOS)
        // 우회책 적용(스펙 4.4-8 예고 경로, spike-capture.md 기록): macOS에서 m. 로드는
        // www로 리다이렉트되지만 seek 시 미디어 데이터를 가져오지 않아(seek timeout, readyState=1)
        // www 직접 로드 + Safari 데스크톱 UA로 전환.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        #else
        // 스펙 4.4-8: iOS는 m.youtube.com (실측 검증 완료)
        let url = URL(string: "https://m.youtube.com/watch?v=\(videoID)")!
        #endif
        webView.load(URLRequest(url: url))
    }

    /// 런타임 강제 어댑테이션(macOS 실측): 페이지가 hidden 스로틀되면 JS 타이머가 멈춰
    /// callAsyncJavaScript가 영원히 안 돌아온다 → Swift 쪽 타임아웃 워치독으로 감싼다.
    /// Swift 6 Sendable 제약으로 반환은 String?로 통일(JS 쪽에서 JSON.stringify).
    private func callJS(_ body: String, timeout: TimeInterval) async throws -> String? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String?, Error>) in
            var resumed = false
            webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { result in
                guard !resumed else { return }
                resumed = true
                switch result {
                case .success(let value): cont.resume(returning: value as? String)
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard !resumed else { return }
                resumed = true
                cont.resume(throwing: PlayerError.captureFailed("JS 응답 시간 초과 (\(Int(timeout))s)"))
            }
        }
    }

    func waitForMetadata(expecting videoID: String? = nil,
                         timeout: TimeInterval = 20) async throws -> (duration: Int, title: String) {
        // 런타임 강제 어댑테이션(iOS 시뮬레이터 실측): 유튜브 첫 로드는 재내비게이션을 거치며
        // 그 사이 주입 스크립트(atDocumentEnd)가 아직 없거나 사라진다 — 장기 waitMeta 한 방 호출은
        // "undefined is not an object" TypeError로 깨졌다. 짧은 waitMeta 호출을 데드라인까지 반복한다.
        let deadline = Date().addingTimeInterval(timeout)
        // expectId: videoID는 유튜브 ID 형식([\w-]{11})이라 JS 문자열 인젝션 불가 — 따옴표로만 감싼다.
        let expectId = videoID.map { "\"\($0)\"" } ?? "null"
        while Date() < deadline {
            try Task.checkCancellation()
            let result = try? await callJS(
                "if (!window.__stepkeeper) { return null; } return JSON.stringify(await window.__stepkeeper.waitMeta(1500, \(expectId)));",
                timeout: 5)
            if let json = result,
               let dict = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
               let duration = (dict["duration"] as? NSNumber)?.intValue,
               let title = dict["title"] as? String, duration > 0 {
                return (duration, title)
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw PlayerError.metadataTimeout
    }

    func primePlayer() async throws {
        // prime() 최악 경로: play 대기 500ms + readyState 폴링 5s → 워치독 10s
        _ = try await callJS("await window.__stepkeeper.prime(); return \"ok\";", timeout: 10)
    }

    /// 스파이크 실패 진단용: 현재 페이지 URL·video 엘리먼트 상태를 한 줄로 반환.
    func probePageState() async throws -> String {
        let js = """
        const v = document.querySelector("video");
        const mp = document.querySelector("#movie_player");
        const buf = v && v.buffered && v.buffered.length ? v.buffered.end(v.buffered.length - 1).toFixed(1) : "0";
        return location.href + " | bridge=" + typeof window.__stepkeeper + " | vis=" + document.visibilityState + " | playerState=" + (mp && mp.getPlayerState ? mp.getPlayerState() : "n/a") + " | video=" + (v ? ("w=" + v.videoWidth + " rs=" + v.readyState + " paused=" + v.paused + " buf=" + buf + " dur=" + v.duration) : "none") + " | title=" + document.title;
        """
        return try await callJS(js, timeout: 3) ?? "no result"
    }

    func captureFrame(at seconds: Int) async throws -> Data {
        let result: String?
        do {
            // capture() 최악 경로: 광고 대기 8s + seek 8s + 프레임 제시 대기 8s → 워치독 30s
            result = try await callJS(
                "return await window.__stepkeeper.capture(\(seconds), 8000);", timeout: 30)
        } catch {
            throw PlayerError.captureFailed(String(describing: error))
        }
        guard let dataURL = result,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              !data.isEmpty else {
            throw PlayerError.emptyFrame
        }
        return data
    }

    /// 캡처 세션 시작: 플레이어 상태 저장 후 음소거·정지 (프레임 디코딩 유도 포함)
    func beginCaptureSession() async throws {
        do {
            _ = try await callJS("return await window.__stepkeeper.captureBegin();", timeout: 8)
        } catch {
            throw PlayerError.captureFailed("세션 시작 실패: \(error)")
        }
    }

    /// 캡처 세션 종료: currentTime·muted·재생 상태 복원 (실패해도 무시)
    func endCaptureSession() async {
        _ = try? await callJS("return await window.__stepkeeper.captureEnd();", timeout: 5)
    }
}

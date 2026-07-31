// 유튜브 페이지에 주입하는 캡처 스크립트. video 엘리먼트 외에 광고 감지/스킵 셀렉터
// (.ad-showing, .ad-interrupting, .ytp-skip-ad-button, .ytp-ad-skip-button,
// .ytp-ad-skip-button-modern)와 prime()의 #movie_player에도 의존한다 — "DOM 구조
// 독립"은 아니며, 광고 처리·cued 상태 재생 문제 때문에 의도적으로 트레이드오프됐다
// (docs/spike-capture.md 참고).
enum CaptureScript {
    static let source = #"""
    (() => {
      if (window.__stepkipper) return;
      const video = () => document.querySelector("video");
      const sleep = (ms) => new Promise(r => setTimeout(r, ms));
      // 광고 대응(macOS www 실측: 프리롤 광고가 video 엘리먼트를 점유해 잘못된 프레임이 잡힘).
      // video 외 DOM 의존 중 하나 — .ad-showing/스킵 버튼은 수년간 안정적인 유튜브 플레이어
      // 클래스. 다른 하나는 prime()의 #movie_player(플레이어 API 접근용, 아래 참고).
      const adShowing = () => !!document.querySelector(".ad-showing, .ad-interrupting");
      function trySkipAd() {
        const b = document.querySelector(
          ".ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern");
        if (b) b.click();
      }
      // 내비게이션 커밋 전엔 이전 페이지에서 실행되므로 기대 영상 href 확인 필수 (최종 리뷰 Critical 2)
      async function waitMeta(timeoutMs, expectId) {
        const t0 = Date.now();
        while (Date.now() - t0 < timeoutMs) {
          if (adShowing()) { trySkipAd(); await sleep(300); continue; }
          const v = video();
          if (v && v.readyState >= 1 && isFinite(v.duration) && v.duration > 0
              && (!expectId || location.href.indexOf(expectId) !== -1)) {
            return { duration: Math.floor(v.duration), title: document.title };
          }
          await sleep(200);
        }
        throw new Error("metadata timeout");
      }
      function seek(v, t, timeoutMs) {
        return new Promise((resolve, reject) => {
          const timer = setTimeout(() => { v.removeEventListener("seeked", done); reject(new Error("seek timeout " + t)); }, timeoutMs);
          const done = () => { clearTimeout(timer); v.removeEventListener("seeked", done); resolve(); };
          v.addEventListener("seeked", done);
          v.currentTime = t;
        });
      }
      // macOS 실측: seeked 발화 후에도 새 프레임 합성 전이면 drawImage가 직전 프레임을 그린다
      // (t=10과 t=60이 바이트 동일). 새 프레임 제시까지 rVFC로 대기, 미지원이면 150ms 폴백.
      function nextPresentedFrame(v, timeoutMs) {
        return new Promise((resolve) => {
          if (!v.requestVideoFrameCallback) { setTimeout(() => resolve(false), 150); return; }
          let settled = false;
          const timer = setTimeout(() => { if (!settled) { settled = true; resolve(false); } }, timeoutMs);
          v.requestVideoFrameCallback(() => {
            if (!settled) { settled = true; clearTimeout(timer); resolve(true); }
          });
        });
      }
      async function capture(t, timeoutMs) {
        const t0 = Date.now();
        while (adShowing() && Date.now() - t0 < timeoutMs) { trySkipAd(); await sleep(300); }
        if (adShowing()) throw new Error("ad not skippable");
        const v = video(); // 광고 후 엘리먼트가 교체될 수 있어 대기 후 다시 조회
        if (!v || !v.videoWidth) throw new Error("no player");
        const presented = nextPresentedFrame(v, timeoutMs); // seek 전에 등록해 레이스 방지
        await seek(v, t, timeoutMs);
        await presented;
        await sleep(150); // 렌더 안정화 (content.js와 동일)
        const c = document.createElement("canvas");
        c.width = v.videoWidth; c.height = v.videoHeight;
        c.getContext("2d").drawImage(v, 0, 0);
        return c.toDataURL("image/jpeg", 0.85);
      }
      async function prime() { // muted 재생으로 프레임 디코딩 유도 후 정지
        const v = video();
        if (!v) throw new Error("no player");
        v.muted = true;
        // macOS www 실측: cued 상태의 데스크톱 플레이어는 v.play()로는 세그먼트를 안 가져온다
        // (readyState=1 정체, seeked 미발화) → 플레이어 API playVideo()로 재생 개시.
        const mp = document.querySelector("#movie_player");
        try { if (mp && mp.mute) mp.mute(); if (mp && mp.playVideo) mp.playVideo(); } catch (e) {}
        try { await v.play(); } catch (e) {}
        await sleep(500);
        // 미디어 데이터 확보 대기 (최대 5초): 광고가 끼면 스킵 시도
        const t0 = Date.now();
        while (v.readyState < 2 && Date.now() - t0 < 5000) { trySkipAd(); await sleep(200); }
        v.pause();
        return true;
      }
      async function captureBegin() {   // content.js 패턴: 상태 저장 → 음소거·정지
        const v = video();
        if (!v) throw new Error("no player");
        window.__cnSaved = { muted: v.muted, paused: v.paused, t: v.currentTime };
        v.muted = true;
        try { await v.play(); } catch (e) {}
        await sleep(300);
        v.pause();
        return true;
      }
      async function captureEnd() {     // 원위치 복원
        const v = video();
        const s = window.__cnSaved;
        if (!v || !s) return false;
        v.currentTime = s.t;
        v.muted = s.muted;
        if (!s.paused) { try { await v.play(); } catch (e) {} }
        return true;
      }
      window.__stepkipper = { waitMeta, capture, prime, captureBegin, captureEnd };
    })();
    """#
}

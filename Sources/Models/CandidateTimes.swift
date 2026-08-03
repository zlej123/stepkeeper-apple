/// capture.py::candidate_times 포팅 — 후보 3장을 center 주변에서 뽑는다.
///
/// 예전에는 before/after를 스텝 경계(t_start-1, t_end+1)에 뒀는데, 긴 스텝에서는 그 둘이
/// **다른 주제**를 찍는다. 실측: 19초짜리 스텝에서 후보가 18·31·39초로 잡혔고 18초는 이전 섹션,
/// 39초는 다음 섹션이라, 가이드가 요구한 26~29초 동작이 세 장 어디에도 없었다.
/// 동작 가이드는 center±1초, 나머지는 최대 ±2초로 제한해 서로 다른 작업 단계가 섞이지 않게 한다.
struct CandidateTimes: Equatable, Sendable {
    /// 코어 ACTION_CANDIDATE_SPREAD / DEFAULT_CANDIDATE_SPREAD와 동일해야 한다.
    static let actionSpreadLimit = 1
    static let defaultSpreadLimit = 2

    let before: Int
    let center: Int
    let after: Int

    init(step: Step?, center: Int, duration: Int, guideType: String) {
        self.center = center
        let last = max(0, duration - 1)
        let limit = guideType == "action" ? Self.actionSpreadLimit : Self.defaultSpreadLimit
        let spread: Int
        if let step {
            let length = max(0, step.tEnd - step.tStart)
            spread = max(1, min(limit, length / 4))
        } else {
            spread = limit
        }
        var before = max(0, center - spread)
        var after = min(last, center + spread)
        // 후보가 스텝 경계를 넘으면 이전/다음 단계의 장면이 들어온다 (외부 리뷰 P2-3).
        // 단 center가 스텝 밖이면 스텝 정보를 불신하고 클램프하지 않는다 — 코어와 동일.
        if let step, step.tStart <= center, center <= step.tEnd {
            before = max(before, step.tStart)
            after = min(after, step.tEnd)
        }
        self.before = before
        self.after = after
    }

    var slots: [(slot: String, time: Int)] {
        [("before", before), ("center", center), ("after", after)]
    }
}

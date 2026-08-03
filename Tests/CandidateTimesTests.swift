import Testing
@testable import stepkipper

struct CandidateTimesTests {
    private func makeStep(_ tStart: Int, _ tEnd: Int) -> Step {
        Step(id: 1, summary: "s", detail: "d", tStart: tStart, tEnd: tEnd)
    }
    /// 후보는 스텝 경계가 아니라 center 주변에서 뽑는다 — 긴 스텝에서 경계 후보는 다른
    /// 주제를 찍어, 정작 가이드가 요구한 순간이 세 장 어디에도 없는 일이 실제로 있었다.
    @Test func staysNearCenterEvenOnLongSteps() {
        let action = CandidateTimes(step: makeStep(10, 20), center: 15, duration: 100,
                                    guideType: "action")
        #expect(action.before == 14 && action.center == 15 && action.after == 16)
        let state = CandidateTimes(step: makeStep(19, 38), center: 31, duration: 82,
                                   guideType: "state")
        #expect(state.before == 29 && state.center == 31 && state.after == 33)
    }
    @Test func keepsAtLeastOneSecondApart() {
        let t = CandidateTimes(step: makeStep(9, 12), center: 10, duration: 30,
                               guideType: "state")
        #expect(t.before == 9 && t.after == 11)   // 세 장이 같은 프레임이면 선택이 무의미하다
    }
    @Test func clampsToVideoRange() {
        let t = CandidateTimes(step: makeStep(0, 99), center: 1, duration: 100,
                               guideType: "state")
        #expect(t.before == 0)                    // center-spread가 음수여도 0
        let end = CandidateTimes(step: makeStep(0, 99), center: 98, duration: 100,
                                 guideType: "state")
        #expect(end.after == 99)                  // duration-1 클램프
    }
    /// 스텝 경계 클램프 (외부 리뷰 P2-3): 스텝이 10초에 시작하고 center=10이면
    /// before=9는 이전 단계의 장면이다.
    @Test func clampsToStepBoundaries() {
        let start = CandidateTimes(step: makeStep(10, 30), center: 10, duration: 100,
                                   guideType: "state")
        #expect(start.before == 10 && start.after == 12)
        let end = CandidateTimes(step: makeStep(0, 20), center: 20, duration: 100,
                                 guideType: "state")
        #expect(end.before == 18 && end.after == 20)
    }
    @Test func centerOutsideStepDistrustsStepBoundaries() {
        // 모델이 준 center가 스텝 밖이면 스텝 정보를 불신한다 — 경계로 끌어오면
        // "가장 잘 보이는 순간"에서 멀어진다
        let t = CandidateTimes(step: makeStep(10, 20), center: 40, duration: 100,
                               guideType: "state")
        #expect(t.before == 38 && t.center == 40 && t.after == 42)
    }
    @Test func withoutStepUsesGuideTypeLimit() {
        let t = CandidateTimes(step: nil, center: 2, duration: 100, guideType: "state")
        #expect(t.before == 0 && t.center == 2 && t.after == 4)
    }
    @Test func withoutStepClampsAfterToDurationEnd() {
        let t = CandidateTimes(step: nil, center: 97, duration: 100, guideType: "state")
        #expect(t.before == 95 && t.after == 99)
    }
    @Test func slotsOrderIsBeforeCenterAfter() {
        let t = CandidateTimes(step: nil, center: 10, duration: 100,
                               guideType: "action")
        #expect(t.slots.map(\.slot) == ["before", "center", "after"])
        #expect(t.slots.map(\.time) == [9, 10, 11])
    }
}

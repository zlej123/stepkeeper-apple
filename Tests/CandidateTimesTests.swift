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

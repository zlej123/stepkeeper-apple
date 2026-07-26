import Testing
@testable import stepkeeper

struct CandidateTimesTests {
    private func makeStep(_ tStart: Int, _ tEnd: Int) -> Step {
        Step(id: 1, summary: "s", detail: "d", tStart: tStart, tEnd: tEnd)
    }
    @Test func withStepSpreadsAcrossStep() {
        let t = CandidateTimes(step: makeStep(10, 20), center: 15, duration: 100)
        #expect(t.before == 9 && t.center == 15 && t.after == 21)
    }
    @Test func clampsToVideoRange() {
        let t = CandidateTimes(step: makeStep(0, 99), center: 50, duration: 100)
        #expect(t.before == 0 && t.after == 99)   // duration-1 클램프
    }
    @Test func withoutStepUsesPlusMinus4() {
        let t = CandidateTimes(step: nil, center: 2, duration: 100)
        #expect(t.before == 0 && t.center == 2 && t.after == 6)
    }
    @Test func withoutStepClampsAfterToDurationEnd() {
        let t = CandidateTimes(step: nil, center: 97, duration: 100)
        #expect(t.before == 93 && t.after == 99)   // after = min(duration-1, center+4)
    }
    @Test func slotsOrderIsBeforeCenterAfter() {
        let t = CandidateTimes(step: nil, center: 10, duration: 100)
        #expect(t.slots.map(\.slot) == ["before", "center", "after"])
        #expect(t.slots.map(\.time) == [6, 10, 14])
    }
}

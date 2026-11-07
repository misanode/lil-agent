import Foundation

func require(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

func harness(entered: Bool = false) -> (StartupCoordinator, () -> [String]) {
    var log: [String] = []
    let startup = StartupCoordinator(entered: entered)
    startup.onFinish = { log.append("finish") }
    startup.onFail = { log.append("fail:\($0)") }
    return (startup, { log })
}

do {
    let (s, log) = harness()
    s.appReady()
    require(log().isEmpty && s.phase == .starting, "ready before entrance must wait")
    s.entranceDone()
    require(log() == ["finish"] && s.phase == .finished, "ready then entrance must finish")
}
do {
    let (s, log) = harness()
    s.entranceDone()
    require(log().isEmpty, "entrance before ready must wait")
    s.appReady()
    s.appReady()
    require(log() == ["finish"], "finishes exactly once")
}
do {
    let (s, log) = harness()
    s.entranceDone()
    s.fail("model missing")
    s.fail("again")
    s.appReady()
    require(log() == ["fail:model missing"] && s.phase == .failed, "failure is final")
}
do {
    let (s, log) = harness(entered: true)
    s.appReady()
    s.fail("late")
    require(log() == ["finish"], "late failures are ignored")
}
do {
    let (s, log) = harness()
    s.cancel()
    s.entranceDone()
    s.appReady()
    s.fail("after quit")
    require(log().isEmpty && s.phase == .cancelled, "quit cancels startup")
}
print("startup checks passed")

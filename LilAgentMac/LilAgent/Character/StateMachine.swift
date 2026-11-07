import Foundation

struct Params {
    var then: String?
    var x: Double?
    var lift: Double?
    var mood: String?
    var loop = false
    var count: Int?
    var side: String?
    var vx: Double?
    var vy: Double?
    var duration: Double?
}

struct Transition {
    var name: String
    var params: Params

    init(_ name: String, _ params: Params = Params()) {
        self.name = name
        self.params = params
    }
}

struct StateInfo {
    var priority = 0
    var autoLook = true
    var blink = true
    var attentive = true
    var turnBody = true
    var freeLift = false
}

class PetState {
    class var info: StateInfo { StateInfo() }
    required init() {}
    func enter(_ c: Pet, _ p: Params) {}
    func update(_ c: Pet, _ dt: Double, _ t: Double, _ p: Params) -> Transition? { nil }
    func exit(_ c: Pet) {}
}

func then(_ p: Params, _ fallback: String = "idle") -> Transition { Transition(p.then ?? fallback) }

final class StateMachine {
    unowned let ctx: Pet
    private(set) var name: String?
    private(set) var state: PetState?
    private(set) var params = Params()
    private(set) var time = 0.0
    var listeners: [(String, String?) -> Void] = []

    init(_ ctx: Pet) { self.ctx = ctx }

    var info: StateInfo { state.map { type(of: $0).info } ?? StateInfo() }

    func go(_ next: Transition) {
        guard let type = STATES[next.name] else { return }
        let prev = name
        state?.exit(ctx)
        let s = type.init()
        name = next.name
        state = s
        params = next.params
        time = 0
        s.enter(ctx, params)
        for fn in listeners { fn(next.name, prev) }
    }

    func update(_ dt: Double) {
        guard let state else { return }
        time += dt
        if let next = state.update(ctx, dt, time, params) { go(next) }
    }
}

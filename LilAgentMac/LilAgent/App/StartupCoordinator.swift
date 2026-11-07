import Foundation

final class StartupCoordinator {
    enum Phase: Equatable {
        case starting, finished, failed, cancelled
    }

    private(set) var phase = Phase.starting
    private var entered: Bool
    private var ready = false
    var onFinish: (() -> Void)?
    var onFail: ((String) -> Void)?

    init(entered: Bool = false) {
        self.entered = entered
    }

    func entranceDone() {
        guard phase == .starting else { return }
        entered = true
        finishIfReady()
    }

    func appReady() {
        guard phase == .starting else { return }
        ready = true
        finishIfReady()
    }

    func fail(_ message: String) {
        guard phase == .starting else { return }
        phase = .failed
        onFail?(message)
    }

    func cancel() {
        guard phase == .starting else { return }
        phase = .cancelled
    }

    private func finishIfReady() {
        guard entered, ready else { return }
        phase = .finished
        onFinish?()
    }
}

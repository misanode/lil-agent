import Foundation

enum UpdateStatus: Equatable {
    case idle, checking, current, failed
    case available(version: String, page: URL)
}

final class UpdateChecker {
    static let repository = ProcessInfo.processInfo.environment["LILAGENT_UPDATE_REPO"] ?? "misanode/lil-agent"
    static let interval: TimeInterval = 24 * 60 * 60

    private(set) var status = UpdateStatus.idle {
        didSet { if status != oldValue { onChange?(status) } }
    }
    var onChange: ((UpdateStatus) -> Void)?
    private let current: String
    private let session: URLSession
    private var timer: Timer?

    init(current: String, session: URLSession = .shared) {
        self.current = current
        self.session = session
    }

    func start() {
        check(quiet: true)
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in self?.check(quiet: true) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func check(quiet: Bool = false) {
        guard status != .checking else { return }
        let previous = status
        if !quiet { status = .checking }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Brand.name.replacingOccurrences(of: " ", with: "-"), forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        session.dataTask(with: request) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result = Self.evaluate(data: data, statusCode: error == nil ? code : 0, current: self?.current ?? "0")
            DispatchQueue.main.async {
                guard let self else { return }
                if result == .failed && quiet { self.status = previous == .checking ? .idle : previous }
                else { self.status = result }
            }
        }.resume()
    }

    static func evaluate(data: Data?, statusCode: Int, current: String) -> UpdateStatus {
        if statusCode == 404 { return .current }
        guard statusCode == 200, let data,
              let release = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = release["tag_name"] as? String else { return .failed }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        guard compare(version, current) > 0 else { return .current }
        let prefix = "https://github.com/\(repository)/"
        let fallback = URL(string: "\(prefix)releases/latest")!
        let page = (release["html_url"] as? String).flatMap { $0.hasPrefix(prefix) ? URL(string: $0) : nil } ?? fallback
        return .available(version: version, page: page)
    }

    static func compare(_ a: String, _ b: String) -> Int {
        let parts = { (v: String) in v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? [] }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }
}

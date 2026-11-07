import Foundation

func require(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

func release(_ tag: String, _ page: String = "https://github.com/\(UpdateChecker.repository)/releases/tag/v9") -> Data {
    try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": page])
}

require(UpdateChecker.compare("1.0", "1.0.0") == 0, "1.0 equals 1.0.0")
require(UpdateChecker.compare("1.0.1", "1.0") > 0, "1.0.1 is newer than 1.0")
require(UpdateChecker.compare("1.10", "1.9") > 0, "numeric, not text, comparison")
require(UpdateChecker.compare("2.0-beta", "2.0") == 0, "suffixes are ignored")
require(UpdateChecker.evaluate(data: release("v1.1.0"), statusCode: 200, current: "1.0") ==
        .available(version: "1.1.0", page: URL(string: "https://github.com/\(UpdateChecker.repository)/releases/tag/v9")!), "newer release is offered")
require(UpdateChecker.evaluate(data: release("v1.0.0"), statusCode: 200, current: "1.0") == .current, "same version is current")
require(UpdateChecker.evaluate(data: release("v0.9"), statusCode: 200, current: "1.0") == .current, "older release is ignored")
require(UpdateChecker.evaluate(data: nil, statusCode: 404, current: "1.0") == .current, "no releases yet is current")
require(UpdateChecker.evaluate(data: nil, statusCode: 0, current: "1.0") == .failed, "network errors fail")
require(UpdateChecker.evaluate(data: Data("{}".utf8), statusCode: 200, current: "1.0") == .failed, "bad payloads fail")
if case .available(_, let page) = UpdateChecker.evaluate(data: release("v2", "https://evil.example/download"), statusCode: 200, current: "1.0") {
    require(page.absoluteString == "https://github.com/\(UpdateChecker.repository)/releases/latest", "only the project's own release pages open")
} else { require(false, "foreign links still report the update") }
print("update checks passed")

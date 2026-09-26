import Foundation

/// Minimal assertion helper shared by the check suites.
///
/// The app is a SwiftPM *executable* target, so it cannot be imported by an XCTest bundle.
/// Each suite is therefore a small standalone program compiled together with the sources it
/// exercises; `Tests/run-tests.sh` builds and runs them all.
final class Checks {

    private var failures = 0
    private var total = 0
    private let suite: String

    init(_ suite: String) {
        self.suite = suite
        print("── \(suite)")
    }

    func that(_ label: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        total += 1
        if condition {
            print("   ok    \(label)")
        } else {
            failures += 1
            let extra = detail()
            print("   FAIL  \(label)\(extra.isEmpty ? "" : " — \(extra)")")
        }
    }

    func equal<T: Equatable>(_ label: String, _ actual: T, _ expected: T) {
        that(label, actual == expected, "got \(actual), expected \(expected)")
    }

    /// Prints the summary and terminates with a non-zero status when anything failed.
    func finish() -> Never {
        if failures == 0 {
            print("   \(total)/\(total) checks passed\n")
            exit(0)
        }
        print("   \(failures) of \(total) checks FAILED in \(suite)\n")
        exit(1)
    }
}

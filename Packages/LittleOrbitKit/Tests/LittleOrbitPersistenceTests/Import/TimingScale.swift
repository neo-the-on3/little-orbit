import Foundation
import Testing

/// #265: the one place the #235 timing suite compares a measured time with its wall-clock bound. The bounds are
/// for Tester2's Mac, and its build notes check them at scale 1. macOS CI runners have been seen up to about 2.2x
/// slower (#278, run 40448359202), so only `.github/workflows/ci.yml` sets `LITTLE_ORBIT_TIMING_SCALE=3`, and CI
/// then catches only gross regressions. 3 is also the clamp maximum, so a further CI miss is a decision under
/// #282, not another bump. Nothing else sets it, so local and tester runs use the real bounds.
///
/// Unset means 1. A number is clamped to 1–3, so a scale can never tighten a bound or hide a 10x regression. Any
/// other value throws, which fails the test instead of quietly running at 1.
enum TimingScale {
    static let variable = "LITTLE_ORBIT_TIMING_SCALE"
    static let range: ClosedRange<Double> = 1...3

    struct Unparsable: Error, CustomStringConvertible {
        let raw: String
        var description: String {
            "\(TimingScale.variable)=\"\(raw)\" is not a number. Unset it for 1, or set a number from 1 to 3."
        }
    }

    /// The scale for a raw value of the variable: 1 when it's unset, the number clamped to 1–3, or a throw.
    static func scale(from raw: String?) throws -> Double {
        guard let raw else {
            return 1
        }
        guard let value = Double(raw.trimmingCharacters(in: .whitespaces)), value.isFinite else {
            throw Unparsable(raw: raw)
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// The scale this test process runs at, read from its environment.
    static func current(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Double {
        try scale(from: environment[variable])
    }

    /// Expects `measured < bound * scale`, and prints the measured time, the raw bound and the scale either way,
    /// so a CI log shows the margin. Throws, failing the test, if the variable is set to something that isn't a
    /// number.
    static func expect(
        _ name: String,
        _ measured: Duration,
        under bound: Duration,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        let scale = try current(environment)
        let scaled = bound * scale
        let line = "\(name) \(measured) against bound \(bound) x scale \(scale) = \(scaled)"
        print("Timing bound: \(line)")
        #expect(measured < scaled, "\(line)", sourceLocation: sourceLocation)
    }
}

import Testing

/// #265: `TimingScale`, which every #235 timing bound goes through. Runs on every platform.
@Suite("Timing scale for wall-clock bounds (#265)")
struct TimingScaleTests {
    @Test("Unset means the real bounds")
    func unsetIsOne() throws {
        #expect(try TimingScale.scale(from: nil) == 1)
        #expect(try TimingScale.current([:]) == 1)
    }

    @Test("A number is used, clamped to 1–3")
    func numbersAreClamped() throws {
        #expect(try TimingScale.scale(from: "2") == 2)
        #expect(try TimingScale.scale(from: " 1.5 ") == 1.5)
        #expect(try TimingScale.scale(from: "0.5") == 1)
        #expect(try TimingScale.scale(from: "-4") == 1)
        #expect(try TimingScale.scale(from: "10") == 3)
        #expect(try TimingScale.current([TimingScale.variable: "2"]) == 2)
    }

    @Test("Anything else fails rather than falling back to 1", arguments: ["abc", "", "2x", "nan", "inf"])
    func unparsableThrows(_ raw: String) {
        #expect(throws: TimingScale.Unparsable.self) {
            try TimingScale.scale(from: raw)
        }
        #expect(throws: TimingScale.Unparsable.self) {
            try TimingScale.expect(
                "probe",
                .milliseconds(1),
                under: .seconds(1),
                environment: [TimingScale.variable: raw],
            )
        }
    }

    @Test("The bound is multiplied by the scale, never changed")
    func boundIsScaled() throws {
        try TimingScale.expect("at 1", .milliseconds(99), under: .milliseconds(100), environment: [:])
        try TimingScale.expect(
            "at 2",
            .milliseconds(150),
            under: .milliseconds(100),
            environment: [TimingScale.variable: "2"],
        )
    }

    /// This process's own scale, printed. With the variable set to something that isn't a number, this fails.
    @Test("This run's scale")
    func thisRun() throws {
        let scale = try TimingScale.current()
        print("Timing scale: \(TimingScale.variable) gives \(scale)")
        #expect(TimingScale.range.contains(scale))
    }
}

import XCTest
@testable import ProofCamCore

final class ProportionIntervalTests: XCTestCase {
    private func assertInterval(_ successes: Int, _ trials: Int, lower: Double, upper: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        let interval = try XCTUnwrap(ProportionInterval(successes: successes, trials: trials), file: file, line: line)
        XCTAssertEqual(interval.lower, lower, accuracy: 0.0005, file: file, line: line)
        XCTAssertEqual(interval.upper, upper, accuracy: 0.0005, file: file, line: line)
    }

    func testKnownTextbookValue() throws {
        // 50 of 100: the standard Wilson example, 0.4038 to 0.5962.
        try assertInterval(50, 100, lower: 0.4038, upper: 0.5962)
    }
    func testAllSucceedClosedForm() throws {
        // k = n gives lower = n / (n + z^2) and upper = 1.
        let z2 = ProportionInterval.z95 * ProportionInterval.z95
        try assertInterval(125, 125, lower: 125 / (125 + z2), upper: 1)
        try assertInterval(5, 5, lower: 5 / (5 + z2), upper: 1)
    }
    func testNoneSucceedClosedForm() throws {
        // k = 0 gives lower = 0 and upper = z^2 / (n + z^2).
        let z2 = ProportionInterval.z95 * ProportionInterval.z95
        try assertInterval(0, 100, lower: 0, upper: z2 / (100 + z2))
    }
    func testStaysInsideZeroToOneAndContainsTheEstimate() throws {
        for trials in [1, 2, 5, 17, 100, 1000] {
            for successes in 0...min(trials, 40) {
                let interval = try XCTUnwrap(ProportionInterval(successes: successes, trials: trials))
                let estimate = Double(successes) / Double(trials)
                XCTAssertGreaterThanOrEqual(interval.lower, 0)
                XCTAssertLessThanOrEqual(interval.upper, 1)
                XCTAssertLessThanOrEqual(interval.lower, estimate + 1e-12)
                XCTAssertGreaterThanOrEqual(interval.upper, estimate - 1e-12)
            }
        }
    }
    func testMoreTrialsGiveANarrowerInterval() throws {
        let small = try XCTUnwrap(ProportionInterval(successes: 5, trials: 5))
        let large = try XCTUnwrap(ProportionInterval(successes: 125, trials: 125))
        XCTAssertLessThan(1 - large.lower, 1 - small.lower)
    }
    func testRejectsImpossibleCounts() {
        XCTAssertNil(ProportionInterval(successes: 0, trials: 0))
        XCTAssertNil(ProportionInterval(successes: -1, trials: 10))
        XCTAssertNil(ProportionInterval(successes: 11, trials: 10))
        XCTAssertNil(ProportionInterval(successes: 1, trials: 10, z: 0))
        XCTAssertNil(ProportionInterval(successes: 1, trials: 10, z: .nan))
    }
}

import Foundation
import XCTest
@testable import ChipBarCore

final class OpenFASTProgressParsingTests: XCTestCase {
    func testParsesExactPrimaryInputTMaxOnly() {
        let input = """
        ----- SIMULATION CONTROL -----------------------------
        700.0     TMax          - Total run time [s]
        0.003125  DT            - Simulation time step [s]
        0.05      DT_Out        - Output interval [s]
        5000.0    NotTMax       - Unrelated variable
        """
        XCTAssertEqual(OpenFASTProgressParsing.tMax(in: input), 700)
        XCTAssertNil(OpenFASTProgressParsing.tMax(in: "INVALID TMax\n100 NotTMax\n"))
        XCTAssertNil(OpenFASTProgressParsing.tMax(in: "0 TMax\n"))
    }

    func testReadsOnlyCompleteDataRows() {
        let output = """
        Output from OpenFAST
        Time RotSpeed PtfmPitch
        (s) (rpm) (deg)
             0.0000  1.2 0.0
           350.0000  1.2 0.0
           475.0000  1.3 0.0
        """
        XCTAssertEqual(OpenFASTProgressParsing.latestTime(in: output + "\n"), 475)
        XCTAssertEqual(OpenFASTProgressParsing.latestTime(in: output + "\n56"), 475)
        XCTAssertNil(OpenFASTProgressParsing.latestTime(in: "Time Power\n(s) (W)\n"))
    }

    func testTruncatedTailDoesNotUseItsPartialFirstLine() {
        let tail = "9999.0000 10.0\n350.0000 12.0\n"
        XCTAssertEqual(OpenFASTProgressParsing.latestTime(in: tail, truncatedStart: true), 350)
    }

    func testProgressAndETAAreOnlyBasedOnValidSimulationTime() {
        XCTAssertEqual(OpenFASTProgressParsing.fraction(current: 350, maximum: 700), 0.5)
        XCTAssertEqual(OpenFASTProgressParsing.remainingSeconds(
            current: 350, maximum: 700, elapsed: 120), 120)
        XCTAssertNil(OpenFASTProgressParsing.fraction(current: 701, maximum: 700))
        XCTAssertNil(OpenFASTProgressParsing.fraction(current: 10, maximum: 0))
        XCTAssertNil(OpenFASTProgressParsing.fraction(current: .nan, maximum: 700))
        XCTAssertNil(OpenFASTProgressParsing.remainingSeconds(
            current: 35, maximum: 700, elapsed: 100))
    }

    func testVersion361IsBackwardCompatibleWithOldTaskPayload() throws {
        let legacy = Data("""
        {"id":"case-001","title":"OC4 Semi","state":"running","progress":0.42}
        """.utf8)
        let task = try JSONDecoder().decode(ClusterTaskReadout.self, from: legacy)
        XCTAssertEqual(task.progress, 0.42)
        XCTAssertNil(task.remainingSeconds)
        XCTAssertNil(task.currentSimTime)
        let extended = ClusterTaskReadout(id: "case-001", title: "OC4",
            state: "运行中", progress: 0.5, currentSimTime: 350,
            targetSimTime: 700, elapsedSeconds: 120, remainingSeconds: 120)
        let restored = try JSONDecoder().decode(ClusterTaskReadout.self,
            from: JSONEncoder().encode(extended))
        XCTAssertEqual(restored, extended)
    }
}

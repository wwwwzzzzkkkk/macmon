import Foundation
import Testing
@testable import ChipBarCore

struct OpenFASTProgressParsingTests {
    @Test func parsesExactPrimaryInputTMaxOnly() {
        let input = """
        ----- SIMULATION CONTROL -----------------------------
        700.0     TMax          - Total run time [s]
        0.003125  DT            - Simulation time step [s]
        0.05      DT_Out        - Output interval [s]
        5000.0    NotTMax       - Unrelated variable
        """
        #expect(OpenFASTProgressParsing.tMax(in: input) == 700)
        #expect(OpenFASTProgressParsing.tMax(in: "INVALID TMax\n100 NotTMax\n") == nil)
        #expect(OpenFASTProgressParsing.tMax(in: "0 TMax\n") == nil)
    }

    @Test func readsOnlyCompleteDataRows() {
        let output = """
        Output from OpenFAST
        Time RotSpeed PtfmPitch
        (s) (rpm) (deg)
             0.0000  1.2 0.0
           350.0000  1.2 0.0
           475.0000  1.3 0.0
        """
        #expect(OpenFASTProgressParsing.latestTime(in: output + "\n") == 475)
        #expect(OpenFASTProgressParsing.latestTime(in: output + "\n56") == 475)
        #expect(OpenFASTProgressParsing.latestTime(in: "Time Power\n(s) (W)\n") == nil)
    }

    @Test func truncatedTailDoesNotUsePartialFirstLine() {
        let tail = "9999.0000 10.0\n350.0000 12.0\n"
        #expect(OpenFASTProgressParsing.latestTime(in: tail, truncatedStart: true) == 350)
    }

    @Test func progressAndETAAreBasedOnValidSimulationTime() {
        #expect(OpenFASTProgressParsing.fraction(current: 350, maximum: 700) == 0.5)
        #expect(OpenFASTProgressParsing.remainingSeconds(
            current: 350, maximum: 700, elapsed: 120) == 120)
        #expect(OpenFASTProgressParsing.fraction(current: 701, maximum: 700) == nil)
        #expect(OpenFASTProgressParsing.fraction(current: 10, maximum: 0) == nil)
        #expect(OpenFASTProgressParsing.fraction(current: .nan, maximum: 700) == nil)
        #expect(OpenFASTProgressParsing.remainingSeconds(
            current: 35, maximum: 700, elapsed: 100) == nil)
    }

    @Test func v361WireDecodesV360TaskPayload() throws {
        let legacy = Data("""
        {"id":"case-001","title":"OC4 Semi","state":"running","progress":0.42}
        """.utf8)
        let task = try JSONDecoder().decode(ClusterTaskReadout.self, from: legacy)
        #expect(task.progress == 0.42)
        #expect(task.remainingSeconds == nil)
        #expect(task.currentSimTime == nil)

        let extended = ClusterTaskReadout(id: "case-001", title: "OC4",
            state: "运行中", progress: 0.5, currentSimTime: 350,
            targetSimTime: 700, elapsedSeconds: 120, remainingSeconds: 120)
        let restored = try JSONDecoder().decode(ClusterTaskReadout.self,
            from: JSONEncoder().encode(extended))
        #expect(restored == extended)
    }
}

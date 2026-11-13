import Foundation
import XCTest
@testable import ChipBarCore

final class ClusterTelemetryTests: XCTestCase {
    private let secret = Data(repeating: 0x31, count: 32)

    private func node(at date: Date = Date()) -> ClusterNodeReadout {
        ClusterNodeReadout(
            id: "node-a", name: "Mac mini", chip: "Apple M5 Pro",
            timestamp: date, cpu: 55, gpu: 16,
            memoryUsedGB: 12, memoryTotalGB: 24,
            chipWatts: 22, cpuTemperatureC: 60,
            tasks: [ClusterTaskReadout(
                id: "openfast-001", title: "OpenFAST case 001",
                state: "running", progress: nil)])
    }

    func testEncryptedRoundTripAndNoCommands() throws {
        let original = node()
        let framed = try ClusterSecureWire.seal(original, key: secret)
        XCTAssertGreaterThan(framed.count, 28)
        let count = framed.prefix(4).reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        XCTAssertEqual(Int(count), framed.count - 4)
        let decoded = try ClusterSecureWire.open(
            Data(framed.dropFirst(4)), key: secret)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.chip, original.chip)
        XCTAssertEqual(decoded.cpu, original.cpu)
        XCTAssertEqual(decoded.tasks, original.tasks)
        XCTAssertEqual(Int(decoded.timestamp.timeIntervalSince1970),
                       Int(original.timestamp.timeIntervalSince1970))
        XCTAssertNil(decoded.tasks.first?.progress,
                     "An externally unreported progress must remain unknown")
    }

    func testWrongKeyAndTamperingFailAuthentication() throws {
        let framed = try ClusterSecureWire.seal(node(), key: secret)
        let ciphertext = Data(framed.dropFirst(4))
        XCTAssertThrowsError(try ClusterSecureWire.open(
            ciphertext, key: Data(repeating: 0x43, count: 32)))
        var tampered = ciphertext
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        XCTAssertThrowsError(try ClusterSecureWire.open(tampered, key: secret))
    }

    func testOldSnapshotsAreRejected() throws {
        let framed = try ClusterSecureWire.seal(
            node(at: Date().addingTimeInterval(-120)), key: secret)
        XCTAssertThrowsError(try ClusterSecureWire.open(
            Data(framed.dropFirst(4)), key: secret))
    }

    func testInvalidMeasurementsAndProgressAreNotInvented() {
        let task = ClusterTaskReadout(
            id: "case", title: "simulation", state: "running",
            progress: .infinity)
        XCTAssertNil(task.progress)
        let snapshot = ClusterNodeReadout(
            id: "id", name: "Mac", chip: "M1 Pro", timestamp: Date(),
            cpu: .nan, gpu: -4, memoryUsedGB: -1,
            memoryTotalGB: 16, chipWatts: .infinity,
            cpuTemperatureC: nil, tasks: [task])
        XCTAssertNil(snapshot.cpu)
        XCTAssertEqual(snapshot.gpu, 0)
        XCTAssertNil(snapshot.memoryUsedGB)
        XCTAssertNil(snapshot.chipWatts)
    }
}

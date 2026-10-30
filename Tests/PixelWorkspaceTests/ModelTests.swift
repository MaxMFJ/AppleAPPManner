import XCTest

final class ModelTests: XCTestCase {
    func testClassifierUsesExplicitRuleBeforeHeuristics() {
        XCTAssertEqual(Classifier.department(for: "com.apple.Terminal", name: "Terminal", rules: [:]), .development)
        XCTAssertEqual(Classifier.department(for: "com.example.app", name: "Unknown", rules: ["com.example.app": .creative]), .creative)
        XCTAssertEqual(Classifier.department(for: "org.example.unknown", name: "Mystery", rules: [:]), .other)
    }

    func testProcessRecordRoundTripsWithoutInferringActivity() throws {
        let record = ProcessRecord(bundleID: "com.example.app", name: "Example", pid: 42, department: .other,
            isFrontmost: false, cpuPercent: nil, memoryBytes: nil, deviceID: "Mac", updatedAt: Date(timeIntervalSince1970: 1))
        let copy = try JSONDecoder().decode(ProcessRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(copy, record)
        XCTAssertNil(copy.cpuPercent)
        XCTAssertNil(copy.memoryBytes)
    }

    func testWireMessageUsesStableExplicitTypeEnvelope() throws {
        let record = ProcessRecord(bundleID: "x", name: "App", pid: 8, department: .other,
            isFrontmost: false, cpuPercent: nil, memoryBytes: nil, deviceID: "device", updatedAt: Date(timeIntervalSince1970: 3))
        let data = try JSONEncoder().encode(WorkspaceMessage.upsert(record))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "upsert")
        XCTAssertNotNil(json["payload"])
        XCTAssertNil(json["_0"])
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceMessage.self, from: data), .upsert(record))
    }
}

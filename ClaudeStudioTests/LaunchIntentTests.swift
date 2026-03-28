import XCTest
@testable import ClaudeStudio

final class LaunchIntentTests: XCTestCase {
    func testParsesScheduleCLIArguments() {
        let intent = LaunchIntent.fromArguments([
            "ClaudeStudio",
            "--schedule", "2F0D95B8-1D90-49B4-9C7B-6DAB4F9386A8",
            "--occurrence", "2026-03-27T06:00:00Z"
        ])

        guard let intent else {
            return XCTFail("Expected launch intent")
        }

        switch intent.mode {
        case .schedule(let id):
            XCTAssertEqual(id.uuidString.uppercased(), "2F0D95B8-1D90-49B4-9C7B-6DAB4F9386A8")
        default:
            XCTFail("Expected schedule launch mode")
        }
        XCTAssertNotNil(intent.occurrence)
    }

    func testParsesScheduleURL() {
        let url = URL(string: "claudestudio://schedule/2F0D95B8-1D90-49B4-9C7B-6DAB4F9386A8?occurrence=2026-03-27T06:00:00Z")!
        let intent = LaunchIntent.fromURL(url)

        guard let intent else {
            return XCTFail("Expected launch intent")
        }

        switch intent.mode {
        case .schedule(let id):
            XCTAssertEqual(id.uuidString.uppercased(), "2F0D95B8-1D90-49B4-9C7B-6DAB4F9386A8")
        default:
            XCTFail("Expected schedule launch mode")
        }
        XCTAssertNotNil(intent.occurrence)
    }
}

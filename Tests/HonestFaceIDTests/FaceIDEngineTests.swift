import XCTest
@testable import HonestFaceID

final class FaceIDEngineTests: XCTestCase {
    func testSmootherMovesPartWayTowardNewObservation() {
        var smoother = FaceSmoother()
        _ = smoother.add(FaceObservation(boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1), confidence: 0.5))
        let result = smoother.add(FaceObservation(boundingBox: CGRect(x: 1, y: 1, width: 1, height: 1), confidence: 1))
        XCTAssertEqual(result.boundingBox.origin.x, 0.22, accuracy: 0.001)
        XCTAssertEqual(result.confidence, 0.61, accuracy: 0.001)
    }

    func testSmootherResetDoesNotCarryAcrossSessions() {
        var smoother = FaceSmoother()
        _ = smoother.add(FaceObservation(boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1), confidence: 0.2))
        smoother.reset()

        let result = smoother.add(FaceObservation(boundingBox: CGRect(x: 1, y: 1, width: 1, height: 1), confidence: 0.9))

        XCTAssertEqual(result.boundingBox.origin.x, 1, accuracy: 0.001)
        XCTAssertEqual(result.confidence, 0.9, accuracy: 0.001)
    }
}

import XCTest
import SwiftUI
import UniformTypeIdentifiers
@testable import WifiHeatmap

final class DocumentTests: XCTestCase {

    func testNewDocumentIsEmpty() {
        let doc = WifiSurveyDocument()
        XCTAssertTrue(doc.survey.floors.isEmpty)
        XCTAssertEqual(doc.survey.name, "New Survey")
    }

    func testAddFloor() {
        let doc = WifiSurveyDocument()
        doc.addFloor(name: "Ground Floor")
        XCTAssertEqual(doc.survey.floors.count, 1)
        XCTAssertEqual(doc.survey.floors[0].name, "Ground Floor")
        XCTAssertNil(doc.survey.floors[0].calibration)
        XCTAssertTrue(doc.survey.floors[0].samples.isEmpty)
        XCTAssertFalse(doc.survey.floors[0].floorPlanFilename.isEmpty)
    }

    func testRoundTripEmptySurvey() throws {
        let doc = WifiSurveyDocument()
        doc.survey.name = "Test Survey"

        let snapshot = try doc.snapshot(contentType: .wifiSurvey)
        let wrapper = try WifiSurveyDocument.encode(snapshot: snapshot)
        let (survey2, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)

        XCTAssertEqual(survey2.name, "Test Survey")
        XCTAssertTrue(survey2.floors.isEmpty)
    }

    func testRoundTripWithFloorAndSamples() throws {
        let doc = WifiSurveyDocument()
        doc.addFloor(name: "Upstairs")
        let floorID = doc.survey.floors[0].id

        let sample = WifiSample(
            id: UUID(),
            position: CGPoint(x: 50, y: 75),
            timestamp: Date(timeIntervalSince1970: 1000),
            ssid: "Net",
            bssid: "00:11:22:33:44:55",
            rssi: -70,
            noise: -95,
            band: .ghz2_4
        )
        doc.survey.floors[0].samples = [sample]

        let snapshot = try doc.snapshot(contentType: .wifiSurvey)
        let wrapper = try WifiSurveyDocument.encode(snapshot: snapshot)
        let (survey2, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)

        XCTAssertEqual(survey2.floors.count, 1)
        XCTAssertEqual(survey2.floors[0].id, floorID)
        XCTAssertEqual(survey2.floors[0].samples.count, 1)
        XCTAssertEqual(survey2.floors[0].samples[0].rssi, -70)
        XCTAssertEqual(survey2.floors[0].samples[0].band, .ghz2_4)
    }

    func testFloorOrderPreserved() throws {
        let doc = WifiSurveyDocument()
        doc.addFloor(name: "Ground")
        doc.addFloor(name: "First")
        doc.addFloor(name: "Second")
        let ids = doc.survey.floors.map(\.id)

        let snapshot = try doc.snapshot(contentType: .wifiSurvey)
        let wrapper = try WifiSurveyDocument.encode(snapshot: snapshot)
        let (survey2, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)

        XCTAssertEqual(survey2.floors.map(\.id), ids)
        XCTAssertEqual(survey2.floors.map(\.name), ["Ground", "First", "Second"])
    }
}

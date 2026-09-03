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
        XCTAssertTrue(doc.survey.floors[0].points.isEmpty)
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

    func testEncodedManifestDeclaresCurrentV3Schema() throws {
        let document = WifiSurveyDocument()
        let wrapper = try WifiSurveyDocument.encode(
            snapshot: try document.snapshot(contentType: .wifiSurvey)
        )
        let manifestData = try XCTUnwrap(
            wrapper.fileWrappers?["manifest.json"]?.regularFileContents
        )
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )

        XCTAssertEqual(manifest["schemaVersion"] as? Int, 3)
    }

    func testRoundTripWithFloorAndPoint() throws {
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
        let point = SurveyPoint(
            id: sample.id,
            position: sample.position,
            startedAt: sample.timestamp,
            completedAt: sample.timestamp,
            scanCacheUpdated: false,
            snapshotChanged: nil,
            attemptCount: 1,
            readings: [WifiNetworkReading(
                ssid: sample.ssid,
                bssid: sample.bssid,
                rssi: sample.rssi,
                noise: sample.noise,
                band: sample.band,
                channel: sample.channel
            )]
        )
        doc.survey.floors[0].points = [point]

        let snapshot = try doc.snapshot(contentType: .wifiSurvey)
        let wrapper = try WifiSurveyDocument.encode(snapshot: snapshot)
        let (survey2, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)

        XCTAssertEqual(survey2.floors.count, 1)
        XCTAssertEqual(survey2.floors[0].id, floorID)
        XCTAssertEqual(survey2.floors[0].points, [point])
    }

    func testUndoAndRedoTreatEveryReadingInCaptureAsOneAtomicChange() throws {
        let document = WifiSurveyDocument()
        document.addFloor(name: "Atomic Floor")
        let floorID = try XCTUnwrap(document.survey.floors.first?.id)
        let capture = SurveyPoint(
            id: UUID(),
            position: CGPoint(x: 13, y: 21),
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 101),
            scanCacheUpdated: true,
            snapshotChanged: true,
            attemptCount: 1,
            readings: [
                WifiNetworkReading(ssid: "Home", bssid: "2g", rssi: -50, noise: -90, band: .ghz2_4, channel: 6),
                WifiNetworkReading(ssid: "Home", bssid: "5g", rssi: -55, noise: -92, band: .ghz5, channel: 44),
                WifiNetworkReading(ssid: "Guest", bssid: "6g", rssi: -65, noise: -94, band: .ghz6, channel: 37)
            ]
        )
        let undoManager = UndoManager()
        document.survey.floors[0].points.append(capture)
        PointUndo.registerUndoForInsertion(
            capture,
            at: 0,
            floorID: floorID,
            document: document,
            undoManager: undoManager,
            actionName: "Log Capture"
        )

        undoManager.undo()
        XCTAssertTrue(document.survey.floors[0].points.isEmpty)

        undoManager.redo()
        XCTAssertEqual(document.survey.floors[0].points, [capture])

        undoManager.undo()
        XCTAssertTrue(document.survey.floors[0].points.isEmpty)
    }

    func testClearAllCapturesOnlyClearsTargetFloorAndUndoRestoresAll() throws {
        let document = WifiSurveyDocument()
        document.addFloor(name: "Active Floor")
        document.addFloor(name: "Other Floor")
        let activeFloorID = try XCTUnwrap(document.survey.floors.first?.id)
        let first = capture(id: UUID(), x: 10)
        let second = capture(id: UUID(), x: 20)
        let otherFloorCapture = capture(id: UUID(), x: 30)
        document.survey.floors[0].points = [first, second]
        document.survey.floors[1].points = [otherFloorCapture]
        let undoManager = UndoManager()

        PointUndo.clearAllPoints(
            floorID: activeFloorID,
            document: document,
            undoManager: undoManager
        )

        XCTAssertTrue(document.survey.floors[0].points.isEmpty)
        XCTAssertEqual(document.survey.floors[1].points, [otherFloorCapture])

        undoManager.undo()
        XCTAssertEqual(document.survey.floors[0].points, [first, second])
        XCTAssertEqual(document.survey.floors[1].points, [otherFloorCapture])

        undoManager.redo()
        XCTAssertTrue(document.survey.floors[0].points.isEmpty)
        XCTAssertEqual(document.survey.floors[1].points, [otherFloorCapture])
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

    func testViewSettingsRoundTrip() throws {
        let doc = WifiSurveyDocument()
        doc.survey.viewSettings = SurveyViewSettings(
            selectedSSID: "Home WiFi",
            selectedBSSID: "aa:bb:cc:dd:ee:ff",
            activeBand: .ghz6,
            showHeatmap: true,
            showContours: true,
            contourSmoothingMeters: 1.75,
            metric: .snr,
            colorScheme: .colorblindSafe,
            fadeRadius: 12.5,
            rssiRange: HeatmapValueRange(lowerBound: -85, upperBound: -25),
            snrRange: HeatmapValueRange(lowerBound: 5, upperBound: 35)
        )

        let snapshot = try doc.snapshot(contentType: .wifiSurvey)
        let wrapper = try WifiSurveyDocument.encode(snapshot: snapshot)
        let (survey, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)

        XCTAssertEqual(survey.viewSettings, doc.survey.viewSettings)
        XCTAssertTrue(survey.viewSettings.showContours)
        XCTAssertEqual(survey.viewSettings.contourSmoothingMeters, 1.75)
    }

    func testLegacyDocumentWithoutViewSettingsUsesStandardSettings() throws {
        let manifestData = """
        {
          "name": "Legacy Survey",
          "createdAt": "1970-01-01T00:00:00Z",
          "floorIDs": []
        }
        """.data(using: .utf8)!
        let manifest = FileWrapper(regularFileWithContents: manifestData)
        manifest.preferredFilename = "manifest.json"
        let floors = FileWrapper(directoryWithFileWrappers: [:])
        floors.preferredFilename = "floors"
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": manifest,
            "floors": floors
        ])

        let (survey, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)

        XCTAssertEqual(survey.viewSettings, .standard)
    }

    func testDocumentWithOlderViewSettingsUsesDefaultHeatmapRanges() throws {
        let manifestData = """
        {
          "name": "Previous Survey",
          "createdAt": "1970-01-01T00:00:00Z",
          "floorIDs": [],
          "viewSettings": {
            "activeBand": "ghz5",
            "showHeatmap": true,
            "metric": "rssi",
            "colorScheme": "classic",
            "fadeRadius": 5
          }
        }
        """.data(using: .utf8)!
        let manifest = FileWrapper(regularFileWithContents: manifestData)
        manifest.preferredFilename = "manifest.json"
        let floors = FileWrapper(directoryWithFileWrappers: [:])
        floors.preferredFilename = "floors"
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": manifest,
            "floors": floors
        ])

        let (survey, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)

        XCTAssertEqual(survey.viewSettings.rssiRange, HeatmapValueRange(lowerBound: -90, upperBound: -20))
        XCTAssertEqual(survey.viewSettings.snrRange, HeatmapValueRange(lowerBound: 0, upperBound: 40))
        XCTAssertFalse(survey.viewSettings.showContours)
        XCTAssertEqual(survey.viewSettings.contourSmoothingMeters, 1.0)
    }

    func testLegacySingularSelectionsDecodeAsSingletonSetsAndAllBandsTracked() throws {
        let data = """
        {
          "selectedSSID": "Home",
          "selectedBSSID": "aa:bb",
          "activeBand": "ghz5",
          "showHeatmap": false,
          "metric": "rssi",
          "colorScheme": "classic",
          "fadeRadius": 5
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(SurveyViewSettings.self, from: data)

        XCTAssertEqual(settings.selectedSSIDs, ["Home"])
        XCTAssertEqual(settings.selectedBSSIDs, ["aa:bb"])
        XCTAssertEqual(settings.trackedBands, Set(WiFiBand.allCases))
    }

    func testMultiSelectionsAndTrackedBandsRoundTrip() throws {
        let settings = SurveyViewSettings(
            selectedSSIDs: ["Home", "Office"],
            selectedBSSIDs: ["home-ap", "office-ap"],
            trackedBands: [.ghz2_4, .ghz5],
            activeBand: .ghz5,
            showHeatmap: true,
            metric: .rssi,
            colorScheme: .classic,
            fadeRadius: 6
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SurveyViewSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testLegacyMigrationCreatesBackupBeforePublishingSurvey() throws {
        let floorID = UUID()
        let legacyWrapper = try legacyV2Wrapper(floorID: floorID)
        let sourceURL = try writePackage(legacyWrapper, named: "Old Survey.wifiheatmap")
        let document = try WifiSurveyDocument(fileWrapper: legacyWrapper)
        var observedBackupURL: URL?

        XCTAssertTrue(document.requiresMigration)
        XCTAssertTrue(document.survey.floors.isEmpty)

        let backupURL = try document.completePendingMigration(
            sourceURL: sourceURL,
            now: Date(timeIntervalSince1970: 0)
        ) { source, destination in
            XCTAssertTrue(document.survey.floors.isEmpty)
            try FileManager.default.copyItem(at: source, to: destination)
            observedBackupURL = destination
        }

        XCTAssertEqual(backupURL, observedBackupURL)
        XCTAssertEqual(backupURL?.lastPathComponent, "Old Survey.pre-v3-backup-1970-01-01-073000.wifiheatmap")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(backupURL).path))
        XCTAssertFalse(document.requiresMigration)
        XCTAssertEqual(document.survey.floors.map(\.id), [floorID])
        XCTAssertEqual(
            document.migrationSuccessMessage,
            "Survey updated to the new point format. Backup saved as Old Survey.pre-v3-backup-1970-01-01-073000.wifiheatmap."
        )
    }

    func testBackupFailureLeavesLegacyMigrationPendingAndReportsError() throws {
        let legacyWrapper = try legacyV2Wrapper(floorID: UUID())
        let sourceURL = try writePackage(legacyWrapper, named: "Unmigrated.wifiheatmap")
        let document = try WifiSurveyDocument(fileWrapper: legacyWrapper)

        XCTAssertThrowsError(
            try document.completePendingMigration(sourceURL: sourceURL) { _, _ in
                throw CocoaError(.fileWriteNoPermission)
            }
        )

        XCTAssertTrue(document.requiresMigration)
        XCTAssertTrue(document.survey.floors.isEmpty)
        XCTAssertNotNil(document.migrationFailureMessage)
        XCTAssertThrowsError(try document.snapshot(contentType: .wifiSurvey))
    }

    func testV3DocumentPublishesImmediatelyWithoutCreatingBackup() throws {
        let original = WifiSurveyDocument()
        original.survey.name = "Current Survey"
        let wrapper = try WifiSurveyDocument.encode(
            snapshot: try original.snapshot(contentType: .wifiSurvey)
        )
        let document = try WifiSurveyDocument(fileWrapper: wrapper)
        var backupCalled = false

        let backupURL = try document.completePendingMigration(
            sourceURL: URL(fileURLWithPath: "/unused/current.wifiheatmap")
        ) { _, _ in
            backupCalled = true
        }

        XCTAssertFalse(document.requiresMigration)
        XCTAssertEqual(document.survey.name, "Current Survey")
        XCTAssertNil(backupURL)
        XCTAssertFalse(backupCalled)
    }

    func testLegacyMigrationUsesNumberedBackupNameWhenTimestampNameExists() throws {
        let legacyWrapper = try legacyV2Wrapper(floorID: UUID())
        let sourceURL = try writePackage(legacyWrapper, named: "Repeated.wifiheatmap")
        let existingURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("Repeated.pre-v3-backup-1970-01-01-073000.wifiheatmap")
        try FileManager.default.createDirectory(at: existingURL, withIntermediateDirectories: false)
        let document = try WifiSurveyDocument(fileWrapper: legacyWrapper)

        let backupURL = try document.completePendingMigration(
            sourceURL: sourceURL,
            now: Date(timeIntervalSince1970: 0)
        ) { source, destination in
            try FileManager.default.copyItem(at: source, to: destination)
        }

        XCTAssertEqual(
            backupURL?.lastPathComponent,
            "Repeated.pre-v3-backup-1970-01-01-073000-2.wifiheatmap"
        )
    }

    private func capture(id: UUID, x: CGFloat) -> SurveyPoint {
        SurveyPoint(
            id: id,
            position: CGPoint(x: x, y: x),
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 101),
            scanCacheUpdated: true,
            snapshotChanged: true,
            attemptCount: 1,
            readings: [
                WifiNetworkReading(
                    ssid: "Home",
                    bssid: id.uuidString,
                    rssi: -50,
                    noise: -90,
                    band: .ghz5,
                    channel: 44
                )
            ]
        )
    }

    private func legacyV2Wrapper(floorID: UUID) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let floor = LegacyV2Floor(
            id: floorID,
            name: "Legacy Floor",
            floorPlanFilename: "\(floorID.uuidString).png",
            calibration: nil,
            captures: [capture(id: UUID(), x: 12)]
        )
        let manifestData = """
        {
          "schemaVersion": 2,
          "name": "Legacy Survey",
          "createdAt": "1970-01-01T00:00:00Z",
          "floorIDs": ["\(floorID.uuidString)"]
        }
        """.data(using: .utf8)!
        let manifest = FileWrapper(regularFileWithContents: manifestData)
        manifest.preferredFilename = "manifest.json"
        let floorJSON = FileWrapper(regularFileWithContents: try encoder.encode(floor))
        floorJSON.preferredFilename = "\(floorID.uuidString).json"
        let floors = FileWrapper(directoryWithFileWrappers: [
            "\(floorID.uuidString).json": floorJSON
        ])
        floors.preferredFilename = "floors"
        return FileWrapper(directoryWithFileWrappers: [
            "manifest.json": manifest,
            "floors": floors
        ])
    }

    private func writePackage(_ wrapper: FileWrapper, named filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(filename, isDirectory: true)
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }
}

private struct LegacyV2Floor: Encodable {
    var id: UUID
    var name: String
    var floorPlanFilename: String
    var calibration: Calibration?
    var captures: [SurveyPoint]
}

import XCTest
import SwiftUI
import UniformTypeIdentifiers
@testable import WifiHeatmap

final class DocumentTests: XCTestCase {

    func testAppLaunchPolicyRequestsAnUntitledDocumentByDefault() {
        XCTAssertTrue(BlankDocumentLaunchPolicy.opensUntitledDocumentByDefault)
    }

    func testExistingDocumentSavesInPlaceWithoutRequestingSaveAsDestination() {
        let existingURL = URL(fileURLWithPath: "/tmp/Existing.wifiheatmap")
        var saveAsWasRequested = false

        let destination = DocumentSaveDestination.resolve(existingFileURL: existingURL) {
            saveAsWasRequested = true
            return URL(fileURLWithPath: "/tmp/Unexpected.wifiheatmap")
        }

        XCTAssertEqual(destination, existingURL)
        XCTAssertFalse(saveAsWasRequested)
    }

    func testUntitledDocumentRequestsSaveAsDestination() {
        let chosenURL = URL(fileURLWithPath: "/tmp/Chosen.wifiheatmap")
        var saveAsWasRequested = false

        let destination = DocumentSaveDestination.resolve(existingFileURL: nil) {
            saveAsWasRequested = true
            return chosenURL
        }

        XCTAssertEqual(destination, chosenURL)
        XCTAssertTrue(saveAsWasRequested)
    }

    func testExactDirtyCheckFindsPersistedChangeWithoutChangeNotification() throws {
        let document = WifiSurveyDocument()
        let saved = try document.snapshot(contentType: .wifiSurvey)
        var changed = saved
        changed.survey.name = "Changed Survey"
        var state = PersistedDocumentDirtyState(savedSnapshot: saved)

        XCTAssertFalse(state.possiblyDirty)
        XCTAssertTrue(state.reconcile(currentSnapshot: changed))
        XCTAssertTrue(state.possiblyDirty)
    }

    func testExactDirtyCheckClearsPossibleChangeAfterRevertingToSavedSnapshot() throws {
        let document = WifiSurveyDocument()
        let saved = try document.snapshot(contentType: .wifiSurvey)
        var state = PersistedDocumentDirtyState(savedSnapshot: saved)

        state.notePossibleChange()

        XCTAssertTrue(state.possiblyDirty)
        XCTAssertFalse(state.reconcile(currentSnapshot: saved))
        XCTAssertFalse(state.possiblyDirty)
    }

    func testSavedSnapshotComparisonIncludesFloorPlanImageData() throws {
        let document = WifiSurveyDocument()
        let saved = try document.snapshot(contentType: .wifiSurvey)
        var changed = saved
        changed.imageCache["floor.png"] = Data([1, 2, 3])
        var state = PersistedDocumentDirtyState(savedSnapshot: saved)

        XCTAssertTrue(state.reconcile(currentSnapshot: changed))

        state.markSaved(changed)

        XCTAssertFalse(state.reconcile(currentSnapshot: changed))
    }

    func testDirtyWindowTitleAppendsOneAsteriskAndRestoresCleanTitle() {
        XCTAssertEqual(DirtyWindowTitle.formatted("Office Survey", isDirty: true), "Office Survey *")
        XCTAssertEqual(DirtyWindowTitle.formatted("Office Survey *", isDirty: true), "Office Survey *")
        XCTAssertEqual(DirtyWindowTitle.formatted("Office Survey *", isDirty: false), "Office Survey")
    }

    @MainActor
    func testFreshBlankDocumentWindowStartsClean() {
        let document = WifiSurveyDocument()
        let coordinator = DocumentCloseCoordinator(document: document, originalFileURL: nil)
        let window = NSWindow()
        window.title = "Untitled"

        coordinator.attach(to: window)

        XCTAssertFalse(coordinator.isDirty)
        XCTAssertFalse(window.isDocumentEdited)
        XCTAssertEqual(window.title, "Untitled")
    }

    @MainActor
    func testNormalDocumentSaveClearsCustomDirtyStateAndTitle() {
        let document = WifiSurveyDocument()
        let coordinator = DocumentCloseCoordinator(document: document, originalFileURL: nil)
        let window = NSWindow()
        window.title = "Untitled"
        coordinator.attach(to: window)

        document.survey.name = "Changed Survey"

        XCTAssertTrue(coordinator.isDirty)
        XCTAssertTrue(window.isDocumentEdited)
        XCTAssertEqual(window.title, "Untitled *")

        // DocumentGroup/NSDocument clears this flag after a successful normal
        // Save or Save As. The custom title tracker must adopt that clean state.
        window.isDocumentEdited = false
        coordinator.windowDidUpdate(window)

        XCTAssertFalse(coordinator.isDirty)
        XCTAssertFalse(window.isDocumentEdited)
        XCTAssertEqual(window.title, "Untitled")
    }

    func testScanDrivenDisplayFallbackDoesNotWritePersistedSelections() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WifiHeatmap/Views/FloorDetailView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("document.survey.viewSettings.displaySSID = resolvedSSID"))
        XCTAssertFalse(source.contains("document.survey.viewSettings.displayBSSIDs = resolvedBSSIDs"))
        XCTAssertTrue(source.contains("displaySSID: displaySSIDBinding"))
    }

    func testCleanDocumentClosesWithoutPromptingOrSaving() {
        var prompted = false
        var saved = false

        let shouldClose = UnsavedClosePolicy.shouldClose(
            isDirty: false,
            choose: {
                prompted = true
                return .cancel
            },
            save: {
                saved = true
                return false
            }
        )

        XCTAssertTrue(shouldClose)
        XCTAssertFalse(prompted)
        XCTAssertFalse(saved)
    }

    func testDirtyDocumentClosesAfterSuccessfulSaveAs() {
        var saved = false

        let shouldClose = UnsavedClosePolicy.shouldClose(
            isDirty: true,
            choose: { .save },
            save: {
                saved = true
                return true
            }
        )

        XCTAssertTrue(shouldClose)
        XCTAssertTrue(saved)
    }

    func testDirtyDocumentStaysOpenWhenSaveAsIsCancelledOrFails() {
        let shouldClose = UnsavedClosePolicy.shouldClose(
            isDirty: true,
            choose: { .save },
            save: { false }
        )

        XCTAssertFalse(shouldClose)
    }

    func testDirtyDocumentCanBeDiscardedButCancelKeepsItOpen() {
        XCTAssertTrue(UnsavedClosePolicy.shouldClose(
            isDirty: true,
            choose: { .discard },
            save: { XCTFail("Discard must not save"); return false }
        ))
        XCTAssertFalse(UnsavedClosePolicy.shouldClose(
            isDirty: true,
            choose: { .cancel },
            save: { XCTFail("Cancel must not save"); return false }
        ))
    }

    func testOpeningAnotherDocumentUsesTheUnsavedChangesDecisionBeforeReplacingCurrentWindow() {
        var choices = 0
        var saves = 0

        XCTAssertTrue(DocumentReplacementPolicy.shouldProceed(
            isDirty: false,
            choose: {
                choices += 1
                return .cancel
            },
            save: {
                saves += 1
                return false
            }
        ))
        XCTAssertEqual(choices, 0)
        XCTAssertEqual(saves, 0)

        XCTAssertTrue(DocumentReplacementPolicy.shouldProceed(
            isDirty: true,
            choose: { .discard },
            save: { XCTFail("Discard must not save"); return false }
        ))
        XCTAssertFalse(DocumentReplacementPolicy.shouldProceed(
            isDirty: true,
            choose: { .cancel },
            save: { XCTFail("Cancel must not save"); return false }
        ))
        XCTAssertFalse(DocumentReplacementPolicy.shouldProceed(
            isDirty: true,
            choose: { .save },
            save: { false }
        ))
        XCTAssertTrue(DocumentReplacementPolicy.shouldProceed(
            isDirty: true,
            choose: { .save },
            save: { true }
        ))
    }

    func testNewDocumentIsEmpty() {
        let doc = WifiSurveyDocument()
        XCTAssertTrue(doc.survey.floors.isEmpty)
        XCTAssertEqual(doc.survey.name, "New Survey")
    }

    func testNewDocumentStartsWithOneActiveDefaultScanEvenWithoutFloors() throws {
        let document = WifiSurveyDocument()

        XCTAssertTrue(document.survey.floors.isEmpty)
        XCTAssertEqual(document.survey.scanSets.count, 1)
        let defaultScan = try XCTUnwrap(document.survey.scanSets.first)
        XCTAssertEqual(defaultScan.name, "Scan 1")
        XCTAssertEqual(document.survey.activeScanID, defaultScan.id)
        XCTAssertTrue(defaultScan.floors.isEmpty)

        document.addFloor(name: "Ground")
        document.addFloor(name: "First")

        XCTAssertEqual(
            Set(try XCTUnwrap(document.survey.scanSets.first).floors.map(\.floorID)),
            Set(document.survey.floors.map(\.id))
        )
        XCTAssertTrue(document.points(for: document.survey.floors[0].id, scanID: defaultScan.id).isEmpty)

        let createdAt = Date(timeIntervalSince1970: 1_000)
        let secondScanID = document.addScan(now: createdAt.addingTimeInterval(60))

        XCTAssertEqual(document.survey.activeScanID, secondScanID)
        XCTAssertEqual(document.survey.scanSets.map(\.name), ["Scan 1", "Scan 2"])
    }

    func testRenameScanTrimsAndPersistsNameWithoutChangingPoints() throws {
        let document = WifiSurveyDocument()
        document.addFloor(name: "Ground")
        let floorID = try XCTUnwrap(document.survey.floors.first?.id)
        let scanID = try XCTUnwrap(document.survey.activeScanID)
        let point = capture(id: UUID(), x: 18)
        XCTAssertTrue(document.replacePoints([point], for: floorID, scanID: scanID))

        XCTAssertTrue(document.renameScan(id: scanID, to: "  Morning walkthrough  "))

        XCTAssertEqual(document.survey.scanSets.first?.id, scanID)
        XCTAssertEqual(document.survey.scanSets.first?.name, "Morning walkthrough")
        XCTAssertEqual(document.points(for: floorID, scanID: scanID), [point])

        let wrapper = try WifiSurveyDocument.encode(
            snapshot: try document.snapshot(contentType: .wifiSurvey)
        )
        let (decoded, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)
        XCTAssertEqual(decoded.scanSets.first?.name, "Morning walkthrough")
        XCTAssertEqual(decoded.scanSets.first?.points(for: floorID), [point])
    }

    func testRenameScanRejectsBlankName() throws {
        let document = WifiSurveyDocument()
        document.addFloor(name: "Ground")
        let scanID = try XCTUnwrap(document.survey.activeScanID)

        XCTAssertFalse(document.renameScan(id: scanID, to: "   \n  "))
        XCTAssertEqual(document.survey.scanSets.first?.name, "Scan 1")
    }

    func testAddNamedScanTrimsAndPersistsItsName() throws {
        let document = WifiSurveyDocument()
        document.addFloor(name: "Ground")

        let scanID = try XCTUnwrap(document.addScan(
            name: "  Pre-install survey  ",
            now: Date(timeIntervalSince1970: 1_000)
        ))

        XCTAssertEqual(document.survey.activeScanID, scanID)
        XCTAssertEqual(document.survey.scanSets.map(\.name), ["Scan 1", "Pre-install survey"])

        let wrapper = try WifiSurveyDocument.encode(
            snapshot: try document.snapshot(contentType: .wifiSurvey)
        )
        let (decoded, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)
        XCTAssertEqual(decoded.scanSets.map(\.name), ["Scan 1", "Pre-install survey"])
    }

    func testAddNamedScanRejectsBlankName() {
        let document = WifiSurveyDocument()
        let originalScans = document.survey.scanSets
        let originalActiveScanID = document.survey.activeScanID

        XCTAssertNil(document.addScan(name: "  \n  "))
        XCTAssertEqual(document.survey.scanSets, originalScans)
        XCTAssertEqual(document.survey.activeScanID, originalActiveScanID)
    }

    func testDeleteActiveScanSelectsTheScanThatMovesIntoItsRow() throws {
        let document = WifiSurveyDocument()
        document.addFloor(name: "Ground")
        let firstID = try XCTUnwrap(document.survey.activeScanID)
        let secondID = document.addScan(now: Date(timeIntervalSince1970: 2_000))
        let thirdID = document.addScan(now: Date(timeIntervalSince1970: 3_000))
        document.survey.activeScanID = secondID

        XCTAssertTrue(document.deleteScan(id: secondID))

        XCTAssertEqual(document.survey.scanSets.map(\.id), [firstID, thirdID])
        XCTAssertEqual(document.survey.activeScanID, thirdID)
    }

    func testDeleteLastActiveScanSelectsItsPredecessor() {
        let document = WifiSurveyDocument()
        let firstID = document.survey.activeScanID!
        let secondID = document.addScan(now: Date(timeIntervalSince1970: 2_000))

        XCTAssertTrue(document.deleteScan(id: secondID))

        XCTAssertEqual(document.survey.scanSets.map(\.id), [firstID])
        XCTAssertEqual(document.survey.activeScanID, firstID)
    }

    func testDeleteOnlyScanReturnsDocumentToNoScanState() {
        let document = WifiSurveyDocument()
        let scanID = document.survey.activeScanID!

        XCTAssertTrue(document.deleteScan(id: scanID))

        XCTAssertTrue(document.survey.scanSets.isEmpty)
        XCTAssertNil(document.survey.activeScanID)
    }

    func testDeletingUnknownScanDoesNotChangeDocument() {
        let document = WifiSurveyDocument()
        let scanID = document.survey.activeScanID!

        XCTAssertFalse(document.deleteScan(id: UUID()))

        XCTAssertEqual(document.survey.scanSets.map(\.id), [scanID])
        XCTAssertEqual(document.survey.activeScanID, scanID)
    }

    func testV4RoundTripKeepsTwoScanSetsIsolatedAndFloorFilesPointFree() throws {
        let document = WifiSurveyDocument()
        document.addFloor(name: "Ground")
        let floorID = try XCTUnwrap(document.survey.floors.first?.id)
        let morningID = try XCTUnwrap(document.survey.activeScanID)
        let morningPoint = capture(id: UUID(), x: 10)
        XCTAssertTrue(document.replacePoints([morningPoint], for: floorID, scanID: morningID))

        let eveningID = document.addScan(now: Date(timeIntervalSince1970: 2_000))
        let eveningPoint = capture(id: UUID(), x: 20)
        XCTAssertTrue(document.replacePoints([eveningPoint], for: floorID, scanID: eveningID))

        let wrapper = try WifiSurveyDocument.encode(
            snapshot: try document.snapshot(contentType: .wifiSurvey)
        )
        let manifestData = try XCTUnwrap(
            wrapper.fileWrappers?["manifest.json"]?.regularFileContents
        )
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        let floorData = try XCTUnwrap(
            wrapper.fileWrappers?["floors"]?.fileWrappers?["\(floorID.uuidString).json"]?.regularFileContents
        )
        let floorJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: floorData) as? [String: Any]
        )

        XCTAssertEqual(manifest["schemaVersion"] as? Int, 4)
        XCTAssertEqual((manifest["scanIDs"] as? [String])?.count, 2)
        XCTAssertEqual(manifest["activeScanID"] as? String, eveningID.uuidString)
        XCTAssertNil(floorJSON["points"])
        XCTAssertNotNil(wrapper.fileWrappers?["scans"]?.fileWrappers?["\(morningID.uuidString).json"])
        XCTAssertNotNil(wrapper.fileWrappers?["scans"]?.fileWrappers?["\(eveningID.uuidString).json"])

        let (decoded, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)
        XCTAssertEqual(decoded.scanSets.count, 2)
        XCTAssertEqual(decoded.activeScanID, eveningID)
        XCTAssertEqual(decoded.scanSets[0].points(for: floorID), [morningPoint])
        XCTAssertEqual(decoded.scanSets[1].points(for: floorID), [eveningPoint])
    }

    func testV3DocumentMigratesFloorPointsIntoScanOneOnlyAfterBackup() throws {
        let floorID = UUID()
        let point = capture(id: UUID(), x: 12)
        let legacyWrapper = try legacyV3Wrapper(floorID: floorID, points: [point])
        let sourceURL = try writePackage(legacyWrapper, named: "Single Scan.wifiheatmap")
        let document = try WifiSurveyDocument(fileWrapper: legacyWrapper)

        XCTAssertTrue(document.requiresMigration)
        XCTAssertTrue(document.survey.scanSets.isEmpty)

        let backupURL = try document.completePendingMigration(
            sourceURL: sourceURL,
            now: Date(timeIntervalSince1970: 0)
        ) { source, destination in
            XCTAssertTrue(document.survey.scanSets.isEmpty)
            try FileManager.default.copyItem(at: source, to: destination)
        }

        let scan = try XCTUnwrap(document.survey.scanSets.first)
        XCTAssertEqual(scan.name, "Scan 1")
        XCTAssertEqual(document.survey.activeScanID, scan.id)
        XCTAssertEqual(scan.points(for: floorID), [point])
        XCTAssertTrue(document.survey.floors[0].points.isEmpty)
        XCTAssertEqual(
            backupURL?.lastPathComponent,
            "Single Scan.pre-v4-backup-1970-01-01-073000.wifiheatmap"
        )
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

    func testEncodedManifestDeclaresCurrentV4Schema() throws {
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

        XCTAssertEqual(manifest["schemaVersion"] as? Int, 4)
    }

    func testRoundTripWithFloorAndPoint() throws {
        let doc = WifiSurveyDocument()
        doc.addFloor(name: "Upstairs")
        let floorID = doc.survey.floors[0].id
        let scanID = try XCTUnwrap(doc.survey.activeScanID)

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
        XCTAssertTrue(doc.replacePoints([point], for: floorID, scanID: scanID))

        let snapshot = try doc.snapshot(contentType: .wifiSurvey)
        let wrapper = try WifiSurveyDocument.encode(snapshot: snapshot)
        let (survey2, _) = try WifiSurveyDocument.decode(fileWrapper: wrapper)

        XCTAssertEqual(survey2.floors.count, 1)
        XCTAssertEqual(survey2.floors[0].id, floorID)
        XCTAssertEqual(survey2.scanSets.first?.points(for: floorID), [point])
    }

    func testUndoAndRedoTreatEveryReadingInCaptureAsOneAtomicChange() throws {
        let document = WifiSurveyDocument()
        document.addFloor(name: "Atomic Floor")
        let floorID = try XCTUnwrap(document.survey.floors.first?.id)
        let scanID = document.addScan(now: Date(timeIntervalSince1970: 90))
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
        XCTAssertTrue(document.replacePoints([capture], for: floorID, scanID: scanID))
        PointUndo.registerUndoForInsertion(
            capture,
            at: 0,
            floorID: floorID,
            scanID: scanID,
            document: document,
            undoManager: undoManager,
            actionName: "Log Capture"
        )

        undoManager.undo()
        XCTAssertTrue(document.points(for: floorID, scanID: scanID).isEmpty)

        undoManager.redo()
        XCTAssertEqual(document.points(for: floorID, scanID: scanID), [capture])

        undoManager.undo()
        XCTAssertTrue(document.points(for: floorID, scanID: scanID).isEmpty)
    }

    func testClearAllCapturesOnlyClearsTargetFloorAndUndoRestoresAll() throws {
        let document = WifiSurveyDocument()
        document.addFloor(name: "Active Floor")
        document.addFloor(name: "Other Floor")
        let activeFloorID = try XCTUnwrap(document.survey.floors.first?.id)
        let otherFloorID = try XCTUnwrap(document.survey.floors.last?.id)
        let scanID = document.addScan(now: Date(timeIntervalSince1970: 90))
        let first = capture(id: UUID(), x: 10)
        let second = capture(id: UUID(), x: 20)
        let otherFloorCapture = capture(id: UUID(), x: 30)
        XCTAssertTrue(document.replacePoints([first, second], for: activeFloorID, scanID: scanID))
        XCTAssertTrue(document.replacePoints([otherFloorCapture], for: otherFloorID, scanID: scanID))
        let undoManager = UndoManager()

        PointUndo.clearAllPoints(
            floorID: activeFloorID,
            scanID: scanID,
            document: document,
            undoManager: undoManager
        )

        XCTAssertTrue(document.points(for: activeFloorID, scanID: scanID).isEmpty)
        XCTAssertEqual(document.points(for: otherFloorID, scanID: scanID), [otherFloorCapture])

        undoManager.undo()
        XCTAssertEqual(document.points(for: activeFloorID, scanID: scanID), [first, second])
        XCTAssertEqual(document.points(for: otherFloorID, scanID: scanID), [otherFloorCapture])

        undoManager.redo()
        XCTAssertTrue(document.points(for: activeFloorID, scanID: scanID).isEmpty)
        XCTAssertEqual(document.points(for: otherFloorID, scanID: scanID), [otherFloorCapture])
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
            requiredSSIDs: ["Home WiFi", "Office"],
            requiredBSSIDs: ["aa:bb:cc:dd:ee:ff"],
            trackedBands: [.ghz2_4, .ghz6],
            displayBand: .ghz6,
            displaySSID: "Home WiFi",
            displayBSSIDs: ["aa:bb:cc:dd:ee:ff", "11:22:33:44:55:66"],
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

    func testViewSettingsEncodeOnlyCanonicalScanAndDisplaySelectionKeys() throws {
        let settings = SurveyViewSettings(
            requiredSSIDs: ["Home"],
            requiredBSSIDs: ["required-ap"],
            trackedBands: [.ghz5],
            displayBand: .ghz5,
            displaySSID: "Home",
            displayBSSIDs: ["display-ap"],
            showHeatmap: true,
            metric: .rssi,
            colorScheme: .classic,
            fadeRadius: 6
        )

        let data = try JSONEncoder().encode(settings)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["requiredSSIDs"])
        XCTAssertNotNil(json["requiredBSSIDs"])
        XCTAssertNotNil(json["displayBand"])
        XCTAssertNotNil(json["displaySSID"])
        XCTAssertNotNil(json["displayBSSIDs"])
        XCTAssertNil(json["selectedSSIDs"])
        XCTAssertNil(json["selectedBSSIDs"])
        XCTAssertNil(json["selectedSSID"])
        XCTAssertNil(json["selectedBSSID"])
        XCTAssertNil(json["activeBand"])
    }

    func testCanonicalNilDisplayNetworkRoundTripStaysNil() throws {
        let settings = SurveyViewSettings(
            requiredSSIDs: ["Required but not displayable yet"],
            requiredBSSIDs: [],
            trackedBands: [.ghz5],
            displayBand: .ghz5,
            displaySSID: nil,
            displayBSSIDs: [],
            showHeatmap: false,
            metric: .rssi,
            colorScheme: .classic,
            fadeRadius: 6
        )

        let decoded = try JSONDecoder().decode(
            SurveyViewSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertNil(decoded.displaySSID)
        XCTAssertEqual(decoded, settings)
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

        XCTAssertEqual(settings.requiredSSIDs, ["Home"])
        XCTAssertEqual(settings.requiredBSSIDs, ["aa:bb"])
        XCTAssertEqual(settings.trackedBands, Set(WiFiBand.allCases))
        XCTAssertEqual(settings.displayBand, .ghz5)
        XCTAssertEqual(settings.displaySSID, "Home")
        XCTAssertEqual(settings.displayBSSIDs, ["aa:bb"])
    }

    func testLegacyMultiSelectionsBecomeRequirementsWithoutChoosingDisplayNetwork() throws {
        let data = """
        {
          "selectedSSIDs": ["Home", "Office"],
          "selectedBSSIDs": ["home-ap", "office-ap"],
          "trackedBands": ["ghz2_4", "ghz5"],
          "activeBand": "ghz5",
          "showHeatmap": true,
          "metric": "rssi",
          "colorScheme": "classic",
          "fadeRadius": 6
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(SurveyViewSettings.self, from: data)

        XCTAssertEqual(settings.requiredSSIDs, ["Home", "Office"])
        XCTAssertEqual(settings.requiredBSSIDs, ["home-ap", "office-ap"])
        XCTAssertEqual(settings.trackedBands, [.ghz2_4, .ghz5])
        XCTAssertEqual(settings.displayBand, .ghz5)
        XCTAssertNil(settings.displaySSID)
        XCTAssertTrue(settings.displayBSSIDs.isEmpty)
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
        XCTAssertEqual(backupURL?.lastPathComponent, "Old Survey.pre-v4-backup-1970-01-01-073000.wifiheatmap")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(backupURL).path))
        XCTAssertFalse(document.requiresMigration)
        XCTAssertEqual(document.survey.floors.map(\.id), [floorID])
        XCTAssertEqual(
            document.migrationSuccessMessage,
            "Survey updated to support multiple scan sets. Backup saved as Old Survey.pre-v4-backup-1970-01-01-073000.wifiheatmap."
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

    func testV4DocumentPublishesImmediatelyWithoutCreatingBackup() throws {
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
            .appendingPathComponent("Repeated.pre-v4-backup-1970-01-01-073000.wifiheatmap")
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
            "Repeated.pre-v4-backup-1970-01-01-073000-2.wifiheatmap"
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

    private func legacyV3Wrapper(floorID: UUID, points: [SurveyPoint]) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let floor = Floor(
            id: floorID,
            name: "Legacy Floor",
            floorPlanFilename: "\(floorID.uuidString).png",
            calibration: nil,
            points: points
        )
        let manifestData = """
        {
          "schemaVersion": 3,
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

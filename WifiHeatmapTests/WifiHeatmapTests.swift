import XCTest
import AppKit
@testable import WifiHeatmap

final class WifiHeatmapTests: XCTestCase {
    func testDeleteSelectedPointActionInvokesTheActiveDocumentHandler() {
        var deleted = false
        let action = DeleteSelectedPointAction { deleted = true }

        action()

        XCTAssertTrue(deleted)
    }

    func testOnlyRequiredBSSIDTooltipOffersSkipAction() {
        XCTAssertTrue(OnboardingTipID.requiredBSSIDs.showsSkipButton)
        XCTAssertFalse(OnboardingTipID.importFloorPlan.showsSkipButton)
        XCTAssertFalse(OnboardingTipID.calibrateDistance.showsSkipButton)
        XCTAssertFalse(OnboardingTipID.requiredSSIDs.showsSkipButton)
        XCTAssertFalse(OnboardingTipID.capturePoint.showsSkipButton)
    }

    func testRequiredBSSIDDefaultsSelectEveryApplicableOptionOnceInUntitledSurvey() {
        let groups = [
            BSSIDOptionGroup(ssid: "Office", options: [
                BSSIDOption(ssid: "Office", bssid: "office-5", band: .ghz5),
                BSSIDOption(ssid: "Office", bssid: "office-6", band: .ghz6)
            ])
        ]
        var initializer = RequiredBSSIDSelectionInitializer()

        XCTAssertNil(initializer.selectionToApply(
            defaultsToAll: true,
            hasRequiredSSIDs: false,
            hasCompletedRequiredSSIDScan: false,
            groups: groups,
            currentSelection: []
        ))
        XCTAssertNil(initializer.selectionToApply(
            defaultsToAll: true,
            hasRequiredSSIDs: true,
            hasCompletedRequiredSSIDScan: false,
            groups: groups,
            currentSelection: []
        ))
        XCTAssertEqual(
            initializer.selectionToApply(
                defaultsToAll: true,
                hasRequiredSSIDs: true,
                hasCompletedRequiredSSIDScan: true,
                groups: groups,
                currentSelection: []
            ),
            ["office-5", "office-6"]
        )
        XCTAssertNil(initializer.selectionToApply(
            defaultsToAll: true,
            hasRequiredSSIDs: true,
            hasCompletedRequiredSSIDScan: true,
            groups: groups,
            currentSelection: []
        ))
    }

    func testRequiredBSSIDDefaultsPreserveExistingSurveySelection() {
        let groups = [
            BSSIDOptionGroup(ssid: "Office", options: [
                BSSIDOption(ssid: "Office", bssid: "office-5", band: .ghz5)
            ])
        ]
        var initializer = RequiredBSSIDSelectionInitializer()

        XCTAssertNil(initializer.selectionToApply(
            defaultsToAll: false,
            hasRequiredSSIDs: true,
            hasCompletedRequiredSSIDScan: true,
            groups: groups,
            currentSelection: []
        ))
    }

    func testAutomaticRequiredBSSIDDefaultsRespectDisabledRecordBands() {
        let groups = [
            BSSIDOptionGroup(ssid: "Office", options: [
                BSSIDOption(ssid: "Office", bssid: "office-5", band: .ghz5),
                BSSIDOption(ssid: "Office", bssid: "office-6", band: .ghz6)
            ])
        ]
        var initializer = RequiredBSSIDSelectionInitializer()

        XCTAssertEqual(
            initializer.selectionToApply(
                defaultsToAll: true,
                hasRequiredSSIDs: true,
                hasCompletedRequiredSSIDScan: true,
                groups: groups,
                currentSelection: [],
                recordBands: [.ghz5]
            ),
            ["office-5"]
        )
    }

    func testAutomaticRequiredBSSIDDefaultsDoNotPrematurelyCompleteOnboarding() {
        let automaticDefault: Set<String> = ["office-5", "office-6"]

        XCTAssertFalse(RequiredBSSIDOnboardingProgress.isConfigured(
            selection: automaticDefault,
            automaticDefault: automaticDefault,
            hasClosedSelectionMenu: false,
            isSelectionMenuOpen: false
        ))
        XCTAssertTrue(RequiredBSSIDOnboardingProgress.isConfigured(
            selection: automaticDefault,
            automaticDefault: automaticDefault,
            hasClosedSelectionMenu: true,
            isSelectionMenuOpen: false
        ))
        XCTAssertTrue(RequiredBSSIDOnboardingProgress.isConfigured(
            selection: automaticDefault,
            automaticDefault: nil,
            hasClosedSelectionMenu: false,
            isSelectionMenuOpen: false
        ))
        XCTAssertFalse(RequiredBSSIDOnboardingProgress.isConfigured(
            selection: ["office-5"],
            automaticDefault: automaticDefault,
            hasClosedSelectionMenu: false,
            isSelectionMenuOpen: true
        ))
    }

    func testRequiredBSSIDTooltipWaitsForSSIDScanAndBSSIDMenuClosure() {
        let base = OnboardingContext(
            hasFloors: true,
            selectedFloorHasPlan: true,
            hasAnyCalibration: true,
            hasRequiredSSIDs: true,
            hasAvailableBSSIDs: true,
            showsInspector: true
        )

        XCTAssertNil(OnboardingFlow.nextTip(for: base))

        var afterScan = base
        afterScan.hasCompletedRequiredSSIDScan = true
        XCTAssertEqual(OnboardingFlow.nextTip(for: afterScan), .requiredBSSIDs)

        afterScan.hasRequiredBSSIDs = true
        afterScan.isRequiredBSSIDSelectionOpen = true
        XCTAssertEqual(OnboardingFlow.nextTip(for: afterScan), .requiredBSSIDs)

        afterScan.isRequiredBSSIDSelectionOpen = false
        afterScan.canCaptureOnSelectedFloor = true
        XCTAssertEqual(OnboardingFlow.nextTip(for: afterScan), .capturePoint)
    }

    func testOnboardingFlowAdvancesThroughTheRequestedSequence() {
        XCTAssertEqual(
            OnboardingFlow.nextTip(for: OnboardingContext()),
            .importFloorPlan
        )
        XCTAssertEqual(
            OnboardingFlow.nextTip(for: OnboardingContext(
                hasFloors: true,
                selectedFloorHasPlan: true
            )),
            .calibrateDistance
        )
        XCTAssertEqual(
            OnboardingFlow.nextTip(for: OnboardingContext(
                hasFloors: true,
                selectedFloorHasPlan: true,
                hasAnyCalibration: true,
                showsInspector: true
            )),
            .requiredSSIDs
        )
        XCTAssertEqual(
            OnboardingFlow.nextTip(for: OnboardingContext(
                hasFloors: true,
                selectedFloorHasPlan: true,
                hasAnyCalibration: true,
                hasRequiredSSIDs: true,
                hasCompletedRequiredSSIDScan: true,
                hasAvailableBSSIDs: true,
                showsInspector: true
            )),
            .requiredBSSIDs
        )
        XCTAssertEqual(
            OnboardingFlow.nextTip(
                for: OnboardingContext(
                    hasFloors: true,
                    selectedFloorHasPlan: true,
                    hasAnyCalibration: true,
                    hasRequiredSSIDs: true,
                    hasAvailableBSSIDs: true,
                    canCaptureOnSelectedFloor: true,
                    showsInspector: true
                ),
                dismissed: [.requiredBSSIDs]
            ),
            .capturePoint
        )
    }

    func testOnboardingFlowHonorsSessionDismissalsAndGlobalPreference() {
        let context = OnboardingContext()

        XCTAssertNil(OnboardingFlow.nextTip(for: context, dismissed: [.importFloorPlan]))
        XCTAssertNil(OnboardingFlow.nextTip(for: context, isHelpEnabled: false))
    }

    @MainActor
    func testOnboardingSessionLatchesTipsCompletedByUserProgress() {
        let state = OnboardingSessionState()
        let completedContext = OnboardingContext(
            hasFloors: true,
            selectedFloorHasPlan: true,
            hasAnyCalibration: true,
            hasRequiredSSIDs: true,
            hasRequiredBSSIDs: true,
            hasAvailableBSSIDs: true,
            canCaptureOnSelectedFloor: true,
            hasRecordedPoints: true,
            showsInspector: true
        )

        state.latchCompletedTips(for: completedContext)
        state.latchCompletedTips(for: OnboardingContext())

        XCTAssertEqual(
            state.dismissedTips,
            [.importFloorPlan, .calibrateDistance, .requiredSSIDs, .requiredBSSIDs, .capturePoint]
        )
    }

    @MainActor
    func testRequiredSSIDTipLatchesOnlyAfterSelectionMenuCloses() {
        let state = OnboardingSessionState()

        state.latchCompletedTips(for: OnboardingContext(
            hasRequiredSSIDs: true,
            isRequiredSSIDSelectionOpen: true
        ))
        XCTAssertFalse(state.dismissedTips.contains(.requiredSSIDs))

        state.latchCompletedTips(for: OnboardingContext(
            hasRequiredSSIDs: true,
            isRequiredSSIDSelectionOpen: false
        ))
        XCTAssertTrue(state.dismissedTips.contains(.requiredSSIDs))
    }

    func testNetworkDiscoveryRetriesPotentiallyCachedResultsAndReturnsFreshBatch() async throws {
        var attempts: [Int] = []
        var delays: [UInt64] = []

        let result = try await NetworkDiscoveryCoordinator.refresh(
            maxAttempts: 3,
            cacheRefreshBackoffNanoseconds: [10, 20],
            scan: { attempt in
                attempts.append(attempt)
                return self.batch(
                    [self.network("Home", "home-5", .ghz5)],
                    attempt: attempt,
                    cacheUpdated: attempt == 3
                )
            },
            sleep: { delays.append($0) }
        )

        XCTAssertEqual(attempts, [1, 2, 3])
        XCTAssertEqual(delays, [10, 20])
        XCTAssertTrue(result.scanCacheUpdated)
        XCTAssertEqual(result.attemptCount, 3)
    }

    func testNetworkDiscoveryReturnsNewestSuccessfulBatchAfterBoundedFreshnessRetries() async throws {
        var attempts = 0

        let result = try await NetworkDiscoveryCoordinator.refresh(
            maxAttempts: 2,
            cacheRefreshBackoffNanoseconds: [0],
            scan: { attempt in
                attempts += 1
                return self.batch(
                    [self.network("Home", "home-\(attempt)", .ghz5)],
                    attempt: attempt,
                    cacheUpdated: false
                )
            },
            sleep: { _ in }
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(result.networks.map(\.bssid), ["home-2"])
    }

    func testInitialWiFiScanGateAllowsExactlyOneAutomaticScan() {
        var gate = InitialWiFiScanGate()

        XCTAssertTrue(gate.claim())
        XCTAssertFalse(gate.claim())
        XCTAssertFalse(gate.claim())
    }

    func testRequiredSSIDRefreshGateRequestsRefreshOnlyAfterChangedMenuCloses() {
        let now = Date(timeIntervalSince1970: 1_000)
        var gate = RequiredSSIDRefreshGate()

        gate.menuDidOpen(selection: ["Office"])
        XCTAssertNil(gate.menuDidClose(selection: ["Office"], at: now))

        gate.menuDidOpen(selection: ["Office"])
        XCTAssertEqual(
            gate.menuDidClose(selection: ["Office", "Guest"], at: now),
            0
        )
    }

    func testRequiredSSIDRefreshGateAppliesSixtySecondCooldown() throws {
        let firstRefresh = Date(timeIntervalSince1970: 1_000)
        var gate = RequiredSSIDRefreshGate()
        gate.didRefresh(at: firstRefresh)

        gate.menuDidOpen(selection: ["Office"])
        let cooldownDelay = gate.menuDidClose(
            selection: ["Office", "Guest"],
            at: firstRefresh.addingTimeInterval(15)
        )
        XCTAssertEqual(
            try XCTUnwrap(cooldownDelay),
            45,
            accuracy: 0.001
        )

        gate.menuDidOpen(selection: ["Office", "Guest"])
        XCTAssertEqual(
            gate.menuDidClose(
                selection: ["Office", "Guest", "Lab"],
                at: firstRefresh.addingTimeInterval(60)
            ),
            0
        )
    }

    func testInspectorExposesNewScanButtonAndScanPicker() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WifiHeatmap/Views/InspectorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("FullWidthScanPicker("))
        XCTAssertTrue(source.contains("Image(systemName: \"plus\")"))
        XCTAssertTrue(source.contains(".help(\"New scan\")"))
        XCTAssertTrue(source.contains("Image(systemName: \"trash\")"))
        XCTAssertTrue(source.contains(".help(\"Delete scan\")"))
        XCTAssertFalse(source.contains("Label(\"New Scan\", systemImage: \"plus\")"))
    }

    func testScanPickerEndsWithASeparatedNewScanAction() {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        let scan = ScanSet(
            id: UUID(),
            name: "Morning",
            createdAt: Date(timeIntervalSince1970: 1_000),
            floorIDs: []
        )

        ScanPickerLayout.populate(popup, scanSets: [scan], activeScanID: scan.id)

        XCTAssertEqual(popup.itemArray.count, 3)
        XCTAssertEqual(popup.itemArray[0].title, "Morning")
        XCTAssertTrue(popup.itemArray[1].isSeparatorItem)
        XCTAssertEqual(popup.itemArray[2].title, "New Scan")
        XCTAssertEqual(
            ScanPickerLayout.action(for: popup.itemArray[2]),
            .newScan
        )
        XCTAssertEqual(
            ScanPickerLayout.action(for: popup.itemArray[0]),
            .select(scan.id)
        )
    }

    func testEmptyScanPickerStillOffersNewScanAction() {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)

        ScanPickerLayout.populate(popup, scanSets: [], activeScanID: nil)

        XCTAssertEqual(popup.itemArray.count, 3)
        XCTAssertEqual(popup.itemArray[0].title, "No scans yet")
        XCTAssertFalse(popup.itemArray[0].isEnabled)
        XCTAssertTrue(popup.itemArray[1].isSeparatorItem)
        XCTAssertEqual(popup.itemArray[2].title, "New Scan")
        XCTAssertTrue(popup.itemArray[2].isEnabled)
    }

    func testScanManagementDialogsUseExplicitNamesAndActions() {
        XCTAssertEqual(
            ScanDialogCopy.deleteTitle(scanName: "Evening survey"),
            "Delete “Evening survey”?"
        )
        XCTAssertEqual(
            ScanDialogCopy.deleteMessage(scanName: "Evening survey"),
            "Are you sure you want to delete “Evening survey” and all of its recorded points? This cannot be undone."
        )
    }

    func testInspectorContainsNamedCreationAndDeletionDialogs() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("WifiHeatmap/Views/InspectorView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".alert(\"New Scan\""))
        XCTAssertTrue(source.contains("TextField(\"Scan name\", text: $newScanName)"))
        XCTAssertTrue(source.contains("Button(\"OK\")"))
        XCTAssertTrue(source.contains("Button(\"Cancel\", role: .cancel)"))
        XCTAssertTrue(source.contains("ScanDialogCopy.deleteTitle"))
        XCTAssertTrue(source.contains("Button(\"Delete Scan\", role: .destructive)"))
    }

    func testNativeScanPopupAllowsHorizontalExpansion() {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)

        ScanPickerLayout.configure(popup)

        XCTAssertEqual(popup.contentHuggingPriority(for: .horizontal).rawValue, 1)
        XCTAssertEqual(popup.contentCompressionResistancePriority(for: .horizontal).rawValue, 1)
    }

    func testInspectorUsesFullWidthScanPickerWithInlineRenameControl() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WifiHeatmap/Views/InspectorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Text(\"Scan\")"))
        XCTAssertTrue(source.contains(".font(.caption)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity)"))
        XCTAssertTrue(source.contains("Image(systemName: \"pencil\")"))
        XCTAssertTrue(source.contains(".help(\"Rename scan\")"))
        XCTAssertTrue(source.contains("TextField(\"Scan name\", text: $scanName)"))
        XCTAssertTrue(source.contains("Image(systemName: \"checkmark\")"))
        XCTAssertTrue(source.contains("Image(systemName: \"xmark\")"))
        XCTAssertTrue(source.contains(".help(\"Cancel renaming\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Cancel renaming\")"))
        XCTAssertFalse(source.contains("Button(\"Rename Scan\\u{2026}\")"))
        XCTAssertFalse(source.contains(".alert(\"Rename Scan\""))
    }

    func testEveryMultiSelectionMenuActionKeepsTheMenuOpen() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("WifiHeatmap/Views/InspectorView.swift"),
            encoding: .utf8
        )
        let menuStart = try XCTUnwrap(source.range(of: "struct MultiSelectionMenu: View"))
        let nextControlStart = try XCTUnwrap(
            source.range(
                of: "struct HeatmapRangeControl: View",
                range: menuStart.upperBound..<source.endIndex
            )
        )
        let menuSource = source[menuStart.lowerBound..<nextControlStart.lowerBound]

        XCTAssertTrue(menuSource.contains("@State private var isPresented = false"))
        XCTAssertTrue(menuSource.contains(".popover(isPresented: $isPresented"))
        XCTAssertFalse(
            menuSource.contains("Menu(summary)"),
            "A standard macOS Menu closes after each action and cannot provide rapid multi-selection."
        )
    }

    func testDisplayBandPickerHidesItsInlineLabel() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("WifiHeatmap/Views/FloorDetailView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let pickerStart = try XCTUnwrap(source.range(of: "Picker(\"Band\", selection: $displayBand)"))
        let helpStart = try XCTUnwrap(
            source.range(
                of: ".help(\"Show readings from one WiFi band.",
                range: pickerStart.lowerBound..<source.endIndex
            )
        )
        let bandPickerSource = source[pickerStart.lowerBound..<helpStart.lowerBound]

        XCTAssertTrue(
            bandPickerSource.contains(".labelsHidden()"),
            "The band title must stay hidden so it cannot wrap into a narrow column in the header."
        )
    }

    func testDisplayBSSIDMenuUsesItsIntrinsicWidth() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("WifiHeatmap/Views/FloorDetailView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let labelStart = try XCTUnwrap(source.range(of: "Text(\"BSSIDs\")"))
        let helpStart = try XCTUnwrap(
            source.range(
                of: ".help(\"Choose one or more BSSIDs to display.",
                range: labelStart.lowerBound..<source.endIndex
            )
        )
        let bssidControlSource = source[labelStart.lowerBound..<helpStart.lowerBound]

        XCTAssertTrue(
            bssidControlSource.contains(".fixedSize(horizontal: true, vertical: false)"),
            "The header BSSID menu must not expand and push its dropdown away from its label."
        )
    }

    func testBSSIDSelectorsAreGroupedBySSIDAndRequiredEntriesShowBands() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let floorSource = try String(
            contentsOf: projectRoot.appendingPathComponent("WifiHeatmap/Views/FloorDetailView.swift"),
            encoding: .utf8
        )
        let inspectorSource = try String(
            contentsOf: projectRoot.appendingPathComponent("WifiHeatmap/Views/InspectorView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(floorSource.contains("Text(\"BSSIDs\")"))
        XCTAssertFalse(floorSource.contains("Text(\"Access Points\")"))
        XCTAssertTrue(inspectorSource.contains("LabeledContent(\"Required BSSIDs\")"))
        XCTAssertFalse(inspectorSource.contains("LabeledContent(\"Required Access Points\")"))
        XCTAssertTrue(inspectorSource.contains("struct GroupedBSSIDSelectionMenu: View"))
        XCTAssertTrue(inspectorSource.contains("Text(group.ssid)"))
        XCTAssertTrue(inspectorSource.contains(".font(.caption2)"))
        XCTAssertTrue(inspectorSource.contains("showsBand: true"))
        XCTAssertTrue(inspectorSource.contains("\\(option.bssid) (\\(option.bandLabel))"))
    }

    func testMapPressDragReleaseCreatesAnOrientedPendingPointBeforeScanning() throws {
        let floorPlanSource = try viewSource(named: "FloorPlanView.swift")
        let markerSource = try viewSource(named: "SampleMarkersView.swift")

        XCTAssertTrue(floorPlanSource.contains("@Binding var pendingPoint: PendingSurveyPoint?"))
        XCTAssertTrue(floorPlanSource.contains("DragGesture(minimumDistance: 0"))
        XCTAssertTrue(floorPlanSource.contains("pendingPoint = PendingSurveyPoint("))
        XCTAssertTrue(floorPlanSource.contains("onCaptureRequested"))
        XCTAssertTrue(floorPlanSource.contains("PendingPointMarker("))
        XCTAssertTrue(markerSource.contains("struct PendingPointMarker: View"))
        XCTAssertTrue(markerSource.contains("ProgressView()"))
    }

    func testCommittedPointMarkersAreSelectableDraggableAndRotatable() throws {
        let floorPlanSource = try viewSource(named: "FloorPlanView.swift")
        let markerSource = try viewSource(named: "SampleMarkersView.swift")
        let detailSource = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(markerSource.contains("NSCursor.pointingHand"))
        XCTAssertTrue(markerSource.contains("struct RotationHandle: View"))
        XCTAssertTrue(markerSource.contains("DragGesture(minimumDistance: 0"))
        XCTAssertTrue(markerSource.contains("accessibilityLabel(\"Rotate point\")"))
        XCTAssertTrue(floorPlanSource.contains("onMovePoint"))
        XCTAssertTrue(floorPlanSource.contains("onSetPointOrientation"))
        XCTAssertTrue(detailSource.contains("PointUndo.registerUndoForUpdate("))
        XCTAssertTrue(detailSource.contains("actionName: \"Move Point\""))
        XCTAssertTrue(detailSource.contains("actionName: \"Rotate Point\""))
    }

    func testPointAndRotationChromeUseThirtyPercentSmallerVisualScaleWithoutDirectionPrompt() throws {
        let markerSource = try viewSource(named: "SampleMarkersView.swift")

        XCTAssertTrue(markerSource.contains("static let visualScale: CGFloat = 0.7"))
        XCTAssertTrue(markerSource.contains("14 * PointMarkerLayout.visualScale"))
        XCTAssertTrue(markerSource.contains("29 * PointMarkerLayout.visualScale"))
        XCTAssertTrue(markerSource.contains("18 * PointMarkerLayout.visualScale"))
        XCTAssertTrue(markerSource.contains("9 * PointMarkerLayout.visualScale"))
        XCTAssertFalse(markerSource.contains("Set direction"))
    }

    func testOrientationFlowsFromMapGestureIntoTheRecordedScanPoint() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelSource = try String(
            contentsOf: projectRoot.appendingPathComponent("WifiHeatmap/Models/ScannedNetwork.swift"),
            encoding: .utf8
        )
        let detailSource = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(modelSource.contains("orientationDegrees: Double? = nil"))
        XCTAssertTrue(modelSource.contains("orientationDegrees: orientationDegrees"))
        XCTAssertTrue(detailSource.contains("orientationDegrees: pendingPoint.orientationDegrees"))
    }

    func testCancellingMapDragLatchesUntilMouseUpAndDoesNotCommitPoint() {
        var state = PointAdditionGestureState()

        state.beginIfNeeded()
        XCTAssertTrue(state.acceptsUpdates)

        state.cancel()
        XCTAssertFalse(state.acceptsUpdates)
        XCTAssertFalse(state.finishShouldCommit())

        state.beginIfNeeded()
        XCTAssertTrue(state.acceptsUpdates)
        XCTAssertTrue(state.finishShouldCommit())
    }

    func testCancelledCaptureSessionRejectsLateScanResultAndDoesNotAffectNextCapture() {
        let firstID = UUID()
        let secondID = UUID()
        var session = PointCaptureSessionState()

        XCTAssertEqual(session.begin(id: firstID), firstID)
        XCTAssertTrue(session.acceptsResult(for: firstID))

        session.cancel()
        XCTAssertFalse(session.acceptsResult(for: firstID))

        XCTAssertEqual(session.begin(id: secondID), secondID)
        XCTAssertFalse(session.acceptsResult(for: firstID))
        XCTAssertTrue(session.acceptsResult(for: secondID))
        XCTAssertTrue(session.finish(id: secondID))
        XCTAssertFalse(session.acceptsResult(for: secondID))
    }

    func testUnsetPointOrientationHasNoDisplayedAngleUntilRotationActuallyMoves() {
        XCTAssertNil(PointRotationPresentation.displayedDegrees(stored: nil, preview: nil))
        XCTAssertEqual(
            PointRotationPresentation.displayedDegrees(stored: 135, preview: nil),
            135
        )
        XCTAssertEqual(
            PointRotationPresentation.displayedDegrees(stored: nil, preview: 42),
            42
        )
        XCTAssertNil(
            PointRotationPresentation.committedDegrees(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 11, y: 10)
            )
        )
        XCTAssertEqual(
            PointRotationPresentation.committedDegrees(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 20, y: 10)
            ),
            0
        )
    }

    func testRotationHandleHitTargetIsGenerousAndFullyInsideItsContainer() throws {
        XCTAssertGreaterThanOrEqual(PointRotationHandleLayout.hitTargetDiameter, 28)
        XCTAssertGreaterThanOrEqual(
            PointRotationHandleLayout.containerSize / 2,
            PointRotationHandleLayout.ringRadius
                + PointRotationHandleLayout.hitTargetDiameter / 2
        )

        let markerSource = try viewSource(named: "SampleMarkersView.swift")
        XCTAssertTrue(markerSource.contains("rotationHitTarget"))
        XCTAssertTrue(markerSource.contains(".highPriorityGesture(rotationGesture)"))
        XCTAssertTrue(markerSource.contains(".allowsHitTesting(false)"))
    }

    func testExistingPointsStayInteractiveDuringPointCaptureButNotCalibration() {
        XCTAssertTrue(ExistingPointInteractionPolicy.isEnabled(
            isCalibrating: false,
            isCaptureInProgress: true
        ))
        XCTAssertFalse(ExistingPointInteractionPolicy.isEnabled(
            isCalibrating: true,
            isCaptureInProgress: false
        ))
    }

    func testHeatmapRangeHasNoInitiallyFocusedNumberField() {
        XCTAssertNil(HeatmapRangeFocusPolicy.initialField)
    }

    @MainActor
    func testWindowTextFieldFocusControllerClearsInitialFocusOnlyOnce() {
        var clearCount = 0
        let controller = WindowTextFieldFocusController {
            clearCount += 1
        }

        controller.clearInitialFocus()
        controller.clearInitialFocus()

        XCTAssertEqual(clearCount, 1)
    }

    @MainActor
    func testWindowTextFieldFocusControllerClearsFocusForEveryPointerPress() {
        var clearCount = 0
        let controller = WindowTextFieldFocusController {
            clearCount += 1
        }

        controller.pointerPressed()
        controller.pointerPressed()

        XCTAssertEqual(clearCount, 2)
    }

    func testDocumentContentInstallsWindowTextFieldFocusBridge() throws {
        let source = try viewSource(named: "ContentView.swift")

        XCTAssertTrue(source.contains(".background(WindowTextFieldFocusBridge())"))
    }


    func testBottomStatusBarHasAStableFootprint() {
        XCTAssertEqual(BottomStatusBarLayout.height, 112)
        XCTAssertEqual(BottomStatusBarLayout.statusCardWidth, 440)
        XCTAssertEqual(BottomStatusBarLayout.statusCardHeight, 96)
        XCTAssertGreaterThanOrEqual(
            BottomStatusBarLayout.height,
            BottomStatusBarLayout.statusCardHeight + 16
        )
    }

    func testSelectedPointMetadataIncludesEveryCaptureAndReadingField() {
        let id = UUID(uuidString: "D8D71D02-5F3E-4ABC-8D3A-92A84A2BF2F0")!
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let completedAt = Date(timeIntervalSince1970: 1_002.75)
        let point = SurveyPoint(
            id: id,
            position: CGPoint(x: 123.25, y: 456.75),
            orientationDegrees: 278.5,
            startedAt: startedAt,
            completedAt: completedAt,
            scanCacheUpdated: true,
            snapshotChanged: false,
            attemptCount: 2,
            readings: [
                WifiNetworkReading(
                    ssid: "Office",
                    bssid: "office-6",
                    rssi: -48,
                    noise: -92,
                    band: .ghz6,
                    channel: 37
                ),
                WifiNetworkReading(
                    ssid: "Guest",
                    bssid: "guest-2",
                    rssi: -61,
                    noise: -95,
                    band: .ghz2_4,
                    channel: 6
                )
            ]
        )

        let metadata = SelectedPointMetadata(point: point)

        XCTAssertEqual(metadata.id, id)
        XCTAssertEqual(metadata.position, CGPoint(x: 123.25, y: 456.75))
        XCTAssertEqual(metadata.orientationDegrees, 278.5)
        XCTAssertEqual(metadata.startedAt, startedAt)
        XCTAssertEqual(metadata.completedAt, completedAt)
        XCTAssertEqual(metadata.duration, 2.75)
        XCTAssertTrue(metadata.scanCacheUpdated)
        XCTAssertEqual(metadata.snapshotChanged, false)
        XCTAssertEqual(metadata.attemptCount, 2)
        XCTAssertEqual(metadata.readings.map(\.bssid), ["guest-2", "office-6"])
        XCTAssertEqual(metadata.readings[0].ssid, "Guest")
        XCTAssertEqual(metadata.readings[0].band, .ghz2_4)
        XCTAssertEqual(metadata.readings[0].channel, 6)
        XCTAssertEqual(metadata.readings[0].rssi, -61)
        XCTAssertEqual(metadata.readings[0].noise, -95)
        XCTAssertEqual(metadata.readings[0].snr, 34)
    }

    func testSelectedPointMetadataPrioritizesActiveDisplaySSIDBandAndBSSIDs() {
        let point = SurveyPoint(
            id: UUID(),
            position: .zero,
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            scanCacheUpdated: true,
            snapshotChanged: true,
            attemptCount: 1,
            readings: [
                WifiNetworkReading(ssid: "Guest", bssid: "guest-2", rssi: -62, noise: -92, band: .ghz2_4, channel: 6),
                WifiNetworkReading(ssid: "Office", bssid: "office-2", rssi: -55, noise: -90, band: .ghz2_4, channel: 11),
                WifiNetworkReading(ssid: "Office", bssid: "office-5-other", rssi: -50, noise: -91, band: .ghz5, channel: 36),
                WifiNetworkReading(ssid: "Guest", bssid: "guest-5", rssi: -58, noise: -93, band: .ghz5, channel: 44),
                WifiNetworkReading(ssid: "Office", bssid: "office-5-selected", rssi: -45, noise: -90, band: .ghz5, channel: 149)
            ]
        )
        let displayFilter = SampleFilter(
            band: .ghz5,
            ssid: "Office",
            bssids: ["office-5-selected"]
        )

        let metadata = SelectedPointMetadata(point: point, priorityFilter: displayFilter)

        XCTAssertEqual(
            metadata.readings.map(\.bssid),
            ["office-5-selected", "office-5-other", "office-2", "guest-5", "guest-2"]
        )
    }

    func testSelectedPointMetadataCardPutsReadingTableFirstAndCaptureDetailsLast() throws {
        let source = try viewSource(named: "FloorDetailView.swift")
        let start = try XCTUnwrap(source.range(of: "private struct SelectedPointMetadataView"))
        let end = try XCTUnwrap(
            source.range(
                of: "private struct PointMetadataItem",
                range: start.upperBound..<source.endIndex
            )
        )
        let viewSource = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertFalse(viewSource.contains("Label(\"Selected point\""))
        XCTAssertFalse(viewSource.contains("metadata.id.uuidString"))
        XCTAssertTrue(
            viewSource.contains(
                "VStack(alignment: .leading, spacing: 4) {\n            readingsGrid\n            Divider()\n            captureMetadata"
            )
        )
        XCTAssertTrue(viewSource.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
    }

    func testBottomLeftShowsSelectedPointMetadataAndNoLongerShowsSetupNotices() throws {
        let source = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(source.contains("private var selectedPoint: SurveyPoint?"))
        XCTAssertTrue(source.contains("SelectedPointMetadataView(point:"))
        XCTAssertTrue(source.contains("Text(\"SSID\")"))
        XCTAssertTrue(source.contains("Text(\"BSSID\")"))
        XCTAssertTrue(source.contains("Text(\"Band\")"))
        XCTAssertTrue(source.contains("Text(\"Channel\")"))
        XCTAssertTrue(source.contains("Text(\"RSSI\")"))
        XCTAssertTrue(source.contains("Text(\"Noise\")"))
        XCTAssertTrue(source.contains("Text(\"SNR\")"))
        XCTAssertFalse(source.contains("private var calibrationStatus"))
        XCTAssertFalse(source.contains("No calibration "))
        XCTAssertFalse(source.contains("No floor "))
    }

    func testDisplayFilterOptionsChooseOneSSIDAndScopeAccessPointsToItAndItsBand() {
        let point = SurveyPoint(
            id: UUID(),
            position: .zero,
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            scanCacheUpdated: true,
            snapshotChanged: true,
            attemptCount: 1,
            readings: [
                WifiNetworkReading(ssid: "Office", bssid: "office-2", rssi: -55, noise: -90, band: .ghz2_4, channel: 6),
                WifiNetworkReading(ssid: "Office", bssid: "office-5", rssi: -45, noise: -90, band: .ghz5, channel: 36),
                WifiNetworkReading(ssid: "Guest", bssid: "guest-5", rssi: -60, noise: -92, band: .ghz5, channel: 44)
            ]
        )
        let latest = [
            ScannedNetwork(ssid: "Office", bssid: "office-5b", rssi: -48, noise: -91, band: .ghz5, channel: 149)
        ]
        let options = FloorFilterOptions(points: [point], latestBatch: latest)

        XCTAssertEqual(options.displaySSIDs, ["Guest", "Office"])
        XCTAssertEqual(options.resolvedDisplaySSID(nil), "Office")
        XCTAssertEqual(options.resolvedDisplaySSID("Office"), "Office")
        XCTAssertEqual(options.resolvedDisplaySSID("Missing"), "Office")
        XCTAssertEqual(
            options.displayBSSIDs(band: .ghz5, ssid: "Office"),
            ["office-5", "office-5b"]
        )
        XCTAssertEqual(options.displayBSSIDs(band: .ghz2_4, ssid: "Office"), ["office-2"])
    }

    func testDisplayFilterOptionsDefaultToStrongestSSIDFromLatestScanAcrossAllBands() {
        let storedPoint = SurveyPoint(
            id: UUID(),
            position: .zero,
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            scanCacheUpdated: true,
            snapshotChanged: true,
            attemptCount: 1,
            readings: [
                WifiNetworkReading(ssid: "Stored Strong", bssid: "stored", rssi: -20, noise: -90, band: .ghz5, channel: 36)
            ]
        )
        let latest = [
            ScannedNetwork(ssid: "Alpha", bssid: "alpha-2", rssi: -62, noise: -90, band: .ghz2_4, channel: 6),
            ScannedNetwork(ssid: "Zulu", bssid: "zulu-6", rssi: -41, noise: -90, band: .ghz6, channel: 37),
            ScannedNetwork(ssid: "Zulu", bssid: "zulu-5", rssi: -48, noise: -90, band: .ghz5, channel: 36)
        ]
        let options = FloorFilterOptions(points: [storedPoint], latestBatch: latest)

        XCTAssertEqual(options.resolvedDisplaySSID(nil), "Zulu")
        XCTAssertEqual(options.resolvedDisplaySSID("Alpha"), "Alpha")
    }

    func testDisplayFilterOptionsTreatEmptyOrStaleAPSelectionAsAllAvailableAPs() {
        let latest = [
            ScannedNetwork(ssid: "Office", bssid: "office-a", rssi: -45, noise: -90, band: .ghz5, channel: 36),
            ScannedNetwork(ssid: "Office", bssid: "office-b", rssi: -50, noise: -91, band: .ghz5, channel: 44),
            ScannedNetwork(ssid: "Guest", bssid: "guest-a", rssi: -60, noise: -92, band: .ghz5, channel: 149)
        ]
        let options = FloorFilterOptions(points: [], latestBatch: latest)

        XCTAssertEqual(
            options.effectiveDisplayBSSIDs([], band: .ghz5, ssid: "Office"),
            []
        )
        XCTAssertEqual(
            options.effectiveDisplayBSSIDs(["stale"], band: .ghz5, ssid: "Office"),
            []
        )
        XCTAssertEqual(
            options.effectiveDisplayBSSIDs(["office-a", "guest-a"], band: .ghz5, ssid: "Office"),
            ["office-a"]
        )
    }

    func testRequiredBSSIDOptionsIncludeBandsThatAreNotYetEnabledForRecording() {
        let latest = [
            ScannedNetwork(ssid: "Office", bssid: "office-2", rssi: -55, noise: -90, band: .ghz2_4, channel: 6),
            ScannedNetwork(ssid: "Office", bssid: "office-5", rssi: -45, noise: -90, band: .ghz5, channel: 36),
            ScannedNetwork(ssid: "Guest", bssid: "guest-5", rssi: -60, noise: -92, band: .ghz5, channel: 44)
        ]
        let options = FloorFilterOptions(points: [], latestBatch: latest)

        XCTAssertEqual(
            options.requiredBSSIDs(requiredSSIDs: ["Office"], trackedBands: [.ghz2_4, .ghz5]),
            ["office-2", "office-5"]
        )
        XCTAssertEqual(
            options.requiredBSSIDs(requiredSSIDs: [], trackedBands: [.ghz5]),
            ["guest-5", "office-2", "office-5"]
        )
    }

    func testScanRequirementSummarySeparatesHardRequirementsFromOptionalRecording() {
        XCTAssertEqual(
            ScanRequirementSummary.lines(
                requiredSSIDCount: 2,
                requiredBSSIDCount: 2,
                recordBands: [.ghz2_4, .ghz5, .ghz6]
            ),
            [
                "Require 2 SSIDs on any selected record band",
                "Require 2 BSSIDs",
                "Record 2.4, 5 and 6 GHz when available"
            ]
        )
        XCTAssertEqual(
            ScanRequirementSummary.lines(
                requiredSSIDCount: 0,
                requiredBSSIDCount: 0,
                recordBands: [.ghz5]
            ),
            [
                "Accept any network on a selected record band",
                "No specific BSSIDs required",
                "Record 5 GHz when available"
            ]
        )
    }

    func testRequiredBSSIDBandsAreAuthoritativeForRecordingAndLocking() {
        let knownBands = [
            "home-2": WiFiBand.ghz2_4,
            "home-5": WiFiBand.ghz5,
            "guest-6": WiFiBand.ghz6
        ]

        XCTAssertEqual(
            RecordBandPolicy.requiredBands(
                selectedBSSIDs: ["home-2", "home-5"],
                knownBSSIDBands: knownBands
            ),
            [.ghz2_4, .ghz5]
        )
        XCTAssertEqual(
            RecordBandPolicy.normalizedRecordBands(
                [.ghz6],
                selectedBSSIDs: ["home-2", "home-5"],
                knownBSSIDBands: knownBands
            ),
            Set(WiFiBand.allCases)
        )
    }

    func testInspectorPresentsRecordBandsAsOptionalAndShowsDetectionAndLockingStatus() throws {
        let source = try viewSource(named: "InspectorView.swift")

        XCTAssertTrue(source.contains("LabeledContent(\"Record Bands\")"))
        XCTAssertFalse(source.contains("LabeledContent(\"Track Bands\")"))
        XCTAssertTrue(source.contains("\"Detected\" : \"Not observed\""))
        XCTAssertTrue(source.contains("requiredRecordBands.contains(band)"))
        XCTAssertTrue(source.contains("Required by a selected BSSID"))
    }

    func testScanActorIsAProcessLifetimeSingleton() {
        XCTAssertTrue(ScanActor.shared === ScanActor.shared)
    }

    func testFullScanPointStoresEveryReadingAndScanMetadata() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let completedAt = startedAt.addingTimeInterval(1.25)
        let position = CGPoint(x: 42, y: 84)
        var scanCount = 0
        let networks = [
            ScannedNetwork(ssid: "Office", bssid: "2g", rssi: -45, noise: -90, band: .ghz2_4, channel: 6),
            ScannedNetwork(ssid: "Office", bssid: "5g-a", rssi: -51, noise: -92, band: .ghz5, channel: 44),
            ScannedNetwork(ssid: "Office", bssid: "5g-b", rssi: -63, noise: -91, band: .ghz5, channel: 149),
            ScannedNetwork(ssid: "Guest", bssid: "6g", rssi: -59, noise: -93, band: .ghz6, channel: 5)
        ]

        let capture = try await FullScanPoint.record(at: position) {
            scanCount += 1
            return ScanBatch(
                networks: networks,
                startedAt: startedAt,
                completedAt: completedAt,
                scanCacheUpdated: true,
                snapshotChanged: false,
                attemptCount: 2
            )
        }

        XCTAssertEqual(capture.position, position)
        XCTAssertEqual(scanCount, 1)
        XCTAssertEqual(capture.startedAt, startedAt)
        XCTAssertEqual(capture.completedAt, completedAt)
        XCTAssertTrue(capture.scanCacheUpdated)
        XCTAssertEqual(capture.snapshotChanged, false)
        XCTAssertEqual(capture.attemptCount, 2)
        XCTAssertEqual(capture.readings.count, networks.count)
        XCTAssertEqual(capture.readings.map(\.bssid), networks.map(\.bssid))
        XCTAssertEqual(capture.readings.map(\.channel), networks.map(\.channel))
        XCTAssertEqual(capture.readings.map(\.rssi), networks.map(\.rssi))
        XCTAssertEqual(capture.readings.map(\.noise), networks.map(\.noise))
    }

    func testFullScanPointPropagatesFailureWithoutReturningPartialData() async {
        enum ScanFailure: Swift.Error, Equatable { case unavailable }

        do {
            _ = try await FullScanPoint.record(at: CGPoint(x: 5, y: 8)) {
                throw ScanFailure.unavailable
            }
            XCTFail("Expected capture creation to fail atomically with the scan")
        } catch let error as ScanFailure {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCompleteScanSnapshotComparesEveryBSSIDRSSINoiseTupleRegardlessOfOrder() {
        let first = ScannedNetwork(
            ssid: "Office", bssid: "aa:aa", rssi: -50, noise: -90,
            band: .ghz5, channel: 36
        )
        let second = ScannedNetwork(
            ssid: "Guest", bssid: "bb:bb", rssi: -65, noise: -92,
            band: .ghz5, channel: 44
        )
        let baseline = ScanSnapshot(networks: [first, second])

        XCTAssertEqual(baseline, ScanSnapshot(networks: [second, first]))

        var changedRSSI = first
        changedRSSI.rssi -= 1
        XCTAssertNotEqual(baseline, ScanSnapshot(networks: [changedRSSI, second]))

        var changedNoise = first
        changedNoise.noise -= 1
        XCTAssertNotEqual(baseline, ScanSnapshot(networks: [changedNoise, second]))

        var changedBSSID = first
        changedBSSID.bssid = "cc:cc"
        XCTAssertNotEqual(baseline, ScanSnapshot(networks: [changedBSSID, second]))
    }

    func testRetryPolicyRejectsEveryBatchWithoutConfirmedCacheUpdate() {
        func batch(
            duration: TimeInterval = 0.2,
            cacheUpdated: Bool = false,
            snapshotChanged: Bool? = false
        ) -> ScanBatch {
            let startedAt = Date(timeIntervalSince1970: 100)
            return ScanBatch(
                networks: [],
                startedAt: startedAt,
                completedAt: startedAt.addingTimeInterval(duration),
                scanCacheUpdated: cacheUpdated,
                snapshotChanged: snapshotChanged,
                attemptCount: 1
            )
        }

        XCTAssertTrue(ScanRetryPolicy.shouldRetry(batch()))
        XCTAssertTrue(ScanRetryPolicy.shouldRetry(batch(duration: 1.0)))
        XCTAssertFalse(ScanRetryPolicy.shouldRetry(batch(cacheUpdated: true)))
        XCTAssertTrue(ScanRetryPolicy.shouldRetry(batch(snapshotChanged: true)))
        XCTAssertTrue(ScanRetryPolicy.shouldRetry(batch(snapshotChanged: nil)))

        XCTAssertGreaterThanOrEqual(ScanRetryPolicy.cacheEventWaitTimeout, 1.0)
    }

    func testPointCaptureDefaultsToFiveAttemptsWithAtLeastFiveSecondsBetweenAttempts() {
        let fiveSeconds: UInt64 = 5_000_000_000

        XCTAssertEqual(PointCaptureCoordinator.maximumAttempts, 5)
        XCTAssertEqual(PointCaptureCoordinator.minimumRetryDelayNanoseconds, fiveSeconds)
        XCTAssertEqual(PointCaptureCoordinator.standardBackoffNanoseconds.count, 4)
        XCTAssertEqual(PointCaptureCoordinator.standardCacheRefreshBackoffNanoseconds.count, 4)
        XCTAssertTrue(PointCaptureCoordinator.standardBackoffNanoseconds.allSatisfy { $0 >= fiveSeconds })
        XCTAssertTrue(PointCaptureCoordinator.standardCacheRefreshBackoffNanoseconds.allSatisfy { $0 >= fiveSeconds })
    }

    func testRetryCountdownRoundsUpAndStopsAtZero() {
        let retryAt = Date(timeIntervalSince1970: 105)

        XCTAssertEqual(RetryCountdown.secondsRemaining(until: retryAt, at: Date(timeIntervalSince1970: 100)), 5)
        XCTAssertEqual(RetryCountdown.secondsRemaining(until: retryAt, at: Date(timeIntervalSince1970: 104.2)), 1)
        XCTAssertEqual(RetryCountdown.secondsRemaining(until: retryAt, at: Date(timeIntervalSince1970: 105)), 0)
        XCTAssertEqual(RetryCountdown.secondsRemaining(until: retryAt, at: Date(timeIntervalSince1970: 110)), 0)
    }

    func testSignalStatusCardDisplaysTheLiveRetryCountdown() throws {
        let source = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(source.contains("RetryCountdown.secondsRemaining"))
        XCTAssertTrue(source.contains("Retrying in \\(secondsRemaining)s"))
        XCTAssertTrue(source.contains("retryAt:"))
    }

    func testRetryProgressPublishesTheEnforcedCountdownDelay() async throws {
        let requirements = CaptureRequirements(
            requiredSSIDs: ["Office"], requiredBSSIDs: [], trackedBands: [.ghz5]
        )
        var progress: [CaptureProgress] = []
        var delays: [UInt64] = []

        _ = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            maxAttempts: 2,
            backoffNanoseconds: [1],
            scan: { attempt in
                self.batch(
                    [self.network(attempt == 1 ? "Home" : "Office", "ap-5", .ghz5)],
                    attempt: attempt
                )
            },
            sleep: { delays.append($0) },
            onProgress: { progress.append($0) }
        )

        XCTAssertEqual(delays, [5_000_000_000])
        XCTAssertEqual(progress, [
            .scanning(attempt: 1, maxAttempts: 2),
            .retrying(
                reason: .missingSSIDs(["Office"]),
                nextAttempt: 2,
                maxAttempts: 2,
                delayNanoseconds: 5_000_000_000
            ),
            .scanning(attempt: 2, maxAttempts: 2)
        ])
    }

    func testExhaustedCaptureReportsEveryMissingRequirementFromTheFinalReading() async {
        let requirements = CaptureRequirements(
            requiredSSIDs: ["Home", "Office"],
            requiredBSSIDs: ["home-5", "office-5"],
            trackedBands: [.ghz5]
        )

        do {
            _ = try await PointCaptureCoordinator.capture(
                at: .zero,
                requirements: requirements,
                maxAttempts: 1,
                scan: { attempt in
                    self.batch([self.network("Home", "home-5", .ghz5)], attempt: attempt)
                },
                sleep: { _ in }
            )
            XCTFail("Expected an incomplete capture")
        } catch let error as PointCaptureError {
            XCTAssertEqual(
                error.errorDescription,
                "No complete reading after 1 attempts.\nMissing required SSID: Office\nMissing required BSSID: office-5"
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCaptureAcceptsWhenEveryRequiredSSIDExistsOnAnyRecordBand() async throws {
        let requirements = CaptureRequirements(
            requiredSSIDs: ["Home", "Office"],
            requiredBSSIDs: [],
            trackedBands: [.ghz2_4, .ghz5]
        )
        var attempts: [Int] = []
        var progress: [CaptureProgress] = []

        let point = try await PointCaptureCoordinator.capture(
            at: CGPoint(x: 1, y: 2),
            requirements: requirements,
            backoffNanoseconds: [0, 0, 0],
            scan: { attempt in
                attempts.append(attempt)
                return self.batch([
                    self.network("Home", "home-2", .ghz2_4),
                    self.network("Office", "office-5", .ghz5),
                    self.network("Guest", "guest-6", .ghz6)
                ], attempt: attempt)
            },
            sleep: { _ in },
            onProgress: { progress.append($0) }
        )

        XCTAssertEqual(attempts, [1])
        XCTAssertEqual(point.attemptCount, 1)
        XCTAssertEqual(Set(point.readings.map(\.ssid)), ["Home", "Office"])
        XCTAssertFalse(point.readings.contains { $0.band == .ghz6 })
        XCTAssertFalse(progress.contains { progress in
            if case .retrying = progress { return true }
            return false
        })
    }

    func testCaptureRetriesWhenRequiredBSSIDIsMissingButDoesNotRequireItOnEveryBand() async throws {
        let requirements = CaptureRequirements(
            requiredSSIDs: ["Home"],
            requiredBSSIDs: ["home-5"],
            trackedBands: [.ghz2_4, .ghz5]
        )
        var attempts = 0

        let point = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            backoffNanoseconds: [0, 0, 0],
            scan: { attempt in
                attempts += 1
                let fiveBSSID = attempt == 1 ? "other-5" : "home-5"
                return self.batch([
                    self.network("Home", "home-2", .ghz2_4),
                    self.network("Home", fiveBSSID, .ghz5)
                ], attempt: attempt)
            },
            sleep: { _ in }
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(point.attemptCount, 2)
    }

    func testEmptyRequiredBSSIDSelectionAcceptsSSIDOnAnyRecordBand() async throws {
        let requirements = CaptureRequirements(
            requiredSSIDs: ["Home"],
            requiredBSSIDs: [],
            trackedBands: [.ghz2_4, .ghz5]
        )

        let reason = PointCaptureCoordinator.rejectionReason(
            for: batch([
                network("Home", "any-2", .ghz2_4)
            ], attempt: 1),
            requirements: requirements
        )

        XCTAssertNil(reason)
    }

    func testAcceptedCaptureRetainsUnrelatedReadingsOnTrackedBands() async throws {
        let requirements = CaptureRequirements(
            requiredSSIDs: ["Home"],
            requiredBSSIDs: ["home-5"],
            trackedBands: [.ghz5]
        )

        let point = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            scan: { attempt in
                self.batch([
                    self.network("Home", "home-5", .ghz5),
                    self.network("Guest", "guest-5", .ghz5),
                    self.network("Other", "other-6", .ghz6)
                ], attempt: attempt)
            },
            sleep: { _ in }
        )

        XCTAssertEqual(Set(point.readings.map(\.ssid)), ["Home", "Guest"])
        XCTAssertEqual(Set(point.readings.map(\.bssid)), ["home-5", "guest-5"])
    }

    func testRequiredBSSIDKnownToBelongToDisabledBandExtendsRecordingToThatBand() async throws {
        let requirements = CaptureRequirements(
            requiredSSIDs: [],
            requiredBSSIDs: ["legacy-6"],
            requiredBSSIDBands: ["legacy-6": .ghz6],
            trackedBands: [.ghz5]
        )
        var attempts = 0

        let point = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            backoffNanoseconds: [0, 0, 0],
            scan: { attempt in
                attempts += 1
                return self.batch([
                    self.network("Home", "home-5", .ghz5),
                    self.network("Home", "legacy-6", .ghz6)
                ], attempt: attempt)
            },
            sleep: { _ in }
        )

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(Set(point.readings.map(\.bssid)), ["home-5", "legacy-6"])
    }

    func testDualBandRequiredBSSIDsSucceedWhenSixGHzIsEnabledButNotObserved() async throws {
        let requirements = CaptureRequirements(
            requiredSSIDs: ["Home"],
            requiredBSSIDs: ["home-2", "home-5"],
            requiredBSSIDBands: ["home-2": .ghz2_4, "home-5": .ghz5],
            trackedBands: [.ghz2_4, .ghz5, .ghz6]
        )
        var attempts = 0

        let point = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            backoffNanoseconds: [0, 0, 0],
            scan: { attempt in
                attempts += 1
                return self.batch([
                    self.network("Home", "home-2", .ghz2_4),
                    self.network("Home", "home-5", .ghz5)
                ], attempt: attempt)
            },
            sleep: { _ in }
        )

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(point.bandCount, 2)
        XCTAssertEqual(Set(point.readings.map(\.bssid)), ["home-2", "home-5"])
    }

    func testCaptureRetriesWhenNoNetworksExistOnSelectedRecordBands() async throws {
        let requirements = CaptureRequirements(
            requiredSSIDs: [], requiredBSSIDs: [], trackedBands: [.ghz5]
        )
        var progress: [CaptureProgress] = []

        let point = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            backoffNanoseconds: [0, 0, 0],
            scan: { attempt in
                let networks = attempt == 1
                    ? [self.network("Home", "home-2", .ghz2_4)]
                    : [self.network("Home", "home-5", .ghz5)]
                return self.batch(networks, attempt: attempt)
            },
            sleep: { _ in },
            onProgress: { progress.append($0) }
        )

        XCTAssertEqual(point.attemptCount, 2)
        XCTAssertTrue(progress.contains(.retrying(
            reason: .noNetworksOnRecordBands([.ghz5]),
            nextAttempt: 2,
            maxAttempts: 5,
            delayNanoseconds: 5_000_000_000
        )))
    }

    func testCaptureRetriesUntilCacheUpdateIsConfirmed() async throws {
        let requirements = CaptureRequirements(requiredSSIDs: [], requiredBSSIDs: [], trackedBands: [.ghz5])
        var attempts = 0

        let point = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            backoffNanoseconds: [0, 0, 0],
            scan: { attempt in
                attempts += 1
                return self.batch(
                    [self.network("Home", "home-5", .ghz5)],
                    attempt: attempt,
                    duration: attempt == 1 ? 0.2 : 1,
                    cacheUpdated: attempt == 2,
                    snapshotChanged: false
                )
            },
            sleep: { _ in }
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(point.attemptCount, 2)
    }

    func testCaptureUsesDedicatedCooldownForPotentiallyCachedResults() async throws {
        let requirements = CaptureRequirements(requiredSSIDs: [], requiredBSSIDs: [], trackedBands: [.ghz5])
        var delays: [UInt64] = []

        let point = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            backoffNanoseconds: [11, 22, 33],
            cacheRefreshBackoffNanoseconds: [2_000, 3_000, 5_000],
            scan: { attempt in
                self.batch(
                    [self.network("Home", "home-5", .ghz5)],
                    attempt: attempt,
                    duration: 1,
                    cacheUpdated: attempt == 4,
                    snapshotChanged: true
                )
            },
            sleep: { delays.append($0) }
        )

        XCTAssertEqual(point.attemptCount, 4)
        XCTAssertEqual(delays, [5_000_000_000, 5_000_000_000, 5_000_000_000])
    }

    func testCaptureNeverAcceptsBatchWithoutConfirmedCacheUpdate() async {
        let requirements = CaptureRequirements(requiredSSIDs: [], requiredBSSIDs: [], trackedBands: [.ghz5])
        var attempts = 0
        var delays: [UInt64] = []

        do {
            _ = try await PointCaptureCoordinator.capture(
                at: .zero,
                requirements: requirements,
                maxAttempts: 3,
                backoffNanoseconds: [11, 22],
                cacheRefreshBackoffNanoseconds: [2_000, 3_000],
                scan: { attempt in
                    attempts += 1
                    return self.batch(
                        [self.network("Home", "home-5", .ghz5)],
                        attempt: attempt,
                        duration: 2,
                        cacheUpdated: false,
                        snapshotChanged: true
                    )
                },
                sleep: { delays.append($0) }
            )
            XCTFail("Expected failure without a confirmed cache update")
        } catch let error as PointCaptureError {
            XCTAssertEqual(attempts, 3)
            XCTAssertEqual(error, PointCaptureError(reason: .potentiallyStale, attempts: 3))
            XCTAssertEqual(delays, [5_000_000_000, 5_000_000_000])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCaptureRetriesRecoverableScanFailureAndUsesConfiguredBackoff() async throws {
        let requirements = CaptureRequirements(requiredSSIDs: [], requiredBSSIDs: [], trackedBands: [.ghz5])
        var attempts = 0
        var delays: [UInt64] = []

        _ = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            backoffNanoseconds: [500, 1_000, 2_000],
            scan: { attempt in
                attempts += 1
                if attempt < 3 { throw ScanActor.ScanError.failed("temporary") }
                return self.batch([self.network("Home", "home-5", .ghz5)], attempt: attempt)
            },
            sleep: { delays.append($0) }
        )

        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(delays, [5_000_000_000, 5_000_000_000])
    }

    func testCaptureDoesNotRetryUnavailableInterface() async {
        let requirements = CaptureRequirements(requiredSSIDs: [], requiredBSSIDs: [], trackedBands: [.ghz5])
        var attempts = 0

        do {
            _ = try await PointCaptureCoordinator.capture(
                at: .zero,
                requirements: requirements,
                backoffNanoseconds: [0, 0, 0],
                scan: { _ in
                    attempts += 1
                    throw ScanActor.ScanError.interfaceUnavailable
                },
                sleep: { _ in }
            )
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(attempts, 1)
        }
    }

    func testCaptureExhaustionReturnsNoPointAndNeverMergesAttempts() async {
        let requirements = CaptureRequirements(
            requiredSSIDs: ["Home", "Office"], requiredBSSIDs: [], trackedBands: [.ghz2_4, .ghz5]
        )
        var attempts = 0

        do {
            _ = try await PointCaptureCoordinator.capture(
                at: .zero,
                requirements: requirements,
                backoffNanoseconds: [0, 0, 0],
                scan: { attempt in
                    attempts += 1
                    let network = attempt.isMultiple(of: 2)
                        ? self.network("Office", "office-5", .ghz5)
                        : self.network("Home", "home-2", .ghz2_4)
                    return self.batch([network], attempt: attempt)
                },
                sleep: { _ in }
            )
            XCTFail("Expected atomic failure rather than merged readings")
        } catch let error as PointCaptureError {
            XCTAssertEqual(attempts, 5)
            XCTAssertEqual(error.attempts, 5)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func network(_ ssid: String, _ bssid: String, _ band: WiFiBand) -> ScannedNetwork {
        ScannedNetwork(ssid: ssid, bssid: bssid, rssi: -50, noise: -90, band: band, channel: 1)
    }

    private func batch(
        _ networks: [ScannedNetwork],
        attempt: Int,
        duration: TimeInterval = 1,
        cacheUpdated: Bool = true,
        snapshotChanged: Bool? = true
    ) -> ScanBatch {
        let startedAt = Date(timeIntervalSince1970: 100)
        return ScanBatch(
            networks: networks,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(duration),
            scanCacheUpdated: cacheUpdated,
            snapshotChanged: snapshotChanged,
            attemptCount: attempt
        )
    }

    func testSignalStatusHasNoSignalBeforeFirstScan() {
        let status = SignalUpdateStatus(latestScanAt: nil, lastTaggedAt: nil)

        XCTAssertEqual(status.freshness, .noSignal)
    }

    func testSignalStatusIsReadyWhenScanExistsWithoutTag() {
        let status = SignalUpdateStatus(
            latestScanAt: Date(timeIntervalSince1970: 100),
            lastTaggedAt: nil
        )

        XCTAssertEqual(status.freshness, .readyToLog)
    }

    func testSignalStatusWaitsWhenTagUsedLatestScan() {
        let status = SignalUpdateStatus(
            latestScanAt: Date(timeIntervalSince1970: 100),
            lastTaggedAt: Date(timeIntervalSince1970: 101)
        )

        XCTAssertEqual(status.freshness, .waitingForNewScan)
    }

    func testSignalStatusIsFreshWhenScanCompletedAfterTag() {
        let status = SignalUpdateStatus(
            latestScanAt: Date(timeIntervalSince1970: 102),
            lastTaggedAt: Date(timeIntervalSince1970: 101)
        )

        XCTAssertEqual(status.freshness, .freshScanAvailable)
    }

    func testSignalStatusFormatsRecentUpdateAge() {
        let status = SignalUpdateStatus(
            latestScanAt: Date(timeIntervalSince1970: 100),
            lastTaggedAt: nil
        )

        XCTAssertEqual(
            status.updatedText(at: Date(timeIntervalSince1970: 107)),
            "Updated 7s ago"
        )
    }

    func testSignalStatusFormatsOlderUpdateAgeInMinutes() {
        let status = SignalUpdateStatus(
            latestScanAt: Date(timeIntervalSince1970: 100),
            lastTaggedAt: nil
        )

        XCTAssertEqual(
            status.updatedText(at: Date(timeIntervalSince1970: 225)),
            "Updated 2m ago"
        )
    }

    private func viewSource(named filename: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: projectRoot.appendingPathComponent("WifiHeatmap/Views/\(filename)"),
            encoding: .utf8
        )
    }

}

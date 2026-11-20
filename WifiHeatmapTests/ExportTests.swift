import XCTest
import CoreGraphics
@testable import WifiHeatmap

final class ExportTests: XCTestCase {

    func testAppProvidesGlobalHelpTooltipSetting() throws {
        let source = try projectSource(named: "WifiHeatmapApp.swift")

        XCTAssertTrue(source.contains("Settings {"))
        XCTAssertTrue(source.contains("HelpTooltipSettingsView()"))
        XCTAssertTrue(source.contains("Toggle(\"Show help tooltips\""))
        XCTAssertTrue(source.contains("@AppStorage(HelpTooltipPreferences.showHelpTooltipsKey)"))
    }

    func testOnboardingTooltipsAreAnchoredToRequestedControls() throws {
        let detailSource = try viewSource(named: "FloorDetailView.swift")
        let inspectorSource = try viewSource(named: "InspectorView.swift")

        XCTAssertTrue(detailSource.contains("tip: .importFloorPlan"))
        XCTAssertTrue(detailSource.contains("tip: .calibrateDistance"))
        XCTAssertTrue(detailSource.contains("tip: .capturePoint"))
        XCTAssertTrue(inspectorSource.contains("tip: .requiredSSIDs"))
        XCTAssertTrue(inspectorSource.contains("tip: .requiredBSSIDs"))
        XCTAssertTrue(detailSource.contains("handleRequiredSSIDMenuPresentation"))
    }

    func testTooltipSupportsGlobalOptOutFromItsCloseButton() throws {
        let source = try projectSource(named: "WifiHeatmapApp.swift")

        XCTAssertTrue(source.contains("Toggle(\"Don’t show again\""))
        XCTAssertTrue(source.contains("showHelpTooltips = false"))
        XCTAssertTrue(source.contains("Button(action: dismiss)"))
        XCTAssertFalse(source.contains("Button(\"Got it\""))
    }

    func testRequiredBSSIDTooltipOffersSkipButtonAtBottomRight() throws {
        let source = try projectSource(named: "WifiHeatmapApp.swift")

        XCTAssertTrue(source.contains("if tip.showsSkipButton"))
        XCTAssertTrue(source.contains("Button(\"Skip\", action: dismiss)"))
        XCTAssertTrue(source.contains("Spacer(minLength: 12)"))
    }

    func testUntitledSurveyDefaultsRequiredBSSIDsToEveryApplicableOption() throws {
        let contentSource = try viewSource(named: "ContentView.swift")
        let detailSource = try viewSource(named: "FloorDetailView.swift")
        let inspectorSource = try viewSource(named: "InspectorView.swift")

        XCTAssertTrue(contentSource.contains("defaultsRequiredBSSIDsToAll: fileURL == nil"))
        XCTAssertTrue(detailSource.contains("defaultsRequiredBSSIDsToAll: defaultsRequiredBSSIDsToAll"))
        XCTAssertTrue(detailSource.contains("defaultRequiredBSSIDSelection"))
        XCTAssertTrue(detailSource.contains("hasCompletedRequiredSSIDScan"))
        XCTAssertTrue(detailSource.contains("isRequiredBSSIDMenuPresented"))
        XCTAssertTrue(detailSource.contains(".onChange(of: isScanning)"))
        XCTAssertTrue(detailSource.contains("guard !isScanning"))
        XCTAssertTrue(detailSource.contains("RequiredBSSIDOnboardingProgress.isConfigured"))
        XCTAssertTrue(inspectorSource.contains("applyDefaultRequiredBSSIDSelectionIfNeeded"))
        XCTAssertTrue(inspectorSource.contains("onDefaultRequiredBSSIDsApplied(selection)"))
        XCTAssertTrue(inspectorSource.contains("onPresentationChanged: onRequiredBSSIDMenuPresentationChanged"))
        XCTAssertTrue(inspectorSource.contains(".onChange(of: availableBSSIDGroups)"))
        XCTAssertTrue(inspectorSource.contains(".onChange(of: requiredSSIDs)"))
    }

    func testTooltipDoesNotDismissForOutsideClicksOrWindowFocusChanges() throws {
        let source = try projectSource(named: "WifiHeatmapApp.swift")

        XCTAssertTrue(source.contains("popover.behavior = .applicationDefined"))
        XCTAssertTrue(source.contains("PersistentPopoverPresenter("))
        XCTAssertFalse(source.contains(".popover(isPresented:"))
    }

    func testPersistentTooltipTracksWindowGeometryAndChoosesAnInBoundsEdge() throws {
        let source = try projectSource(named: "WifiHeatmapApp.swift")

        XCTAssertTrue(source.contains("NSWindow.didMoveNotification"))
        XCTAssertTrue(source.contains("NSWindow.didResizeNotification"))
        XCTAssertTrue(source.contains("popover.positioningRect = anchorView.bounds"))
        XCTAssertTrue(source.contains("PersistentPopoverPlacement.preferredEdge"))
        XCTAssertTrue(source.contains("screen.visibleFrame"))
    }

    func testRequiredSSIDTooltipWaitsForSelectionMenuToCloseBeforeAdvancing() throws {
        let detailSource = try viewSource(named: "FloorDetailView.swift")
        let inspectorSource = try viewSource(named: "InspectorView.swift")

        XCTAssertTrue(detailSource.contains("@State private var isRequiredSSIDMenuPresented"))
        XCTAssertTrue(detailSource.contains("isRequiredSSIDSelectionOpen: isRequiredSSIDMenuPresented"))
        XCTAssertTrue(inspectorSource.contains("onRequiredSSIDMenuPresentationChanged"))
        XCTAssertTrue(inspectorSource.contains("onPresentationChanged: onRequiredSSIDMenuPresentationChanged"))
        XCTAssertTrue(inspectorSource.contains("onPresentationChanged(isPresented)"))
    }

    func testRequiredSSIDSelectionRefreshesOnlyAfterTheChangedMenuCloses() throws {
        let detailSource = try viewSource(named: "FloorDetailView.swift")

        XCTAssertFalse(detailSource.contains(".onChange(of: settings.requiredSSIDs)"))
        XCTAssertTrue(detailSource.contains("requiredSSIDRefreshGate.menuDidOpen"))
        XCTAssertTrue(detailSource.contains("requiredSSIDRefreshGate.menuDidClose"))
        XCTAssertTrue(detailSource.contains("scheduleRequiredSSIDRefresh(after: delay)"))
    }

    func testRequiredSSIDMenuContainsOnlyActualNetworksAndUsesPromptForEmptySelection() throws {
        let source = try viewSource(named: "InspectorView.swift")
        let controlStart = try XCTUnwrap(source.range(of: "LabeledContent(\"Required SSIDs\")"))
        let controlEnd = try XCTUnwrap(
            source.range(
                of: "LabeledContent(\"Required BSSIDs\")",
                range: controlStart.upperBound..<source.endIndex
            )
        )
        let controlSource = source[controlStart.lowerBound..<controlEnd.lowerBound]

        XCTAssertTrue(controlSource.contains("emptySelectionLabel: \"Select SSID(s)...\""))
        XCTAssertTrue(controlSource.contains("showsClearSelectionOption: false"))
        XCTAssertFalse(controlSource.contains("Any SSID"))
    }

    func testFirstOnboardingTooltipPrefersTheRightSideOfImportButton() throws {
        let source = try projectSource(named: "WifiHeatmapApp.swift")

        XCTAssertTrue(source.contains("preferredEdge: tip == .importFloorPlan ? .maxX : nil"))
        XCTAssertTrue(source.contains("preferredEdge.flatMap"))
    }

    func testInspectorOmitsRedundantLegendAndFloorPlanSections() throws {
        let source = try viewSource(named: "InspectorView.swift")

        XCTAssertFalse(source.contains("Section(\"Legend\")"))
        XCTAssertFalse(source.contains("Section(\"Floor Plan\")"))
    }

    func testClearAllRequiresDestructiveConfirmation() throws {
        let source = try viewSource(named: "InspectorView.swift")

        XCTAssertTrue(source.contains(".confirmationDialog("))
        XCTAssertTrue(source.contains("Button(\"Clear All Points\", role: .destructive, action: onClearAll)"))
    }

    func testFloorCloseButtonUsesAStandardHitTarget() throws {
        let source = try viewSource(named: "FloorTabBar.swift")

        XCTAssertTrue(source.contains(".frame(width: 24, height: 24)"))
        XCTAssertTrue(source.contains(".contentShape(Rectangle())"))
    }

    func testFloorDeletionRequiresDestructiveConfirmation() throws {
        let source = try viewSource(named: "FloorTabBar.swift")

        XCTAssertTrue(source.contains("@State private var floorPendingDeletion: Floor?"))
        XCTAssertTrue(source.contains(".confirmationDialog("))
        XCTAssertTrue(source.contains("Button(\"Delete Floor\", role: .destructive)"))
    }

    func testEmptyFloorPlanOffersImageImportButton() throws {
        let source = try viewSource(named: "FloorPlanView.swift")

        XCTAssertTrue(source.contains("let onImport: () -> Void"))
        XCTAssertTrue(source.contains("Button(action: onImport)"))
        XCTAssertTrue(source.contains("Label(\"Import Floor Plan\\u{2026}\", systemImage: \"photo\")"))
    }

    func testEmptySurveyOffersDirectFloorPlanImportThatCreatesItsFirstFloor() throws {
        let contentSource = try viewSource(named: "ContentView.swift")
        let detailSource = try viewSource(named: "FloorDetailView.swift")

        XCTAssertFalse(contentSource.contains("Add a floor using the "))
        XCTAssertTrue(contentSource.contains("onImportFirstFloorPlan: importFirstFloorPlan"))
        XCTAssertTrue(detailSource.contains("Button(action: onImportFirstFloorPlan)"))
        XCTAssertTrue(detailSource.contains("Label(\"Import Floor Plan\\u{2026}\", systemImage: \"photo\")"))
        XCTAssertTrue(contentSource.contains("document.addFloor(name: \"Floor 1\")"))
        XCTAssertTrue(contentSource.contains("try document.importFloorPlan(url: url, for: floorID)"))
        XCTAssertTrue(contentSource.contains("document.removeFloor(id: floorID)"))
        XCTAssertTrue(contentSource.contains("selectedFloorID = floorID"))
    }

    func testEmptySurveyOffersExistingSurveyOpenFlowBelowOrDivider() throws {
        let contentSource = try viewSource(named: "ContentView.swift")
        let detailSource = try viewSource(named: "FloorDetailView.swift")
        let appSource = try projectSource(named: "WifiHeatmapApp.swift")

        XCTAssertTrue(detailSource.contains("Text(\"OR\")"))
        XCTAssertTrue(detailSource.contains("Text(\"Open an existing scan\")"))
        XCTAssertTrue(detailSource.contains("Button(action: onOpenExistingSurvey)"))
        XCTAssertTrue(detailSource.contains("Label(\"Choose .wifiheatmap File\\u{2026}\", systemImage: \"folder\")"))
        XCTAssertTrue(contentSource.contains("@Environment(\\.openDocument)"))
        XCTAssertTrue(contentSource.contains("panel.allowedContentTypes = [.wifiSurvey]"))
        XCTAssertTrue(contentSource.contains("closeCoordinator.prepareForDocumentReplacement"))
        XCTAssertTrue(contentSource.contains("try await openDocument(at: url)"))
        XCTAssertTrue(contentSource.contains("sourceWindow.performClose(nil)"))
        XCTAssertTrue(contentSource.contains("closeCoordinator.resetCloseApproval()"))
        XCTAssertTrue(contentSource.contains("onOpenExistingSurvey: openExistingSurvey"))
        XCTAssertTrue(contentSource.contains(".focusedSceneValue("))
        XCTAssertTrue(contentSource.contains("\\.openSurveyInCurrentWindow"))
        XCTAssertTrue(appSource.contains("CommandGroup(replacing: .newItem)"))
        XCTAssertTrue(appSource.contains("@FocusedValue(\\.openSurveyInCurrentWindow)"))
        XCTAssertTrue(appSource.contains("Button(\"Open\\u{2026}\")"))
    }

    func testStartupLauncherCreatesBlankDocumentBeforeDocumentGroupCanShowItsChooser() throws {
        let source = try projectSource(named: "WifiHeatmapApp.swift")
        let launcherScene = try XCTUnwrap(source.range(of: "WindowGroup(id: StartupDocumentLauncher.sceneID)"))
        let documentScene = try XCTUnwrap(source.range(of: "DocumentGroup(newDocument:"))

        XCTAssertLessThan(launcherScene.lowerBound, documentScene.lowerBound)
        XCTAssertTrue(source.contains("@Environment(\\.newDocument)"))
        XCTAssertTrue(source.contains("newDocument { WifiSurveyDocument() }"))
        XCTAssertTrue(source.contains("dismissWindow(id: Self.sceneID)"))
        XCTAssertEqual(source.components(separatedBy: "DocumentGroup(newDocument:").count - 1, 1)
    }

    func testWorkspaceBarsRemainMountedWhenNoFloorIsSelected() throws {
        let contentSource = try viewSource(named: "ContentView.swift")
        let detailSource = try viewSource(named: "FloorDetailView.swift")

        XCTAssertFalse(contentSource.contains("if let idx = selectedFloorIndex"))
        XCTAssertTrue(contentSource.contains("floor: selectedFloorBinding"))
        XCTAssertTrue(detailSource.contains("let floor: Binding<Floor>?"))
        XCTAssertTrue(detailSource.contains("DisplayFiltersBar("))
        XCTAssertTrue(detailSource.contains("FloorPlanActionsBar("))
        XCTAssertTrue(detailSource.contains("SignalStatusView("))
        XCTAssertTrue(detailSource.contains("InspectorView("))
    }

    func testUnsavedCloseGuardCoversWindowCloseAndApplicationTermination() throws {
        let contentSource = try viewSource(named: "ContentView.swift")
        let appSource = try projectSource(named: "WifiHeatmapApp.swift")

        XCTAssertTrue(contentSource.contains("func windowShouldClose(_ sender: NSWindow) -> Bool"))
        XCTAssertTrue(contentSource.contains("let panel = NSSavePanel()"))
        XCTAssertTrue(contentSource.contains("WindowCloseBridge("))
        XCTAssertTrue(appSource.contains("applicationShouldTerminate"))
        XCTAssertTrue(appSource.contains("@NSApplicationDelegateAdaptor"))
    }

    func testContentViewRunsOneInitialWiFiDiscoveryScan() throws {
        let source = try viewSource(named: "ContentView.swift")

        XCTAssertTrue(source.contains("@State private var initialScanGate = InitialWiFiScanGate()"))
        XCTAssertTrue(source.contains("guard initialScanGate.claim() else { return }"))
        XCTAssertTrue(source.contains("await refreshAvailableNetworks()"))
        XCTAssertTrue(source.contains("availableNetworks: availableNetworks"))
    }

    func testScanningSectionHeaderHasRefreshButton() throws {
        let inspectorSource = try viewSource(named: "InspectorView.swift")
        let detailSource = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(inspectorSource.contains("Button(action: onRefreshNetworks)"))
        XCTAssertTrue(inspectorSource.contains("Image(systemName: \"arrow.clockwise\")"))
        XCTAssertTrue(inspectorSource.contains(".help(\"Refresh WiFi networks\")"))
        XCTAssertTrue(inspectorSource.contains(".accessibilityLabel(\"Refresh WiFi networks\")"))
        XCTAssertTrue(inspectorSource.contains("The app scans once at startup"))
        XCTAssertFalse(inspectorSource.contains("The scanner stays idle until"))
        XCTAssertTrue(detailSource.contains("onRefreshNetworks: onRefreshNetworks"))
    }

    func testFloorPlanActionsAppearBetweenMapAndStatusBar() throws {
        let source = try viewSource(named: "FloorDetailView.swift")
        let map = try XCTUnwrap(source.range(of: "FloorPlanView("))
        let actions = try XCTUnwrap(source.range(of: "FloorPlanActionsBar("))
        let status = try XCTUnwrap(source.range(of: "SignalStatusView("))

        XCTAssertLessThan(map.lowerBound, actions.lowerBound)
        XCTAssertLessThan(actions.lowerBound, status.lowerBound)
    }

    func testHeatmapControlsMoveFromInspectorIntoWrappingBottomBar() throws {
        let inspectorSource = try viewSource(named: "InspectorView.swift")
        let detailSource = try viewSource(named: "FloorDetailView.swift")

        XCTAssertFalse(inspectorSource.contains("Section(\"Heatmap\")"))
        XCTAssertFalse(inspectorSource.contains("@Binding var showHeatmap"))
        XCTAssertTrue(detailSource.contains("WrappingHStack("))
        XCTAssertTrue(detailSource.contains("showHeatmap: $document.survey.viewSettings.showHeatmap"))
    }

    func testBottomBarSeparatesFileActionsFromHeatmapControls() throws {
        let source = try viewSource(named: "FloorDetailView.swift")
        let exportButton = try XCTUnwrap(source.range(of: "Button(action: onExport)"))
        let separator = try XCTUnwrap(
            source.range(of: "Divider()", range: exportButton.lowerBound..<source.endIndex)
        )
        let heatmapToggle = try XCTUnwrap(
            source.range(of: "title: \"Show Heatmap\"", range: exportButton.lowerBound..<source.endIndex)
        )

        XCTAssertLessThan(exportButton.lowerBound, separator.lowerBound)
        XCTAssertLessThan(separator.lowerBound, heatmapToggle.lowerBound)
    }

    func testCalibrationMovesFromSidebarBelowImportFloorPlan() throws {
        let inspectorSource = try viewSource(named: "InspectorView.swift")
        let detailSource = try viewSource(named: "FloorDetailView.swift")
        let panelStart = try XCTUnwrap(detailSource.range(of: "private struct FloorPlanActionsPanel"))
        let panelSource = detailSource[panelStart.lowerBound...]
        let importButton = try XCTUnwrap(panelSource.range(of: "Button(action: onImport)"))
        let calibrateButton = try XCTUnwrap(panelSource.range(of: "                calibrationButton"))
        let exportButton = try XCTUnwrap(panelSource.range(of: "Button(action: onExport)"))

        XCTAssertFalse(inspectorSource.contains("Calibration Mode"))
        XCTAssertFalse(inspectorSource.contains("@Binding var isCalibrating"))
        XCTAssertTrue(panelSource.contains("Button(action: onCalibrate)"))
        XCTAssertTrue(panelSource.contains("Label(\"Calibrate Distance\", systemImage: \"ruler\")"))
        XCTAssertLessThan(importButton.lowerBound, calibrateButton.lowerBound)
        XCTAssertLessThan(calibrateButton.lowerBound, exportButton.lowerBound)
    }

    func testUncalibratedFloorUsesProminentBlueCalibrationButton() throws {
        let source = try viewSource(named: "FloorDetailView.swift")
        let panelStart = try XCTUnwrap(source.range(of: "private struct FloorPlanActionsPanel"))
        let panelSource = source[panelStart.lowerBound...]

        XCTAssertTrue(panelSource.contains("let isCalibrated: Bool"))
        XCTAssertTrue(panelSource.contains("if canCalibrate && !isCalibrated"))
        XCTAssertTrue(panelSource.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(panelSource.contains(".tint(.blue)"))
    }

    func testCalibrationButtonShowsNewUserInstructionsBeforeStarting() throws {
        let source = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(source.contains(".alert(\"Calibrate Distance\""))
        XCTAssertTrue(source.contains("Button(\"Cancel\", role: .cancel)"))
        XCTAssertTrue(source.contains("Button(\"OK\")"))
        XCTAssertTrue(source.contains(
            "Click two points on the floor plan that are a known distance apart. Then enter the real-world distance between them in meters."
        ))
        XCTAssertTrue(source.contains("isCalibrating = true"))
    }

    func testCompletedCalibrationReturnsToNormalMode() throws {
        let floorPlanSource = try viewSource(named: "FloorPlanView.swift")
        let detailSource = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(floorPlanSource.contains("let onCalibrationComplete: () -> Void"))
        XCTAssertTrue(floorPlanSource.contains("onCalibrationComplete()"))
        XCTAssertTrue(detailSource.contains("onCalibrationComplete: finishCalibration"))
        XCTAssertTrue(detailSource.contains("private func finishCalibration()"))
        XCTAssertTrue(detailSource.contains("isCalibrating = false"))
    }

    func testEscapeExitsCalibrationMode() throws {
        let source = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(source.contains(".onExitCommand(perform: handleExitCommand)"))
        XCTAssertTrue(source.contains("private func handleExitCommand()"))
        XCTAssertTrue(source.contains("exitCalibrationMode()"))
        XCTAssertTrue(source.contains("private func exitCalibrationMode()"))
        XCTAssertTrue(source.contains("isCalibrating = false"))
    }

    func testCalibrationButtonExitsAnActiveCalibration() throws {
        let source = try viewSource(named: "FloorDetailView.swift")
        let panelStart = try XCTUnwrap(source.range(of: "private struct FloorPlanActionsPanel"))
        let panelSource = source[panelStart.lowerBound...]

        XCTAssertTrue(source.contains("onCalibrate: handleCalibrationButton"))
        XCTAssertTrue(source.contains("private func handleCalibrationButton()"))
        XCTAssertTrue(source.contains("if isCalibrating"))
        XCTAssertTrue(source.contains("exitCalibrationMode()"))
        XCTAssertFalse(panelSource.contains(".disabled(!canCalibrate || isCalibrating)"))
        XCTAssertTrue(panelSource.contains(".disabled(!canCalibrate)"))
    }

    func testBottomBarUsesCompactStackedSelectorsAndFadeStepper() throws {
        let source = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(source.contains("CompactLabeledControl(\"Metric\")"))
        XCTAssertTrue(source.contains("CompactLabeledControl(\"Color Scheme\")"))
        XCTAssertTrue(source.contains("Stepper(value: $outerRadius"))
        XCTAssertFalse(source.contains("Slider(value: $outerRadius"))
    }

    func testHeatmapSelectorsAreLeadingAlignedWithinTheirPanel() throws {
        let source = try viewSource(named: "FloorDetailView.swift")
        let panelStart = try XCTUnwrap(source.range(of: "private struct HeatmapControlsPanel"))
        let panelEnd = try XCTUnwrap(
            source.range(of: "private struct ContourControlsPanel", range: panelStart.upperBound..<source.endIndex)
        )
        let panelSource = source[panelStart.lowerBound..<panelEnd.lowerBound]

        XCTAssertTrue(panelSource.contains("VStack(alignment: .leading, spacing: 8)"))
    }

    func testColorRangePlacesMinimumAndMaximumOnEitherSideOfSlider() throws {
        let source = try viewSource(named: "InspectorView.swift")
        let controlStart = try XCTUnwrap(source.range(of: "struct HeatmapRangeControl"))
        let bindingsStart = try XCTUnwrap(
            source.range(of: "private var lowerBinding", range: controlStart.upperBound..<source.endIndex)
        )
        let controlSource = source[controlStart.lowerBound..<bindingsStart.lowerBound]
        let minimum = try XCTUnwrap(controlSource.range(of: "TextField(\"Minimum\""))
        let slider = try XCTUnwrap(controlSource.range(of: "TwoSidedSlider("))
        let maximum = try XCTUnwrap(controlSource.range(of: "TextField(\"Maximum\""))

        XCTAssertLessThan(minimum.lowerBound, slider.lowerBound)
        XCTAssertLessThan(slider.lowerBound, maximum.lowerBound)
    }

    func testBottomBarUsesThreeOrderedControlPanels() throws {
        let source = try viewSource(named: "FloorDetailView.swift")
        let filePanel = try XCTUnwrap(source.range(of: "FloorPlanActionsPanel("))
        let heatmapPanel = try XCTUnwrap(source.range(of: "HeatmapControlsPanel("))
        let contourPanel = try XCTUnwrap(source.range(of: "ContourControlsPanel("))

        XCTAssertLessThan(filePanel.lowerBound, heatmapPanel.lowerBound)
        XCTAssertLessThan(heatmapPanel.lowerBound, contourPanel.lowerBound)
        XCTAssertTrue(source.contains("showsLeadingSeparator: true"))
    }

    func testHeatmapAndContourControlsAreWideLabeledButtons() throws {
        let source = try viewSource(named: "FloorDetailView.swift")

        XCTAssertTrue(source.contains("LayerToggleButton("))
        XCTAssertTrue(source.contains("title: \"Show Heatmap\""))
        XCTAssertTrue(source.contains("systemImage: \"map.fill\""))
        XCTAssertTrue(source.contains("accessibilityLabel: \"Heatmap\""))
        XCTAssertTrue(source.contains("title: \"Show Contours\""))
        XCTAssertTrue(source.contains("systemImage: \"waveform.path.ecg\""))
        XCTAssertTrue(source.contains("accessibilityLabel: \"Contours\""))
        XCTAssertTrue(source.contains("Label(title, systemImage: systemImage)"))
    }

    func testCompositeProducesCorrectSize() {
        let w = 400, h = 300
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue),
              let floorImg = ctx.makeImage() else {
            return XCTFail("Could not create test floor image")
        }
        let result = FloorDetailView.composeExportImage(floorImage: floorImg, heatmapImage: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, w)
        XCTAssertEqual(result?.height, h)
    }

    func testCompositeWithHeatmapIsNotNil() {
        let w = 100, h = 100
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue),
              let img = ctx.makeImage() else {
            return XCTFail("Could not create test image")
        }
        let result = FloorDetailView.composeExportImage(floorImage: img, heatmapImage: img)
        XCTAssertNotNil(result)
    }

    func testCompositeIncludesContourLayer() throws {
        let floor = try solidImage(width: 80, height: 60, red: 1, green: 1, blue: 1)
        let contours = try solidImage(width: 80, height: 60, red: 1, green: 0, blue: 0)

        let result = try XCTUnwrap(FloorDetailView.composeExportImage(
            floorImage: floor,
            heatmapImage: nil,
            contourImage: contours
        ))
        let pixel = rgba(result, x: 40, y: 30)

        XCTAssertGreaterThan(pixel.r, 240)
        XCTAssertGreaterThan(Int(pixel.r) - Int(pixel.g), 180)
        XCTAssertGreaterThan(Int(pixel.r) - Int(pixel.b), 180)
    }

    func testExportDrawsFloorNameAndLegendPanelsWithoutChangingImageSize() throws {
        let floor = try solidImage(width: 600, height: 400, red: 1, green: 1, blue: 1)
        let legend = ExportLegend(
            colorScheme: .classic,
            metric: .rssi,
            valueRange: HeatmapValueRange(lowerBound: -90, upperBound: -20)
        )

        let result = try XCTUnwrap(FloorDetailView.composeExportImage(
            floorImage: floor,
            heatmapImage: nil,
            contourImage: nil,
            floorName: "Ground Floor",
            legend: legend
        ))

        XCTAssertEqual(result.width, 600)
        XCTAssertEqual(result.height, 400)
        let titleBackground = rgba(result, x: 22, y: 22)
        let legendBackground = rgba(result, x: 22, y: 378)
        XCTAssertLessThan(titleBackground.r, 245)
        XCTAssertLessThan(legendBackground.r, 245)
    }

    private func solidImage(
        width: Int,
        height: Int,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return image
    }

    private func rgba(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(
            image,
            in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height)
        )
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    private func viewSource(named filename: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("WifiHeatmap/Views/\(filename)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func projectSource(named filename: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("WifiHeatmap/\(filename)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

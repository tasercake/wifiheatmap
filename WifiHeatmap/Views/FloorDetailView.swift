import SwiftUI
import ImageIO

struct BSSIDOption: Identifiable, Equatable {
    let ssid: String
    let bssid: String
    let band: WiFiBand?

    var id: String { bssid }
    var bandLabel: String { band?.displayName ?? "Unknown band" }
}

struct BSSIDOptionGroup: Identifiable, Equatable {
    let ssid: String
    let options: [BSSIDOption]

    var id: String { ssid }

    static func grouped(_ options: [BSSIDOption]) -> [BSSIDOptionGroup] {
        Dictionary(grouping: options, by: \.ssid)
            .map { ssid, options in
                BSSIDOptionGroup(
                    ssid: ssid,
                    options: options.sorted { lhs, rhs in
                        let lhsBand = lhs.band.flatMap(WiFiBand.allCases.firstIndex) ?? Int.max
                        let rhsBand = rhs.band.flatMap(WiFiBand.allCases.firstIndex) ?? Int.max
                        if lhsBand != rhsBand { return lhsBand < rhsBand }
                        return lhs.bssid.localizedStandardCompare(rhs.bssid) == .orderedAscending
                    }
                )
            }
            .sorted { $0.ssid.localizedStandardCompare($1.ssid) == .orderedAscending }
    }
}

struct FloorFilterOptions {
    private struct Entry {
        let ssid: String
        let bssid: String
        let band: WiFiBand
        let rssi: Int
    }

    private let entries: [Entry]
    private let defaultDisplaySSID: String?

    init(points: [SurveyPoint], latestBatch: [ScannedNetwork]) {
        let storedEntries = points.flatMap(\.readings).map {
            Entry(ssid: $0.ssid, bssid: $0.bssid, band: $0.band, rssi: $0.rssi)
        }
        let latestEntries = latestBatch.map {
            Entry(ssid: $0.ssid, bssid: $0.bssid, band: $0.band, rssi: $0.rssi)
        }
        entries = storedEntries + latestEntries
        defaultDisplaySSID = Self.strongestSSID(
            in: latestEntries.isEmpty ? storedEntries : latestEntries
        )
    }

    var displaySSIDs: [String] {
        Set(entries.map(\.ssid).filter { !$0.isEmpty }).sorted()
    }

    func resolvedDisplaySSID(_ selection: String?) -> String? {
        if let selection, displaySSIDs.contains(selection) {
            return selection
        }
        return defaultDisplaySSID
    }

    func displayBSSIDs(band: WiFiBand, ssid: String?) -> [String] {
        displayBSSIDOptions(band: band, ssid: ssid).map(\.bssid).sorted()
    }

    func displayBSSIDGroups(band: WiFiBand, ssid: String?) -> [BSSIDOptionGroup] {
        BSSIDOptionGroup.grouped(displayBSSIDOptions(band: band, ssid: ssid))
    }

    func effectiveDisplayBSSIDs(
        _ selection: Set<String>,
        band: WiFiBand,
        ssid: String?
    ) -> Set<String> {
        selection.intersection(displayBSSIDs(band: band, ssid: ssid))
    }

    func requiredBSSIDs(
        requiredSSIDs: Set<String>,
        trackedBands: Set<WiFiBand>
    ) -> [String] {
        requiredBSSIDOptions(
            requiredSSIDs: requiredSSIDs,
            trackedBands: trackedBands
        ).map(\.bssid).sorted()
    }

    func requiredBSSIDGroups(
        requiredSSIDs: Set<String>,
        trackedBands: Set<WiFiBand>,
        preserving selectedBSSIDs: Set<String>
    ) -> [BSSIDOptionGroup] {
        var options = requiredBSSIDOptions(
            requiredSSIDs: requiredSSIDs,
            trackedBands: trackedBands
        )
        let available = Set(options.map(\.bssid))
        for bssid in selectedBSSIDs.subtracting(available) {
            options.append(option(for: bssid) ?? BSSIDOption(
                ssid: "Unavailable",
                bssid: bssid,
                band: nil
            ))
        }
        return BSSIDOptionGroup.grouped(options)
    }

    private func displayBSSIDOptions(band: WiFiBand, ssid: String?) -> [BSSIDOption] {
        guard let ssid else { return [] }
        return bssidOptions {
            $0.band == band && $0.ssid == ssid
        }
    }

    private func requiredBSSIDOptions(
        requiredSSIDs: Set<String>,
        trackedBands _: Set<WiFiBand>
    ) -> [BSSIDOption] {
        bssidOptions {
            requiredSSIDs.isEmpty || requiredSSIDs.contains($0.ssid)
        }
    }

    private func option(for bssid: String) -> BSSIDOption? {
        guard let entry = entries.last(where: { $0.bssid == bssid }) else { return nil }
        return makeOption(from: entry)
    }

    private func bssidOptions(where include: (Entry) -> Bool) -> [BSSIDOption] {
        var optionsByBSSID: [String: BSSIDOption] = [:]
        for entry in entries where !entry.bssid.isEmpty && include(entry) {
            optionsByBSSID[entry.bssid] = makeOption(from: entry)
        }
        return Array(optionsByBSSID.values)
    }

    private func makeOption(from entry: Entry) -> BSSIDOption {
        BSSIDOption(
            ssid: entry.ssid.isEmpty ? "Hidden SSID" : entry.ssid,
            bssid: entry.bssid,
            band: entry.band
        )
    }

    private static func strongestSSID(in entries: [Entry]) -> String? {
        entries
            .filter { !$0.ssid.isEmpty }
            .max { lhs, rhs in
                if lhs.rssi != rhs.rssi {
                    return lhs.rssi < rhs.rssi
                }
                return lhs.ssid.localizedStandardCompare(rhs.ssid) == .orderedDescending
            }?
            .ssid
    }
}

struct SelectedPointMetadata: Equatable {
    struct Reading: Equatable {
        let ssid: String
        let bssid: String
        let band: WiFiBand
        let channel: Int
        let rssi: Int
        let noise: Int

        var snr: Int { rssi - noise }
    }

    let id: UUID
    let position: CGPoint
    let orientationDegrees: Double?
    let startedAt: Date
    let completedAt: Date
    let duration: TimeInterval
    let scanCacheUpdated: Bool
    let snapshotChanged: Bool?
    let attemptCount: Int
    let readings: [Reading]

    init(point: SurveyPoint, priorityFilter: SampleFilter? = nil) {
        id = point.id
        position = point.position
        orientationDegrees = point.orientationDegrees
        startedAt = point.startedAt
        completedAt = point.completedAt
        duration = point.duration
        scanCacheUpdated = point.scanCacheUpdated
        snapshotChanged = point.snapshotChanged
        attemptCount = point.attemptCount
        readings = point.readings
            .map {
                Reading(
                    ssid: $0.ssid,
                    bssid: $0.bssid,
                    band: $0.band,
                    channel: $0.channel,
                    rssi: $0.rssi,
                    noise: $0.noise
                )
            }
            .sorted { lhs, rhs in
                if let priorityFilter {
                    let lhsMatchesSSID = priorityFilter.ssid.map { lhs.ssid == $0 } ?? false
                    let rhsMatchesSSID = priorityFilter.ssid.map { rhs.ssid == $0 } ?? false
                    if lhsMatchesSSID != rhsMatchesSSID { return lhsMatchesSSID }

                    let lhsMatchesBand = lhs.band == priorityFilter.band
                    let rhsMatchesBand = rhs.band == priorityFilter.band
                    if lhsMatchesBand != rhsMatchesBand { return lhsMatchesBand }

                    if !priorityFilter.bssids.isEmpty {
                        let lhsMatchesBSSID = priorityFilter.bssids.contains(lhs.bssid)
                        let rhsMatchesBSSID = priorityFilter.bssids.contains(rhs.bssid)
                        if lhsMatchesBSSID != rhsMatchesBSSID { return lhsMatchesBSSID }
                    }
                }

                let lhsBand = WiFiBand.allCases.firstIndex(of: lhs.band) ?? Int.max
                let rhsBand = WiFiBand.allCases.firstIndex(of: rhs.band) ?? Int.max
                if lhsBand != rhsBand { return lhsBand < rhsBand }
                let ssidOrder = lhs.ssid.localizedStandardCompare(rhs.ssid)
                if ssidOrder != .orderedSame { return ssidOrder == .orderedAscending }
                return lhs.bssid.localizedStandardCompare(rhs.bssid) == .orderedAscending
            }
    }
}

struct PointCaptureSessionState: Equatable {
    private var activeID: UUID?

    @discardableResult
    mutating func begin(id: UUID = UUID()) -> UUID {
        activeID = id
        return id
    }

    func acceptsResult(for id: UUID) -> Bool {
        activeID == id
    }

    @discardableResult
    mutating func finish(id: UUID) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        return true
    }

    mutating func cancel() {
        activeID = nil
    }
}

enum ScanRequirementSummary {
    static func lines(
        requiredSSIDCount: Int,
        requiredBSSIDCount: Int,
        recordBands: Set<WiFiBand>
    ) -> [String] {
        let ssidRequirement = requiredSSIDCount == 0
            ? "Accept any network on a selected record band"
            : "Require \(requiredSSIDCount) \(requiredSSIDCount == 1 ? "SSID" : "SSIDs") on any selected record band"
        let bssidRequirement = requiredBSSIDCount == 0
            ? "No specific BSSIDs required"
            : "Require \(requiredBSSIDCount) \(requiredBSSIDCount == 1 ? "BSSID" : "BSSIDs")"
        return [ssidRequirement, bssidRequirement, recordBandText(recordBands)]
    }

    private static func recordBandText(_ recordBands: Set<WiFiBand>) -> String {
        let names = WiFiBand.allCases
            .filter(recordBands.contains)
            .map { $0.displayName.replacingOccurrences(of: " GHz", with: "") }
        guard !names.isEmpty else { return "Select at least one Record Band" }

        let joined: String
        switch names.count {
        case 1:
            joined = names[0]
        case 2:
            joined = names.joined(separator: " and ")
        default:
            joined = names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
        return "Record \(joined) GHz when available"
    }
}

struct RequiredSSIDRefreshGate {
    static let cooldown: TimeInterval = 60

    private var selectionWhenOpened: Set<String>?
    private var lastRefreshAt: Date?

    mutating func menuDidOpen(selection: Set<String>) {
        selectionWhenOpened = selection
    }

    mutating func menuDidClose(selection: Set<String>, at date: Date) -> TimeInterval? {
        guard let selectionWhenOpened else { return nil }
        self.selectionWhenOpened = nil
        guard selection != selectionWhenOpened else { return nil }
        guard let lastRefreshAt else { return 0 }
        return max(0, Self.cooldown - date.timeIntervalSince(lastRefreshAt))
    }

    mutating func didRefresh(at date: Date) {
        lastRefreshAt = date
    }
}

enum RequiredBSSIDOnboardingProgress {
    static func isConfigured(
        selection: Set<String>,
        automaticDefault: Set<String>?,
        hasClosedSelectionMenu: Bool,
        isSelectionMenuOpen: Bool
    ) -> Bool {
        guard !isSelectionMenuOpen else { return false }
        return hasClosedSelectionMenu
            || (!selection.isEmpty && selection != automaticDefault)
    }
}

struct FloorDetailView: View {
    @Environment(\.undoManager) var undoManager
    @ObservedObject var document: WifiSurveyDocument
    let floor: Binding<Floor>?

    var availableNetworks: [ScannedNetwork] = []
    var latestBatch: [ScannedNetwork] = []
    var latestScanAt: Date? = nil
    var isScanning: Bool = false
    var scanForReading: (Int) async throws -> ScanBatch
    @Binding var showInspector: Bool
    @ObservedObject var onboarding: OnboardingSessionState
    let defaultsRequiredBSSIDsToAll: Bool
    let onImportFirstFloorPlan: () -> Void
    let onOpenExistingSurvey: () -> Void
    let onRefreshNetworks: () -> Void

    @State private var isCalibrating = false
    @State private var isShowingCalibrationInstructions = false
    @State private var isDeleteMode: Bool = false
    @State private var measurementState: MeasurementState = .idle
    @State private var pendingPoint: PendingSurveyPoint?
    @State private var selectedPointID: UUID?
    @State private var pointAdditionCancellationToken = 0
    @State private var pointCaptureSession = PointCaptureSessionState()
    @State private var pointCaptureTask: Task<Void, Never>?
    @State private var isRequiredSSIDMenuPresented = false
    @State private var isRequiredBSSIDMenuPresented = false
    @State private var hasClosedRequiredBSSIDMenu = false
    @State private var requiredSSIDRefreshGate = RequiredSSIDRefreshGate()
    @State private var pendingRequiredSSIDRefresh: Task<Void, Never>?
    @State private var isWaitingForRequiredSSIDScan = false
    @State private var requiredSSIDScanRequestedAt: Date?
    @State private var hasCompletedRequiredSSIDScan = false
    @State private var defaultRequiredBSSIDSelection: Set<String>?

    private var settings: SurveyViewSettings {
        document.survey.viewSettings
    }

    private var selectedFloor: Floor? {
        floor?.wrappedValue
    }

    private var activeScanID: UUID? {
        guard let scanID = document.survey.activeScanID,
              document.survey.scanSets.contains(where: { $0.id == scanID })
        else { return nil }
        return scanID
    }

    private var activePoints: [SurveyPoint] {
        guard let activeScanID, let floorID = selectedFloor?.id else { return [] }
        return document.points(for: floorID, scanID: activeScanID)
    }

    private var selectedPoint: SurveyPoint? {
        guard let selectedPointID,
              let point = activePoints.first(where: { $0.id == selectedPointID }),
              !sampleFilter.apply(to: [point]).isEmpty
        else { return nil }
        return point
    }

    private var filterOptions: FloorFilterOptions {
        FloorFilterOptions(points: activePoints, latestBatch: availableNetworks)
    }

    private var resolvedDisplaySSID: String? {
        filterOptions.resolvedDisplaySSID(settings.displaySSID)
    }

    private var availableDisplayBSSIDs: [String] {
        filterOptions.displayBSSIDs(band: settings.displayBand, ssid: resolvedDisplaySSID)
    }

    private var availableDisplayBSSIDGroups: [BSSIDOptionGroup] {
        filterOptions.displayBSSIDGroups(
            band: settings.displayBand,
            ssid: resolvedDisplaySSID
        )
    }

    private var effectiveDisplayBSSIDs: Set<String> {
        filterOptions.effectiveDisplayBSSIDs(
            settings.displayBSSIDs,
            band: settings.displayBand,
            ssid: resolvedDisplaySSID
        )
    }

    private var displaySSIDBinding: Binding<String?> {
        Binding(
            get: { resolvedDisplaySSID },
            set: { selection in
                guard settings.displaySSID != selection else { return }
                document.survey.viewSettings.displaySSID = selection
                document.survey.viewSettings.displayBSSIDs = []
            }
        )
    }

    private var displayBSSIDsBinding: Binding<Set<String>> {
        Binding(
            get: { effectiveDisplayBSSIDs },
            set: { document.survey.viewSettings.displayBSSIDs = $0 }
        )
    }

    private var sampleFilter: SampleFilter {
        SampleFilter(
            band: settings.displayBand,
            ssid: resolvedDisplaySSID,
            bssids: effectiveDisplayBSSIDs
        )
    }

    private var heatmapValueRange: HeatmapValueRange {
        settings.valueRange(for: settings.metric)
    }

    private var availableSSIDs: [String] {
        var ssids = Set(filterOptions.displaySSIDs)
        ssids.formUnion(settings.requiredSSIDs)
        return ssids.sorted()
    }

    private var availableRequiredBSSIDGroups: [BSSIDOptionGroup] {
        filterOptions.requiredBSSIDGroups(
            requiredSSIDs: settings.requiredSSIDs,
            trackedBands: settings.trackedBands,
            preserving: settings.requiredBSSIDs
        )
    }

    private var latestSignal: ScannedNetwork? {
        guard let resolvedDisplaySSID else { return nil }
        return latestBatch
            .filter {
                $0.band == settings.displayBand
                    && $0.ssid == resolvedDisplaySSID
                    && (effectiveDisplayBSSIDs.isEmpty || effectiveDisplayBSSIDs.contains($0.bssid))
            }
            .max(by: { $0.rssi < $1.rssi })
    }

    private var knownBSSIDBands: [String: WiFiBand] {
        let scanReadings = document.survey.scanSets
            .flatMap(\.floors)
            .flatMap(\.points)
            .flatMap(\.readings)
        let legacyReadings = document.survey.floors
            .flatMap(\.points)
            .flatMap(\.readings)
        let stored = (scanReadings + legacyReadings).map { ($0.bssid, $0.band) }
        let recent = availableNetworks.map { ($0.bssid, $0.band) }
        return Dictionary(stored + recent, uniquingKeysWith: { _, newest in newest })
    }

    private var requiredRecordBands: Set<WiFiBand> {
        RecordBandPolicy.requiredBands(
            selectedBSSIDs: settings.requiredBSSIDs,
            knownBSSIDBands: knownBSSIDBands
        )
    }

    private var discoveredBands: Set<WiFiBand> {
        Set(availableNetworks.map(\.band))
    }

    private var lastTaggedAt: Date? {
        sampleFilter.apply(to: activePoints)
            .map(\.timestamp)
            .max()
    }

    private var onboardingContext: OnboardingContext {
        OnboardingContext(
            hasFloors: !document.survey.floors.isEmpty,
            selectedFloorHasPlan: selectedFloor.map {
                document.imageCache[$0.floorPlanFilename] != nil
            } ?? false,
            hasAnyCalibration: document.survey.floors.contains { $0.calibration != nil },
            hasRequiredSSIDs: !settings.requiredSSIDs.isEmpty,
            hasCompletedRequiredSSIDScan: hasCompletedRequiredSSIDScan,
            hasRequiredBSSIDs: RequiredBSSIDOnboardingProgress.isConfigured(
                selection: settings.requiredBSSIDs,
                automaticDefault: defaultRequiredBSSIDSelection,
                hasClosedSelectionMenu: hasClosedRequiredBSSIDMenu,
                isSelectionMenuOpen: isRequiredBSSIDMenuPresented
            ),
            hasAvailableBSSIDs: availableRequiredBSSIDGroups.contains { !$0.options.isEmpty },
            canCaptureOnSelectedFloor: selectedFloor?.calibration != nil
                && activeScanID != nil
                && !settings.trackedBands.isEmpty
                && !isScanning
                && !measurementState.isScanning,
            hasRecordedPoints: !activePoints.isEmpty,
            showsInspector: showInspector,
            isRequiredSSIDSelectionOpen: isRequiredSSIDMenuPresented,
            isRequiredBSSIDSelectionOpen: isRequiredBSSIDMenuPresented
        )
    }

    private var activeOnboardingTip: OnboardingTipID? {
        OnboardingFlow.nextTip(
            for: onboardingContext,
            dismissed: onboarding.dismissedTips
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                DisplayFiltersBar(
                    availableSSIDs: filterOptions.displaySSIDs,
                    availableBSSIDGroups: availableDisplayBSSIDGroups,
                    displayBand: $document.survey.viewSettings.displayBand,
                    displaySSID: displaySSIDBinding,
                    displayBSSIDs: displayBSSIDsBinding
                )

                Divider()

                if let floor {
                    FloorPlanView(
                        document: document,
                        floor: floor,
                        points: activePoints,
                        sampleFilter: sampleFilter,
                        showHeatmap: settings.showHeatmap,
                        showContours: settings.showContours,
                        contourSmoothingMeters: settings.contourSmoothingMeters,
                        colorScheme: settings.colorScheme,
                        metric: settings.metric,
                        valueRange: heatmapValueRange,
                        outerRadius: settings.fadeRadius,
                        isCalibrating: isCalibrating,
                        pendingPoint: $pendingPoint,
                        selectedPointID: $selectedPointID,
                        pointAdditionCancellationToken: pointAdditionCancellationToken,
                        isCaptureInProgress: measurementState.isScanning || isScanning,
                        onCaptureRequested: logReading,
                        onMovePoint: movePoint,
                        onSetPointOrientation: setPointOrientation,
                        onImport: importFloorPlan,
                        onCalibrationComplete: finishCalibration,
                        isDeleteMode: isDeleteMode,
                        onDelete: deleteReading
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onboardingTooltip(
                        tip: .capturePoint,
                        isPresented: activeOnboardingTip == .capturePoint,
                        onDismiss: { onboarding.dismiss(.capturePoint) }
                    )
                } else {
                    VStack(spacing: 12) {
                        Text("Import a floor plan to get started")
                            .foregroundStyle(.secondary)

                        Button(action: onImportFirstFloorPlan) {
                            Label("Import Floor Plan\u{2026}", systemImage: "photo")
                        }
                        .buttonStyle(.borderedProminent)
                        .onboardingTooltip(
                            tip: .importFloorPlan,
                            isPresented: activeOnboardingTip == .importFloorPlan,
                            onDismiss: { onboarding.dismiss(.importFloorPlan) }
                        )

                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(height: 1)
                            Text("OR")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(height: 1)
                        }
                        .frame(maxWidth: 280)
                        .padding(.vertical, 4)

                        Text("Open an existing scan")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button(action: onOpenExistingSurvey) {
                            Label("Choose .wifiheatmap File\u{2026}", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()

                FloorPlanActionsBar(
                    canExport: selectedFloor.map { document.imageCache[$0.floorPlanFilename] != nil } ?? false,
                    canCalibrate: selectedFloor.map {
                        document.imageCache[$0.floorPlanFilename] != nil
                    } ?? false,
                    isCalibrated: selectedFloor?.calibration != nil,
                    isCalibrating: isCalibrating,
                    showHeatmap: $document.survey.viewSettings.showHeatmap,
                    showContours: $document.survey.viewSettings.showContours,
                    contourSmoothingMeters: $document.survey.viewSettings.contourSmoothingMeters,
                    metric: $document.survey.viewSettings.metric,
                    colorScheme: $document.survey.viewSettings.colorScheme,
                    rssiRange: $document.survey.viewSettings.rssiRange,
                    snrRange: $document.survey.viewSettings.snrRange,
                    outerRadius: $document.survey.viewSettings.fadeRadius,
                    showsCalibrationTooltip: activeOnboardingTip == .calibrateDistance,
                    onDismissCalibrationTooltip: { onboarding.dismiss(.calibrateDistance) },
                    onImport: importFloorPlan,
                    onCalibrate: handleCalibrationButton,
                    onExport: exportFloorPlan
                )

                Divider()

                HStack(alignment: .top, spacing: 8) {
                    if let selectedPoint {
                        SelectedPointMetadataView(point: selectedPoint, priorityFilter: sampleFilter)
                            .frame(maxWidth: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                    SignalStatusView(
                        signal: latestSignal,
                        filter: sampleFilter,
                        latestScanAt: latestSignal == nil ? nil : latestScanAt,
                        lastTaggedAt: lastTaggedAt,
                        measurementState: measurementState,
                        hasActiveScan: activeScanID != nil
                    )
                }
                .padding(.horizontal, 8)
                .frame(height: BottomStatusBarLayout.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showInspector {
                Divider()
                InspectorView(
                    scanSets: document.survey.scanSets,
                    activeScanID: $document.survey.activeScanID,
                    isScanning: measurementState.isScanning || isScanning,
                    availableSSIDs: availableSSIDs,
                    requiredSSIDs: $document.survey.viewSettings.requiredSSIDs,
                    trackedBands: $document.survey.viewSettings.trackedBands,
                    discoveredBands: discoveredBands,
                    requiredRecordBands: requiredRecordBands,
                    availableBSSIDGroups: availableRequiredBSSIDGroups,
                    requiredBSSIDs: $document.survey.viewSettings.requiredBSSIDs,
                    defaultsRequiredBSSIDsToAll: defaultsRequiredBSSIDsToAll,
                    hasCompletedRequiredSSIDScan: hasCompletedRequiredSSIDScan,
                    onDefaultRequiredBSSIDsApplied: { selection in
                        defaultRequiredBSSIDSelection = selection
                    },
                    activeOnboardingTip: activeOnboardingTip,
                    onDismissOnboardingTip: onboarding.dismiss,
                    onRequiredSSIDMenuPresentationChanged: handleRequiredSSIDMenuPresentation,
                    onRequiredBSSIDMenuPresentationChanged: handleRequiredBSSIDMenuPresentation,
                    isDeleteMode: $isDeleteMode,
                    hasRecordedPoints: !activePoints.isEmpty,
                    onNewScan: createScan,
                    onRenameScan: renameActiveScan,
                    onDeleteScan: deleteScan,
                    onClearAll: clearAllPoints,
                    onRefreshNetworks: onRefreshNetworks
                )
                .frame(width: 260)
            }
        }
        .alert("Calibrate Distance", isPresented: $isShowingCalibrationInstructions) {
            Button("Cancel", role: .cancel) {}
            Button("OK") {
                isDeleteMode = false
                isCalibrating = true
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Click two points on the floor plan that are a known distance apart. Then enter the real-world distance between them in meters.")
        }
        .onAppear {
            normalizeRecordBands()
            onboarding.latchCompletedTips(for: onboardingContext)
        }
        .onChange(of: onboardingContext) {
            onboarding.latchCompletedTips(for: onboardingContext)
        }
        .onChange(of: document.survey.activeScanID) {
            pendingPoint = nil
            selectedPointID = nil
            measurementState = .idle
        }
        .onChange(of: latestScanAt) {
            handleLatestScanCompletion()
        }
        .onChange(of: isScanning) {
            if !isScanning {
                handleLatestScanCompletion()
            }
        }
        .onChange(of: settings.requiredBSSIDs) { normalizeRecordBands() }
        .onChange(of: knownBSSIDBands) { normalizeRecordBands() }
        .onExitCommand(perform: handleExitCommand)
        .focusedSceneValue(
            \.deleteSelectedPoint,
            selectedPoint.map { point in
                DeleteSelectedPointAction { deleteReading(id: point.id) }
            }
        )
    }

    private func handleRequiredSSIDMenuPresentation(_ isPresented: Bool) {
        if isPresented {
            requiredSSIDRefreshGate.menuDidOpen(selection: settings.requiredSSIDs)
            isRequiredSSIDMenuPresented = true
        } else {
            isRequiredSSIDMenuPresented = false
            guard let delay = requiredSSIDRefreshGate.menuDidClose(
                selection: settings.requiredSSIDs,
                at: Date()
            ) else { return }
            hasCompletedRequiredSSIDScan = false
            isWaitingForRequiredSSIDScan = true
            requiredSSIDScanRequestedAt = nil
            scheduleRequiredSSIDRefresh(after: delay)
        }
    }

    private func handleRequiredBSSIDMenuPresentation(_ isPresented: Bool) {
        isRequiredBSSIDMenuPresented = isPresented
        if !isPresented {
            hasClosedRequiredBSSIDMenu = true
        }
    }

    private func handleLatestScanCompletion() {
        guard !isScanning else { return }
        guard !settings.requiredSSIDs.isEmpty, let latestScanAt else { return }
        if isWaitingForRequiredSSIDScan {
            guard let requiredSSIDScanRequestedAt,
                  latestScanAt >= requiredSSIDScanRequestedAt else { return }
        }
        hasCompletedRequiredSSIDScan = true
        isWaitingForRequiredSSIDScan = false
        requiredSSIDScanRequestedAt = nil
    }

    private func normalizeRecordBands() {
        let normalized = RecordBandPolicy.normalizedRecordBands(
            settings.trackedBands,
            selectedBSSIDs: settings.requiredBSSIDs,
            knownBSSIDBands: knownBSSIDBands
        )
        guard normalized != settings.trackedBands else { return }
        document.survey.viewSettings.trackedBands = normalized
    }

    private func scheduleRequiredSSIDRefresh(after delay: TimeInterval) {
        pendingRequiredSSIDRefresh?.cancel()
        pendingRequiredSSIDRefresh = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            requiredSSIDScanRequestedAt = Date()
            requiredSSIDRefreshGate.didRefresh(at: Date())
            onRefreshNetworks()
        }
    }

    private func logReading(_ pendingPoint: PendingSurveyPoint) {
        guard let floor = selectedFloor else {
            self.pendingPoint = nil
            return
        }
        guard floor.calibration != nil else {
            self.pendingPoint = nil
            return
        }
        guard !measurementState.isScanning else { return }
        guard let activeScanID else {
            self.pendingPoint = nil
            measurementState = .failed("Create or select a scan before recording a point.")
            return
        }

        self.pendingPoint = pendingPoint
        let requirements = CaptureRequirements(
            requiredSSIDs: settings.requiredSSIDs,
            requiredBSSIDs: settings.requiredBSSIDs,
            requiredBSSIDBands: knownBSSIDBands.filter { settings.requiredBSSIDs.contains($0.key) },
            trackedBands: settings.trackedBands
        )
        measurementState = .scanning(attempt: 1, maxAttempts: PointCaptureCoordinator.maximumAttempts)
        let sessionID = pointCaptureSession.begin()

        pointCaptureTask = Task {
            do {
                let point = try await PointCaptureCoordinator.capture(
                    at: pendingPoint.position,
                    orientationDegrees: pendingPoint.orientationDegrees,
                    requirements: requirements,
                    scan: scanForReading,
                    onProgress: { progress in
                        guard pointCaptureSession.acceptsResult(for: sessionID) else { return }
                        switch progress {
                        case .scanning(let attempt, let maxAttempts):
                            measurementState = .scanning(attempt: attempt, maxAttempts: maxAttempts)
                        case .retrying(let reason, let nextAttempt, let maxAttempts, let delayNanoseconds):
                            measurementState = .retrying(
                                reason: reason,
                                nextAttempt: nextAttempt,
                                maxAttempts: maxAttempts,
                                retryAt: Date().addingTimeInterval(Double(delayNanoseconds) / 1_000_000_000)
                            )
                        }
                    }
                )
                guard !Task.isCancelled,
                      pointCaptureSession.acceptsResult(for: sessionID)
                else { return }
                var points = document.points(for: floor.id, scanID: activeScanID)
                let insertionIndex = points.endIndex
                points.append(point)
                guard document.replacePoints(points, for: floor.id, scanID: activeScanID) else {
                    throw PointStorageError.activeScanUnavailable
                }
                guard pointCaptureSession.finish(id: sessionID) else { return }
                pointCaptureTask = nil
                self.pendingPoint = nil
                selectedPointID = point.id
                measurementState = .recorded(point)

                PointUndo.registerUndoForInsertion(
                    point,
                    at: insertionIndex,
                    floorID: floor.id,
                    scanID: activeScanID,
                    document: document,
                    undoManager: undoManager,
                    actionName: "Log Point"
                )
            } catch is CancellationError {
                guard pointCaptureSession.finish(id: sessionID) else { return }
                pointCaptureTask = nil
                self.pendingPoint = nil
                measurementState = .idle
            } catch {
                guard pointCaptureSession.finish(id: sessionID) else { return }
                pointCaptureTask = nil
                self.pendingPoint = nil
                measurementState = .failed(error.localizedDescription)
            }
        }
    }

    private func handleExitCommand() {
        if measurementState.isScanning {
            cancelPointAddition()
        } else if pendingPoint != nil {
            pointAdditionCancellationToken &+= 1
            pendingPoint = nil
        } else {
            exitCalibrationMode()
        }
    }

    private func cancelPointAddition() {
        pointCaptureSession.cancel()
        pointCaptureTask?.cancel()
        pointCaptureTask = nil
        pendingPoint = nil
        measurementState = .idle
    }

    private func movePoint(id: UUID, to position: CGPoint) {
        updatePoint(id: id, actionName: "Move Point") { point in
            point.position = position
        }
    }

    private func setPointOrientation(id: UUID, to orientationDegrees: Double?) {
        updatePoint(id: id, actionName: "Rotate Point") { point in
            point.orientationDegrees = orientationDegrees.map(PointOrientation.normalized)
        }
    }

    private func updatePoint(
        id: UUID,
        actionName: String,
        edit: (inout SurveyPoint) -> Void
    ) {
        guard ExistingPointInteractionPolicy.isEnabled(
            isCalibrating: isCalibrating,
            isCaptureInProgress: measurementState.isScanning
        ) else { return }
        guard let floor = selectedFloor, let activeScanID else { return }
        var points = document.points(for: floor.id, scanID: activeScanID)
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }

        let original = points[index]
        edit(&points[index])
        guard points[index] != original else { return }
        guard document.replacePoints(points, for: floor.id, scanID: activeScanID) else { return }

        PointUndo.registerUndoForUpdate(
            original,
            floorID: floor.id,
            scanID: activeScanID,
            document: document,
            undoManager: undoManager,
            actionName: actionName
        )
    }

    private func deleteReading(id: UUID) {
        guard let floor = selectedFloor else { return }
        guard let activeScanID else { return }
        var points = document.points(for: floor.id, scanID: activeScanID)
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        let removed = points.remove(at: index)
        guard document.replacePoints(points, for: floor.id, scanID: activeScanID) else { return }
        if selectedPointID == id {
            selectedPointID = nil
        }
        PointUndo.registerUndoForRemoval(
            removed,
            at: index,
            floorID: floor.id,
            scanID: activeScanID,
            document: document,
            undoManager: undoManager,
            actionName: "Delete Point"
        )
    }

    private func clearAllPoints() {
        guard let floor = selectedFloor else { return }
        guard !measurementState.isScanning else { return }
        guard let activeScanID else { return }
        guard PointUndo.clearAllPoints(
            floorID: floor.id,
            scanID: activeScanID,
            document: document,
            undoManager: undoManager
        ) else { return }

        pendingPoint = nil
        selectedPointID = nil
        measurementState = .idle
    }

    private func createScan(named name: String) {
        guard !measurementState.isScanning else { return }
        guard document.addScan(name: name) != nil else { return }
        pendingPoint = nil
        selectedPointID = nil
        measurementState = .idle
    }

    private func renameActiveScan(to name: String) {
        guard let activeScanID else { return }
        _ = document.renameScan(id: activeScanID, to: name)
    }

    private func deleteScan(id: UUID) {
        guard !measurementState.isScanning else { return }
        guard document.deleteScan(id: id) else { return }
        pendingPoint = nil
        selectedPointID = nil
        measurementState = .idle
    }

    private func showCalibrationInstructions() {
        guard selectedFloor != nil else { return }
        isShowingCalibrationInstructions = true
    }

    private func handleCalibrationButton() {
        if isCalibrating {
            exitCalibrationMode()
        } else {
            showCalibrationInstructions()
        }
    }

    private func exitCalibrationMode() {
        guard isCalibrating else { return }
        isCalibrating = false
    }

    private func finishCalibration() {
        exitCalibrationMode()
    }

    private func importFloorPlan() {
        guard let floor = selectedFloor else {
            onImportFirstFloorPlan()
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Floor Plan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? document.importFloorPlan(url: url, for: floor.id)
    }

    // MARK: - Export

    nonisolated static func composeExportImage(
        floorImage: CGImage,
        heatmapImage: CGImage?,
        contourImage: CGImage? = nil,
        floorName: String? = nil,
        legend: ExportLegend? = nil
    ) -> CGImage? {
        let w = floorImage.width
        let h = floorImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        ctx.draw(floorImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let hm = heatmapImage {
            ctx.setAlpha(0.6)
            ctx.draw(hm, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        if let contours = contourImage {
            ctx.setAlpha(1)
            ctx.draw(contours, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.setAlpha(1)
        ExportOverlayRenderer.draw(
            floorName: floorName,
            legend: legend,
            canvasSize: CGSize(width: w, height: h),
            in: ctx
        )
        return ctx.makeImage()
    }

    private func exportFloorPlan() {
        guard let floor = selectedFloor else { return }
        guard let imageData = document.imageCache[floor.floorPlanFilename],
              let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let floorImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }

        let imgSize = CGSize(width: floorImg.width, height: floorImg.height)
        let samples = sampleFilter.apply(to: activePoints)
        let band    = settings.displayBand
        let radius  = settings.fadeRadius
        let met     = settings.metric
        let scheme  = settings.colorScheme
        let valueRange = heatmapValueRange
        let cal     = floor.calibration
        let includeHeatmap = settings.showHeatmap
        let includeContours = settings.showContours && met != .channel
        let contourSmoothing = settings.contourSmoothingMeters
        let floorName = floor.name

        Task.detached(priority: .userInitiated) {
            let heatmapImg: CGImage?
            let contourImg: CGImage?
            if (includeHeatmap || includeContours), let c = cal {
                let grid = IDWInterpolator.interpolate(
                    samples: samples, calibration: c,
                    band: band, imageSize: imgSize,
                    outerRadius: radius, metric: met
                )
                heatmapImg = includeHeatmap ? HeatmapRenderer.render(
                    grid: grid,
                    colorScheme: scheme,
                    metric: met,
                    valueRange: valueRange
                ) : nil
                contourImg = includeContours ? ContourRenderer.render(
                    grid: grid,
                    metric: met,
                    valueRange: valueRange,
                    calibration: c,
                    imageSize: imgSize,
                    smoothingMeters: contourSmoothing
                ) : nil
            } else {
                heatmapImg = nil
                contourImg = nil
            }
            let composite = Self.composeExportImage(
                floorImage: floorImg,
                heatmapImage: heatmapImg,
                contourImage: contourImg,
                floorName: floorName,
                legend: ExportLegend(
                    colorScheme: scheme,
                    metric: met,
                    valueRange: valueRange
                )
            )

            await MainActor.run {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.nameFieldStringValue = "\(floorName).png"
                panel.title = "Export Floor Plan"
                guard panel.runModal() == .OK, let url = panel.url,
                      let img = composite else { return }
                guard let dest = CGImageDestinationCreateWithURL(
                    url as CFURL, "public.png" as CFString, 1, nil
                ) else { return }
                CGImageDestinationAddImage(dest, img, nil)
                CGImageDestinationFinalize(dest)
            }
        }
    }
}

private struct FloorPlanActionsBar: View {
    let canExport: Bool
    let canCalibrate: Bool
    let isCalibrated: Bool
    let isCalibrating: Bool
    @Binding var showHeatmap: Bool
    @Binding var showContours: Bool
    @Binding var contourSmoothingMeters: Double
    @Binding var metric: HeatmapMetric
    @Binding var colorScheme: HeatmapColorScheme
    @Binding var rssiRange: HeatmapValueRange
    @Binding var snrRange: HeatmapValueRange
    @Binding var outerRadius: Double
    let showsCalibrationTooltip: Bool
    let onDismissCalibrationTooltip: () -> Void
    let onImport: () -> Void
    let onCalibrate: () -> Void
    let onExport: () -> Void

    var body: some View {
        WrappingHStack(horizontalSpacing: 0, verticalSpacing: 8) {
            FloorPlanActionsPanel(
                canExport: canExport,
                canCalibrate: canCalibrate,
                isCalibrated: isCalibrated,
                isCalibrating: isCalibrating,
                showsCalibrationTooltip: showsCalibrationTooltip,
                onDismissCalibrationTooltip: onDismissCalibrationTooltip,
                onImport: onImport,
                onCalibrate: onCalibrate,
                onExport: onExport
            )

            HeatmapControlsPanel(
                showsLeadingSeparator: false,
                showHeatmap: $showHeatmap,
                showContours: showContours,
                metric: $metric,
                colorScheme: $colorScheme,
                rssiRange: $rssiRange,
                snrRange: $snrRange,
                outerRadius: $outerRadius
            )

            ContourControlsPanel(
                showsLeadingSeparator: true,
                showContours: $showContours,
                contourSmoothingMeters: $contourSmoothingMeters,
                metric: metric
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct FloorPlanActionsPanel: View {
    let canExport: Bool
    let canCalibrate: Bool
    let isCalibrated: Bool
    let isCalibrating: Bool
    let showsCalibrationTooltip: Bool
    let onDismissCalibrationTooltip: () -> Void
    let onImport: () -> Void
    let onCalibrate: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                Spacer(minLength: 0)

                Button(action: onImport) {
                    Label("Import Floor Plan\u{2026}", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .help("Load a PNG, JPEG, or PDF floor plan into the current floor.")

                calibrationButton

                Button(action: onExport) {
                    Label("Export as PNG\u{2026}", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canExport)
                .help("Export the floor plan with the visible heatmap and contours as a PNG.")

                Spacer(minLength: 0)
            }
            .frame(width: 170)
            .frame(minHeight: 192)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .padding(.vertical, 8)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var calibrationButton: some View {
        if canCalibrate && !isCalibrated {
            calibrationActionButton
                .buttonStyle(.borderedProminent)
                .tint(.blue)
        } else {
            calibrationActionButton
        }
    }

    private var calibrationActionButton: some View {
        Button(action: onCalibrate) {
            Label("Calibrate Distance", systemImage: "ruler")
                .frame(maxWidth: .infinity)
        }
        .disabled(!canCalibrate)
        .help("Set the floor plan scale using two points a known distance apart.")
        .onboardingTooltip(
            tip: .calibrateDistance,
            isPresented: showsCalibrationTooltip,
            onDismiss: onDismissCalibrationTooltip
        )
    }
}

private struct HeatmapControlsPanel: View {
    let showsLeadingSeparator: Bool
    @Binding var showHeatmap: Bool
    let showContours: Bool
    @Binding var metric: HeatmapMetric
    @Binding var colorScheme: HeatmapColorScheme
    @Binding var rssiRange: HeatmapValueRange
    @Binding var snrRange: HeatmapValueRange
    @Binding var outerRadius: Double

    private var controlsDisabled: Bool {
        !showHeatmap && !showContours
    }

    var body: some View {
        BottomBarPanel(showsLeadingSeparator: showsLeadingSeparator) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        CompactLabeledControl("Metric") {
                            Picker("Metric", selection: $metric) {
                                ForEach(HeatmapMetric.allCases, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 124)
                        }

                        CompactLabeledControl("Color Scheme") {
                            Picker("Color Scheme", selection: $colorScheme) {
                                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                                    Text(scheme.displayName).tag(scheme)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 124)
                        }
                    }

                    CompactLabeledControl("Fade Radius") {
                        Stepper(value: $outerRadius, in: IDWInterpolator.innerRadiusMeters...30, step: 0.5) {
                            Text("\(outerRadius, specifier: "%.1f") m")
                                .frame(width: 48, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .disabled(controlsDisabled)

                if metric != .channel {
                    HeatmapRangeControl(
                        range: metric == .rssi ? $rssiRange : $snrRange,
                        metric: metric
                    )
                    .frame(width: 280)
                    .disabled(controlsDisabled)
                }

                LayerToggleButton(
                    title: "Show Heatmap",
                    systemImage: "map.fill",
                    accessibilityLabel: "Heatmap",
                    isOn: $showHeatmap
                )
                .frame(maxWidth: .infinity)
                .help("Show or hide the heatmap layer.")
            }
            .frame(width: 280)
            .frame(minHeight: 192)
        }
    }
}

private struct ContourControlsPanel: View {
    let showsLeadingSeparator: Bool
    @Binding var showContours: Bool
    @Binding var contourSmoothingMeters: Double
    let metric: HeatmapMetric

    var body: some View {
        BottomBarPanel(showsLeadingSeparator: showsLeadingSeparator) {
            VStack(spacing: 12) {
                Spacer(minLength: 0)

                CompactLabeledControl("Smoothing") {
                    HStack(spacing: 5) {
                        Slider(value: $contourSmoothingMeters, in: 0...3, step: 0.25)
                            .frame(width: 205)
                        Text(contourSmoothingMeters == 0
                             ? "Off"
                             : "\(contourSmoothingMeters, specifier: "%.2g") m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
                .disabled(!showContours || metric == .channel)
                .help("Smooth contour lines to reduce point-scale bumps.")

                Spacer(minLength: 0)

                LayerToggleButton(
                    title: "Show Contours",
                    systemImage: "waveform.path.ecg",
                    accessibilityLabel: "Contours",
                    isOn: $showContours
                )
                .frame(maxWidth: .infinity)
                .disabled(metric == .channel)
                .help("Show or hide labeled 10 dB contour lines.")
            }
            .frame(width: 270)
            .frame(minHeight: 192)
        }
    }
}

private struct BottomBarPanel<Content: View>: View {
    let showsLeadingSeparator: Bool
    let content: Content

    init(showsLeadingSeparator: Bool, @ViewBuilder content: () -> Content) {
        self.showsLeadingSeparator = showsLeadingSeparator
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsLeadingSeparator {
                Divider()
                    .padding(.vertical, 8)
            }
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct LayerToggleButton: View {
    let title: String
    let systemImage: String
    let accessibilityLabel: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .tint(isOn ? .accentColor : .secondary)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct CompactLabeledControl<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        makeLayout(maxWidth: proposal.width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = makeLayout(maxWidth: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func makeLayout(
        maxWidth proposedWidth: CGFloat?,
        subviews: Subviews
    ) -> (size: CGSize, frames: [CGRect]) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = sizes.reduce(0) { $0 + $1.width }
            + horizontalSpacing * CGFloat(max(sizes.count - 1, 0))
        let maxWidth = max(proposedWidth ?? naturalWidth, 1)

        var rows: [[Int]] = []
        var rowWidths: [CGFloat] = []
        var rowHeights: [CGFloat] = []
        var currentRow: [Int] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            let candidateWidth = currentRow.isEmpty
                ? size.width
                : currentWidth + horizontalSpacing + size.width
            if !currentRow.isEmpty && candidateWidth > maxWidth {
                rows.append(currentRow)
                rowWidths.append(currentWidth)
                rowHeights.append(currentHeight)
                currentRow = []
                currentWidth = 0
                currentHeight = 0
            }

            currentWidth = currentRow.isEmpty
                ? size.width
                : currentWidth + horizontalSpacing + size.width
            currentHeight = max(currentHeight, size.height)
            currentRow.append(index)
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
            rowWidths.append(currentWidth)
            rowHeights.append(currentHeight)
        }

        var frames = Array(repeating: CGRect.zero, count: sizes.count)
        var y: CGFloat = 0
        for rowIndex in rows.indices {
            var x: CGFloat = 0
            let rowHeight = rowHeights[rowIndex]
            for itemIndex in rows[rowIndex] {
                let size = sizes[itemIndex]
                frames[itemIndex] = CGRect(
                    x: x,
                    y: y + (rowHeight - size.height) / 2,
                    width: size.width,
                    height: size.height
                )
                x += size.width + horizontalSpacing
            }
            y += rowHeight
            if rowIndex < rows.index(before: rows.endIndex) {
                y += verticalSpacing
            }
        }

        return (
            CGSize(width: min(rowWidths.max() ?? 0, maxWidth), height: y),
            frames
        )
    }
}

private struct DisplayFiltersBar: View {
    let availableSSIDs: [String]
    let availableBSSIDGroups: [BSSIDOptionGroup]
    @Binding var displayBand: WiFiBand
    @Binding var displaySSID: String?
    @Binding var displayBSSIDs: Set<String>

    var body: some View {
        HStack(spacing: 10) {
            Label("Display", systemImage: "eye")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Band", selection: $displayBand) {
                ForEach(WiFiBand.allCases, id: \.self) { band in
                    Text(band.displayName).tag(band)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            .help("Show readings from one WiFi band. This does not change scan requirements.")

            Divider()
                .frame(height: 20)

            Text("SSID")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("SSID", selection: $displaySSID) {
                if availableSSIDs.isEmpty {
                    Text("No networks").tag(String?.none)
                } else {
                    ForEach(availableSSIDs, id: \.self) { ssid in
                        Text(ssid).tag(Optional(ssid))
                    }
                }
            }
            .labelsHidden()
            .frame(minWidth: 120, maxWidth: 220)
            .disabled(availableSSIDs.isEmpty)
            .help("Show exactly one network on the map, heatmap, contours, signal card, and exported PNG.")

            Text("BSSIDs")
                .font(.caption)
                .foregroundStyle(.secondary)
            GroupedBSSIDSelectionMenu(
                allLabel: "All BSSIDs",
                groups: availableBSSIDGroups,
                showsBand: false,
                selection: $displayBSSIDs,
                onPresentationChanged: { _ in }
            )
            .frame(minWidth: 100, maxWidth: 220)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(displaySSID == nil || availableBSSIDGroups.isEmpty)
            .help("Choose one or more BSSIDs to display. All BSSIDs uses the strongest matching BSSID at each recorded point.")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(.bar)
    }
}

private enum PointStorageError: LocalizedError {
    case activeScanUnavailable

    var errorDescription: String? {
        "The selected scan is no longer available, so no point was added."
    }
}

enum PointUndo {
    static func registerUndoForUpdate(
        _ replacement: SurveyPoint,
        floorID: UUID,
        scanID: UUID,
        document: WifiSurveyDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: document) { document in
            var points = document.points(for: floorID, scanID: scanID)
            guard let index = points.firstIndex(where: { $0.id == replacement.id }) else { return }
            let current = points[index]
            points[index] = replacement
            guard document.replacePoints(points, for: floorID, scanID: scanID) else { return }
            registerUndoForUpdate(
                current,
                floorID: floorID,
                scanID: scanID,
                document: document,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }

    @discardableResult
    static func clearAllPoints(
        floorID: UUID,
        scanID: UUID,
        document: WifiSurveyDocument,
        undoManager: UndoManager?
    ) -> Bool {
        let removedPoints = document.points(for: floorID, scanID: scanID)
        guard !removedPoints.isEmpty else { return false }
        guard document.replacePoints([], for: floorID, scanID: scanID) else { return false }

        registerUndoForReplacement(
            removedPoints,
            floorID: floorID,
            scanID: scanID,
            document: document,
            undoManager: undoManager,
            actionName: "Clear All Points"
        )
        return true
    }

    static func registerUndoForInsertion(
        _ point: SurveyPoint,
        at index: Int,
        floorID: UUID,
        scanID: UUID,
        document: WifiSurveyDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: document) { document in
            var points = document.points(for: floorID, scanID: scanID)
            guard let pointIndex = points.firstIndex(where: { $0.id == point.id }) else { return }

            points.remove(at: pointIndex)
            guard document.replacePoints(points, for: floorID, scanID: scanID) else { return }
            registerUndoForRemoval(
                point,
                at: index,
                floorID: floorID,
                scanID: scanID,
                document: document,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }

    static func registerUndoForRemoval(
        _ point: SurveyPoint,
        at index: Int,
        floorID: UUID,
        scanID: UUID,
        document: WifiSurveyDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: document) { document in
            var points = document.points(for: floorID, scanID: scanID)
            let restoredIndex = min(index, points.endIndex)
            points.insert(point, at: restoredIndex)
            guard document.replacePoints(points, for: floorID, scanID: scanID) else { return }
            registerUndoForInsertion(
                point,
                at: restoredIndex,
                floorID: floorID,
                scanID: scanID,
                document: document,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }

    private static func registerUndoForReplacement(
        _ replacement: [SurveyPoint],
        floorID: UUID,
        scanID: UUID,
        document: WifiSurveyDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: document) { document in
            let currentPoints = document.points(for: floorID, scanID: scanID)
            guard document.replacePoints(replacement, for: floorID, scanID: scanID) else { return }
            registerUndoForReplacement(
                currentPoints,
                floorID: floorID,
                scanID: scanID,
                document: document,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }
}

enum BottomStatusBarLayout {
    static let height: CGFloat = 112
    static let statusCardWidth: CGFloat = 440
    static let statusCardHeight: CGFloat = 96
}

private struct SelectedPointMetadataView: View {
    let metadata: SelectedPointMetadata

    init(point: SurveyPoint, priorityFilter: SampleFilter) {
        metadata = SelectedPointMetadata(point: point, priorityFilter: priorityFilter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            readingsGrid
            Divider()
            captureMetadata
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(
            maxWidth: .infinity,
            minHeight: BottomStatusBarLayout.statusCardHeight,
            maxHeight: BottomStatusBarLayout.statusCardHeight,
            alignment: .topLeading
        )
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(0.2))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected survey point details")
    }

    private var captureMetadata: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                PointMetadataItem(
                    label: "Position",
                    value: String(format: "x %.1f, y %.1f px", metadata.position.x, metadata.position.y)
                )
                PointMetadataItem(
                    label: "Direction",
                    value: metadata.orientationDegrees.map { String(format: "%.1f\u{00B0}", $0) } ?? "Not set"
                )
                PointMetadataItem(
                    label: "Started",
                    value: metadata.startedAt.formatted(date: .abbreviated, time: .standard)
                )
                PointMetadataItem(
                    label: "Completed",
                    value: metadata.completedAt.formatted(date: .abbreviated, time: .standard)
                )
                PointMetadataItem(label: "Duration", value: String(format: "%.2f s", metadata.duration))
                PointMetadataItem(label: "Attempts", value: "\(metadata.attemptCount)")
                PointMetadataItem(
                    label: "Cache update",
                    value: metadata.scanCacheUpdated ? "Observed" : "Not observed"
                )
                PointMetadataItem(label: "Snapshot", value: snapshotDescription)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var readingsGrid: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    GridRow {
                        Text("SSID")
                        Text("BSSID")
                        Text("Band")
                        Text("Channel")
                        Text("RSSI")
                        Text("Noise")
                        Text("SNR")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(Array(metadata.readings.enumerated()), id: \.offset) { _, reading in
                        GridRow {
                            Text(reading.ssid.isEmpty ? "Hidden SSID" : reading.ssid)
                            Text(reading.bssid)
                                .monospaced()
                            Text(reading.band.displayName)
                            Text("\(reading.channel)")
                                .monospacedDigit()
                            Text("\(reading.rssi) dBm")
                                .monospacedDigit()
                            Text("\(reading.noise) dBm")
                                .monospacedDigit()
                            Text("\(reading.snr) dB")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: proxy.size.width, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var snapshotDescription: String {
        switch metadata.snapshotChanged {
        case true: return "Changed"
        case false: return "Unchanged"
        case nil: return "Unknown"
        }
    }
}

private struct PointMetadataItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }
}

private enum MeasurementState {
    case idle
    case scanning(attempt: Int, maxAttempts: Int)
    case retrying(reason: CaptureRetryReason, nextAttempt: Int, maxAttempts: Int, retryAt: Date)
    case recorded(SurveyPoint)
    case failed(String)

    var isScanning: Bool {
        switch self {
        case .scanning, .retrying: return true
        case .idle, .recorded, .failed: return false
        }
    }
}

private struct SignalStatusView: View {
    let signal: ScannedNetwork?
    let filter: SampleFilter
    let latestScanAt: Date?
    let lastTaggedAt: Date?
    let measurementState: MeasurementState
    let hasActiveScan: Bool

    private var status: SignalUpdateStatus {
        SignalUpdateStatus(latestScanAt: latestScanAt, lastTaggedAt: lastTaggedAt)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 5) {
                    if measurementState.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                    }
                    Text(statusTitle)
                        .fontWeight(.medium)
                }

                switch measurementState {
                case .scanning(let attempt, let maxAttempts):
                    Text("Attempt \(attempt) of \(maxAttempts)")
                        .foregroundStyle(.secondary)
                    Text("Points will be added after the scan completes")
                        .foregroundStyle(.secondary)
                case .retrying(let reason, let nextAttempt, let maxAttempts, let retryAt):
                    let secondsRemaining = RetryCountdown.secondsRemaining(
                        until: retryAt,
                        at: context.date
                    )
                    Text(reason.message)
                        .foregroundStyle(.orange)
                    Text("Retrying in \(secondsRemaining)s · attempt \(nextAttempt) of \(maxAttempts)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.secondary)
                    Text("No points were added")
                        .foregroundStyle(.red)
                case .recorded(let point):
                    if let sample = filter.apply(to: [point]).first {
                        Text("\(sample.rssi) dBm \u{00B7} \(sample.ssid) \u{00B7} \(sample.band.displayName)")
                            .foregroundStyle(.primary)
                    } else {
                        Text("No recorded reading matches the current filters")
                            .foregroundStyle(.secondary)
                    }
                    Text("\(SignalUpdateStatus(latestScanAt: point.completedAt, lastTaggedAt: nil).updatedText(at: context.date)) \u{00B7} \(point.duration, specifier: "%.1f")s \u{00B7} \(point.scanCacheUpdated ? "cache updated" : "no cache-update event")")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    if point.attemptCount > 1 {
                        Text("Completed after \(point.attemptCount) scan attempts")
                            .foregroundStyle(.secondary)
                    }
                case .idle:
                    if !hasActiveScan {
                        Text("Use New Scan in the sidebar, or select an existing scan")
                            .foregroundStyle(.secondary)
                    } else if let signal {
                        Text("\(signal.rssi) dBm \u{00B7} \(signal.ssid) \u{00B7} \(filter.band.displayName)")
                            .foregroundStyle(.primary)
                    } else {
                        Text("No signal on \(filter.band.displayName)")
                            .foregroundStyle(.secondary)
                    }

                    if hasActiveScan {
                        Text(status.updatedText(at: context.date))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .font(.caption)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(
                width: BottomStatusBarLayout.statusCardWidth,
                height: BottomStatusBarLayout.statusCardHeight,
                alignment: .topTrailing
            )
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.2))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var statusTitle: String {
        switch measurementState {
        case .scanning: return "Scanning\u{2026}"
        case .retrying: return "Retrying scan\u{2026}"
        case .recorded(let point):
            let networkLabel = point.readings.count == 1 ? "network" : "networks"
            let bandLabel = point.bandCount == 1 ? "band" : "bands"
            return "New CoreWLAN scan completed \u{00B7} \(point.readings.count) \(networkLabel) \u{00B7} \(point.bandCount) \(bandLabel)"
        case .failed: return "Scan unsuccessful"
        case .idle: return hasActiveScan ? "Tap map to scan and record" : "No scan selected"
        }
    }

    private var statusIcon: String {
        switch measurementState {
        case .recorded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle, .scanning, .retrying: break
        }

        switch status.freshness {
        case .noSignal: return "antenna.radiowaves.left.and.right.slash"
        case .readyToLog: return "checkmark.circle.fill"
        case .waitingForNewScan: return "clock.arrow.circlepath"
        case .freshScanAvailable: return "sparkles"
        }
    }

    private var statusColor: Color {
        switch measurementState {
        case .recorded: return .green
        case .failed: return .red
        case .idle, .scanning, .retrying: break
        }

        switch status.freshness {
        case .noSignal: return .secondary
        case .readyToLog, .freshScanAvailable: return .green
        case .waitingForNewScan: return .orange
        }
    }
}

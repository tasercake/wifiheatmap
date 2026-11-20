import SwiftUI
import AppKit

struct RequiredBSSIDSelectionInitializer {
    private var hasFinished = false

    mutating func selectionToApply(
        defaultsToAll: Bool,
        hasRequiredSSIDs: Bool,
        hasCompletedRequiredSSIDScan: Bool,
        groups: [BSSIDOptionGroup],
        currentSelection: Set<String>,
        recordBands: Set<WiFiBand> = Set(WiFiBand.allCases)
    ) -> Set<String>? {
        guard !hasFinished else { return nil }
        guard defaultsToAll else {
            hasFinished = true
            return nil
        }
        guard currentSelection.isEmpty else {
            hasFinished = true
            return nil
        }
        guard hasRequiredSSIDs else { return nil }
        guard hasCompletedRequiredSSIDScan else { return nil }

        let availableBSSIDs = Set(groups
            .flatMap(\.options)
            .filter { option in
                guard let band = option.band else { return false }
                return recordBands.contains(band)
            }
            .map(\.bssid))
        guard !availableBSSIDs.isEmpty else { return nil }
        hasFinished = true
        return availableBSSIDs
    }
}

struct InspectorView: View {
    @State private var isConfirmingClearAll = false
    @State private var isConfirmingDeleteScan = false
    @State private var isCreatingScan = false
    @State private var isRenamingScan = false
    @State private var newScanName = ""
    @State private var scanName = ""
    @State private var scanPendingDeletion: ScanSet?
    @State private var requiredBSSIDSelectionInitializer = RequiredBSSIDSelectionInitializer()
    @FocusState private var isScanNameFocused: Bool

    // Scanning
    let scanSets: [ScanSet]
    @Binding var activeScanID: UUID?
    let isScanning: Bool
    let availableSSIDs: [String]
    @Binding var requiredSSIDs: Set<String>
    @Binding var trackedBands: Set<WiFiBand>
    let discoveredBands: Set<WiFiBand>
    let requiredRecordBands: Set<WiFiBand>
    let availableBSSIDGroups: [BSSIDOptionGroup]
    @Binding var requiredBSSIDs: Set<String>
    let defaultsRequiredBSSIDsToAll: Bool
    let hasCompletedRequiredSSIDScan: Bool
    let onDefaultRequiredBSSIDsApplied: (Set<String>) -> Void
    let activeOnboardingTip: OnboardingTipID?
    let onDismissOnboardingTip: (OnboardingTipID) -> Void
    let onRequiredSSIDMenuPresentationChanged: (Bool) -> Void
    let onRequiredBSSIDMenuPresentationChanged: (Bool) -> Void

    // Survey modes
    @Binding var isDeleteMode: Bool
    let hasRecordedPoints: Bool

    // Callbacks
    let onNewScan: (String) -> Void
    let onRenameScan: (String) -> Void
    let onDeleteScan: (UUID) -> Void
    let onClearAll: () -> Void
    let onRefreshNetworks: () -> Void

    private var activeScan: ScanSet? {
        guard let activeScanID else { return nil }
        return scanSets.first { $0.id == activeScanID }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scan")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        if isRenamingScan {
                            TextField("Scan name", text: $scanName)
                                .textFieldStyle(.roundedBorder)
                                .focused($isScanNameFocused)
                                .onSubmit(finishRenamingScan)
                                .onExitCommand(perform: cancelRenamingScan)
                                .frame(maxWidth: .infinity)

                            Button(action: finishRenamingScan) {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(.borderless)
                            .disabled(scanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Save scan name")
                            .accessibilityLabel("Save scan name")

                            Button(action: cancelRenamingScan) {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .help("Cancel renaming")
                            .accessibilityLabel("Cancel renaming")
                        } else {
                            FullWidthScanPicker(
                                scanSets: scanSets,
                                activeScanID: $activeScanID,
                                isEnabled: !isScanning,
                                onNewScan: beginCreatingScan
                            )
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1)
                            .help("Choose which scan set to record into and display. Floor plans and calibration are shared by every scan.")

                            Button(action: beginCreatingScan) {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                            .disabled(isScanning)
                            .help("New scan")
                            .accessibilityLabel("New scan")

                            Button(action: beginRenamingScan) {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .disabled(activeScan == nil || isScanning)
                            .help("Rename scan")
                            .accessibilityLabel("Rename scan")

                            Button(role: .destructive, action: beginDeletingScan) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(activeScan == nil || isScanning)
                            .help("Delete scan")
                            .accessibilityLabel("Delete scan")
                        }
                    }
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: isScanning
                              ? "antenna.radiowaves.left.and.right"
                              : "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(isScanning ? .green : .secondary)
                        Text(isScanning ? "Scanning\u{2026}" : "Idle")
                            .foregroundStyle(isScanning ? .primary : .secondary)
                    }
                }
                .help("The app scans once at startup. Use Refresh or tap the calibrated floor plan to scan again. Required SSIDs and BSSIDs define when a point-capture scan is complete; Record Bands choose which available readings are saved. The header above the map controls what is displayed.")

                LabeledContent("Record Bands") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(WiFiBand.allCases, id: \.self) { band in
                            HStack(spacing: 5) {
                                Toggle(band.displayName, isOn: trackedBandBinding(band))
                                    .toggleStyle(.checkbox)
                                    .disabled(
                                        isScanning
                                            || trackedBands == [band]
                                            || requiredRecordBands.contains(band)
                                    )
                                    .accessibilityHint(recordBandHelp(for: band))

                                Spacer(minLength: 4)

                                if requiredRecordBands.contains(band) {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Required by a selected BSSID")
                                }

                                Text(discoveredBands.contains(band) ? "Detected" : "Not observed")
                                    .font(.caption2)
                                    .foregroundStyle(discoveredBands.contains(band) ? .green : .secondary)
                                    .accessibilityLabel(discoveredBands.contains(band)
                                                        ? "Detected in the latest scan"
                                                        : "Not observed in the latest scan")
                            }
                            .help(recordBandHelp(for: band))
                        }
                    }
                }
                .help("Choose which bands to save when readings are available. A band does not have to be observed for a scan to succeed. At least one band remains enabled; existing points are unchanged.")

                LabeledContent("Required SSIDs") {
                    MultiSelectionMenu(
                        emptySelectionLabel: "Select SSID(s)...",
                        showsClearSelectionOption: false,
                        options: availableSSIDs,
                        selection: $requiredSSIDs,
                        onPresentationChanged: onRequiredSSIDMenuPresentationChanged
                    )
                }
                .disabled(isScanning)
                .help("Every selected SSID must appear on at least one selected Record Band before a scan is accepted. It does not need to appear on every band. Leave the selection empty to accept any network on a selected Record Band.")
                .onboardingTooltip(
                    tip: .requiredSSIDs,
                    isPresented: activeOnboardingTip == .requiredSSIDs,
                    onDismiss: { onDismissOnboardingTip(.requiredSSIDs) }
                )

                LabeledContent("Required BSSIDs") {
                    GroupedBSSIDSelectionMenu(
                        allLabel: "No required BSSIDs",
                        groups: availableBSSIDGroups,
                        showsBand: true,
                        selection: $requiredBSSIDs,
                        onPresentationChanged: onRequiredBSSIDMenuPresentationChanged
                    )
                }
                .disabled(isScanning)
                .help("Every selected BSSID must appear before a scan is accepted. Selecting a BSSID automatically enables and locks its known Record Band. An empty selection means no BSSID is required; all returned readings on selected Record Bands are still recorded.")
                .onboardingTooltip(
                    tip: .requiredBSSIDs,
                    isPresented: activeOnboardingTip == .requiredBSSIDs,
                    onDismiss: { onDismissOnboardingTip(.requiredBSSIDs) }
                )

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ScanRequirementSummary.lines(
                        requiredSSIDCount: requiredSSIDs.count,
                        requiredBSSIDCount: requiredBSSIDs.count,
                        recordBands: trackedBands
                    ), id: \.self) { line in
                        Text(line)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("Scanning")
                    Spacer()
                    Button(action: onRefreshNetworks) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isScanning)
                    .help("Refresh WiFi networks")
                    .accessibilityLabel("Refresh WiFi networks")
                }
                .frame(maxWidth: .infinity)
            }

            Section("Survey") {
                Toggle("Delete Mode", isOn: $isDeleteMode)
                    .tint(isDeleteMode ? .red : nil)
                    .help("Click any reading marker on the map to remove it. Right-click a marker at any time to get a context menu with a delete option.")

                Button(role: .destructive) {
                    isConfirmingClearAll = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(!hasRecordedPoints || isScanning)
                .help("Delete every recorded point on the currently active floor. Use Undo to restore them.")
            }
        }
        .formStyle(.grouped)
        .alert("New Scan", isPresented: $isCreatingScan) {
            TextField("Scan name", text: $newScanName)
            Button("Cancel", role: .cancel) {
                cancelCreatingScan()
            }
            Button("OK") {
                finishCreatingScan()
            }
                .disabled(newScanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Enter a name for the new scan.")
        }
        .alert(
            ScanDialogCopy.deleteTitle(scanName: scanPendingDeletion?.name ?? "this scan"),
            isPresented: $isConfirmingDeleteScan
        ) {
            Button("Cancel", role: .cancel) {
                scanPendingDeletion = nil
                isConfirmingDeleteScan = false
            }
            Button("Delete Scan", role: .destructive) {
                finishDeletingScan()
            }
        } message: {
            Text(ScanDialogCopy.deleteMessage(
                scanName: scanPendingDeletion?.name ?? "this scan"
            ))
        }
        .confirmationDialog(
            "Clear all points on this floor?",
            isPresented: $isConfirmingClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear All Points", role: .destructive, action: onClearAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every recorded point from the active scan on this floor. You can restore them with Undo.")
        }
        .onAppear(perform: applyDefaultRequiredBSSIDSelectionIfNeeded)
        .onChange(of: availableBSSIDGroups) {
            applyDefaultRequiredBSSIDSelectionIfNeeded()
        }
        .onChange(of: requiredSSIDs) {
            applyDefaultRequiredBSSIDSelectionIfNeeded()
        }
        .onChange(of: hasCompletedRequiredSSIDScan) {
            applyDefaultRequiredBSSIDSelectionIfNeeded()
        }
    }

    private func applyDefaultRequiredBSSIDSelectionIfNeeded() {
        guard let selection = requiredBSSIDSelectionInitializer.selectionToApply(
            defaultsToAll: defaultsRequiredBSSIDsToAll,
            hasRequiredSSIDs: !requiredSSIDs.isEmpty,
            hasCompletedRequiredSSIDScan: hasCompletedRequiredSSIDScan,
            groups: availableBSSIDGroups,
            currentSelection: requiredBSSIDs,
            recordBands: trackedBands
        ) else { return }
        onDefaultRequiredBSSIDsApplied(selection)
        requiredBSSIDs = selection
    }

    private func beginCreatingScan() {
        guard !isScanning else { return }
        newScanName = ""
        isCreatingScan = true
    }

    private func finishCreatingScan() {
        let trimmedName = newScanName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        onNewScan(trimmedName)
        newScanName = ""
        isCreatingScan = false
    }

    private func cancelCreatingScan() {
        newScanName = ""
        isCreatingScan = false
    }

    private func beginRenamingScan() {
        guard let activeScan else { return }
        scanName = activeScan.name
        isRenamingScan = true
        Task { @MainActor in
            await Task.yield()
            isScanNameFocused = true
        }
    }

    private func finishRenamingScan() {
        let trimmedName = scanName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        onRenameScan(trimmedName)
        scanName = trimmedName
        isScanNameFocused = false
        isRenamingScan = false
    }

    private func cancelRenamingScan() {
        isScanNameFocused = false
        isRenamingScan = false
    }

    private func beginDeletingScan() {
        guard !isScanning, let activeScan else { return }
        scanPendingDeletion = activeScan
        isConfirmingDeleteScan = true
    }

    private func finishDeletingScan() {
        guard let scanID = scanPendingDeletion?.id else { return }
        onDeleteScan(scanID)
        scanPendingDeletion = nil
        isConfirmingDeleteScan = false
    }

    private func trackedBandBinding(_ band: WiFiBand) -> Binding<Bool> {
        Binding(
            get: { trackedBands.contains(band) },
            set: { enabled in
                if enabled {
                    trackedBands.insert(band)
                } else if trackedBands.count > 1 && !requiredRecordBands.contains(band) {
                    trackedBands.remove(band)
                }
            }
        )
    }

    private func recordBandHelp(for band: WiFiBand) -> String {
        if requiredRecordBands.contains(band) {
            return "Required by a selected BSSID. Deselect that BSSID before turning off \(band.displayName) recording."
        }
        let discovery = discoveredBands.contains(band)
            ? "Detected in the latest scan."
            : "Not observed in the latest scan."
        return "\(discovery) Readings on \(band.displayName) are recorded when available, but their absence does not prevent a capture."
    }
}

enum ScanDialogCopy {
    static func deleteTitle(scanName: String) -> String {
        "Delete “\(scanName)”?"
    }

    static func deleteMessage(scanName: String) -> String {
        "Are you sure you want to delete “\(scanName)” and all of its recorded points? This cannot be undone."
    }
}

enum ScanPickerAction: Equatable {
    case select(UUID)
    case newScan
}

enum ScanPickerLayout {
    private static let expandingPriority = NSLayoutConstraint.Priority(rawValue: 1)
    private static let newScanIdentifier = NSUserInterfaceItemIdentifier("WifiHeatmap.NewScan")

    static func configure(_ popup: NSPopUpButton) {
        popup.setContentHuggingPriority(expandingPriority, for: .horizontal)
        popup.setContentCompressionResistancePriority(expandingPriority, for: .horizontal)
    }

    static func populate(
        _ popup: NSPopUpButton,
        scanSets: [ScanSet],
        activeScanID: UUID?
    ) {
        popup.removeAllItems()

        if scanSets.isEmpty {
            let emptyItem = NSMenuItem(title: "No scans yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            popup.menu?.addItem(emptyItem)
        } else {
            for scan in scanSets {
                let item = NSMenuItem(title: scan.name, action: nil, keyEquivalent: "")
                item.representedObject = scan.id.uuidString
                popup.menu?.addItem(item)
            }
        }

        popup.menu?.addItem(.separator())
        let newScanItem = NSMenuItem(title: "New Scan", action: nil, keyEquivalent: "")
        newScanItem.identifier = newScanIdentifier
        popup.menu?.addItem(newScanItem)

        selectActiveItem(in: popup, scanSets: scanSets, activeScanID: activeScanID)
    }

    static func action(for item: NSMenuItem?) -> ScanPickerAction? {
        guard let item else { return nil }
        if item.identifier == newScanIdentifier {
            return .newScan
        }
        guard let rawID = item.representedObject as? String,
              let scanID = UUID(uuidString: rawID)
        else { return nil }
        return .select(scanID)
    }

    static func selectActiveItem(
        in popup: NSPopUpButton,
        scanSets: [ScanSet],
        activeScanID: UUID?
    ) {
        if let activeScanID,
           let selectedIndex = scanSets.firstIndex(where: { $0.id == activeScanID }) {
            popup.selectItem(at: selectedIndex)
        } else if scanSets.isEmpty {
            popup.selectItem(at: 0)
        } else {
            popup.select(nil)
        }
    }
}

struct FullWidthScanPicker: NSViewRepresentable {
    let scanSets: [ScanSet]
    @Binding var activeScanID: UUID?
    let isEnabled: Bool
    let onNewScan: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        ScanPickerLayout.configure(popup)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        popup.setAccessibilityLabel("Scan")
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        ScanPickerLayout.populate(
            popup,
            scanSets: scanSets,
            activeScanID: activeScanID
        )
        popup.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var parent: FullWidthScanPicker

        init(parent: FullWidthScanPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            switch ScanPickerLayout.action(for: sender.selectedItem) {
            case .select(let scanID):
                parent.activeScanID = scanID
            case .newScan:
                ScanPickerLayout.selectActiveItem(
                    in: sender,
                    scanSets: parent.scanSets,
                    activeScanID: parent.activeScanID
                )
                parent.onNewScan()
            case nil:
                break
            }
        }
    }
}

struct MultiSelectionMenu: View {
    let emptySelectionLabel: String
    let showsClearSelectionOption: Bool
    let options: [String]
    @Binding var selection: Set<String>
    let onPresentationChanged: (Bool) -> Void
    @State private var isPresented = false

    private var summary: String {
        if selection.isEmpty { return emptySelectionLabel }
        if selection.count == 1 { return selection.first! }
        return "\(selection.count) selected"
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(summary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(emptySelectionLabel)
        .accessibilityValue(summary)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if showsClearSelectionOption {
                    Button {
                        selection.removeAll()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark")
                                .opacity(selection.isEmpty ? 1 : 0)
                                .frame(width: 12)
                            Text("Clear Selection")
                            Spacer(minLength: 12)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.vertical, 4)
                }

                ScrollView {
                    if options.isEmpty {
                        Text("No networks found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(options, id: \.self) { option in
                                Toggle(option, isOn: optionBinding(option))
                                    .toggleStyle(.checkbox)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: min(max(CGFloat(options.count) * 24, 28), 280))
            }
            .padding(6)
            .frame(minWidth: 220, idealWidth: 250)
        }
        .onChange(of: isPresented) {
            onPresentationChanged(isPresented)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func optionBinding(_ option: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(option) },
            set: { selected in
                if selected { selection.insert(option) }
                else { selection.remove(option) }
            }
        )
    }
}

struct GroupedBSSIDSelectionMenu: View {
    let allLabel: String
    let groups: [BSSIDOptionGroup]
    let showsBand: Bool
    @Binding var selection: Set<String>
    let onPresentationChanged: (Bool) -> Void
    @State private var isPresented = false

    private var optionCount: Int {
        groups.reduce(0) { $0 + $1.options.count }
    }

    private var summary: String {
        if selection.isEmpty { return allLabel }
        if selection.count == 1 { return selection.first! }
        return "\(selection.count) selected"
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(summary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(allLabel)
        .accessibilityValue(summary)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    selection.removeAll()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark")
                            .opacity(selection.isEmpty ? 1 : 0)
                            .frame(width: 12)
                        Text(allLabel)
                        Spacer(minLength: 12)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.vertical, 4)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.ssid)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 19)

                                ForEach(group.options) { option in
                                    Toggle(
                                        showsBand
                                            ? "\(option.bssid) (\(option.bandLabel))"
                                            : option.bssid,
                                        isOn: optionBinding(option.bssid)
                                    )
                                    .toggleStyle(.checkbox)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: min(
                    max(CGFloat(optionCount) * 24 + CGFloat(groups.count) * 18, 46),
                    320
                ))
            }
            .padding(6)
            .frame(minWidth: showsBand ? 280 : 240, idealWidth: showsBand ? 320 : 280)
        }
        .onChange(of: isPresented) {
            onPresentationChanged(isPresented)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func optionBinding(_ bssid: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(bssid) },
            set: { selected in
                if selected { selection.insert(bssid) }
                else { selection.remove(bssid) }
            }
        )
    }
}

enum HeatmapRangeField: Hashable {
    case minimum
    case maximum
}

enum HeatmapRangeFocusPolicy {
    static let initialField: HeatmapRangeField? = nil
}

struct HeatmapRangeControl: View {
    @Binding var range: HeatmapValueRange
    let metric: HeatmapMetric
    @FocusState private var focusedField: HeatmapRangeField?

    private var limits: ClosedRange<Double> {
        metric == .rssi ? -120...0 : -20...100
    }

    private var unit: String {
        metric == .rssi ? "dBm" : "dB"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color Range")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("Minimum", value: lowerBinding, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 62)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .minimum)
                    .accessibilityLabel("Minimum \(metric.displayName)")

                TwoSidedSlider(range: $range, limits: limits)
                    .frame(minWidth: 90)
                    .frame(height: 22)

                TextField("Maximum", value: upperBinding, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 62)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .maximum)
                    .accessibilityLabel("Maximum \(metric.displayName)")

                Text(unit)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .help("Values at or below the minimum use the weakest color; values at or above the maximum use the strongest color.")
        .onAppear {
            DispatchQueue.main.async {
                focusedField = HeatmapRangeFocusPolicy.initialField
            }
        }
    }

    private var lowerBinding: Binding<Double> {
        Binding(
            get: { range.lowerBound },
            set: { value in
                var updated = range
                updated.setLowerBound(value, within: limits)
                range = updated
            }
        )
    }

    private var upperBinding: Binding<Double> {
        Binding(
            get: { range.upperBound },
            set: { value in
                var updated = range
                updated.setUpperBound(value, within: limits)
                range = updated
            }
        )
    }
}

private struct TwoSidedSlider: View {
    @Binding var range: HeatmapValueRange
    let limits: ClosedRange<Double>

    private let thumbSize: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(geometry.size.width - thumbSize, 1)
            let lowerX = thumbSize / 2 + xPosition(for: range.lowerBound, width: usableWidth)
            let upperX = thumbSize / 2 + xPosition(for: range.upperBound, width: usableWidth)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 4)
                    .padding(.horizontal, thumbSize / 2)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(upperX - lowerX, 0), height: 4)
                    .offset(x: lowerX)

                thumb(at: lowerX, label: "Minimum")
                    .gesture(dragGesture(width: usableWidth, isLower: true))

                thumb(at: upperX, label: "Maximum")
                    .gesture(dragGesture(width: usableWidth, isLower: false))
            }
            .coordinateSpace(name: "twoSidedSlider")
        }
    }

    private func thumb(at x: CGFloat, label: String) -> some View {
        Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: thumbSize, height: thumbSize)
            .position(x: x, y: 11)
            .contentShape(Rectangle().inset(by: -5))
            .accessibilityLabel("\(label) heatmap bound")
    }

    private func dragGesture(width: CGFloat, isLower: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("twoSidedSlider"))
            .onChanged { gesture in
                let value = value(at: gesture.location.x - thumbSize / 2, width: width)
                var updated = range
                if isLower {
                    updated.setLowerBound(value, within: limits)
                } else {
                    updated.setUpperBound(value, within: limits)
                }
                range = updated
            }
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        CGFloat((value - limits.lowerBound) / (limits.upperBound - limits.lowerBound)) * width
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let fraction = min(max(Double(x / width), 0), 1)
        return (limits.lowerBound + fraction * (limits.upperBound - limits.lowerBound)).rounded()
    }
}

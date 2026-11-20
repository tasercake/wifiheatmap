import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

struct InitialWiFiScanGate {
    private var hasStarted = false

    mutating func claim() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }
}

struct ContentView: View {
    @Environment(\.openDocument) private var openDocument
    @ObservedObject var document: WifiSurveyDocument
    let fileURL: URL?
    @StateObject private var closeCoordinator: DocumentCloseCoordinator
    @StateObject private var onboarding = OnboardingSessionState()
    @State private var selectedFloorID: UUID? = nil
    @State private var showInspector: Bool = true
    @StateObject private var locationAuth = LocationAuthManager()
    private let scanActor = ScanActor.shared
    @State private var initialScanGate = InitialWiFiScanGate()
    @State private var availableNetworks: [ScannedNetwork] = []
    @State private var latestBatch: [ScannedNetwork] = []
    @State private var latestScanAt: Date? = nil
    @State private var latestScanSetID: UUID? = nil
    @State private var isScanning = false

    init(document: WifiSurveyDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _closeCoordinator = StateObject(wrappedValue: DocumentCloseCoordinator(
            document: document,
            originalFileURL: fileURL
        ))
    }

    private var selectedFloorIndex: Int? {
        document.survey.floors.firstIndex(where: { $0.id == selectedFloorID })
    }

    private var selectedFloorBinding: Binding<Floor>? {
        guard let selectedFloorIndex else { return nil }
        return $document.survey.floors[selectedFloorIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            FloorTabBar(
                document: document,
                selectedFloorID: $selectedFloorID,
                showInspector: $showInspector
            )

            FloorDetailView(
                document: document,
                floor: selectedFloorBinding,
                availableNetworks: availableNetworks,
                latestBatch: latestScanSetID == document.survey.activeScanID ? latestBatch : [],
                latestScanAt: latestScanSetID == document.survey.activeScanID ? latestScanAt : nil,
                isScanning: isScanning,
                scanForReading: scanForReading,
                showInspector: $showInspector,
                onboarding: onboarding,
                defaultsRequiredBSSIDsToAll: fileURL == nil,
                onImportFirstFloorPlan: importFirstFloorPlan,
                onOpenExistingSurvey: openExistingSurvey,
                onRefreshNetworks: {
                    Task { await refreshAvailableNetworks() }
                }
            )
        }
        .onAppear {
            locationAuth.requestIfNeeded()
            if selectedFloorID == nil { selectedFloorID = document.survey.floors.first?.id }
        }
        .overlay(alignment: .top) {
            if locationAuth.isDenied { locationDeniedBanner }
        }
        .overlay {
            if document.requiresMigration {
                migrationOverlay
            }
        }
        .disabled(document.requiresMigration)
        .task {
            guard initialScanGate.claim() else { return }
            await refreshAvailableNetworks()
        }
        .task(id: fileURL) {
            closeCoordinator.associate(with: fileURL)
            guard document.requiresMigration else { return }
            do {
                try document.completePendingMigration(sourceURL: fileURL)
                selectedFloorID = document.survey.floors.first?.id
            } catch {
                // The document publishes a user-visible migration failure and
                // remains read-only until a complete backup can be created.
            }
        }
        .alert(
            "Survey Updated",
            isPresented: Binding(
                get: { document.migrationSuccessMessage != nil },
                set: { if !$0 { document.dismissMigrationSuccess() } }
            )
        ) {
            Button("OK") { document.dismissMigrationSuccess() }
        } message: {
            Text(document.migrationSuccessMessage ?? "")
        }
        .background(WindowCloseBridge(coordinator: closeCoordinator))
        .background(WindowTextFieldFocusBridge())
        .focusedSceneValue(
            \.openSurveyInCurrentWindow,
            OpenSurveyInCurrentWindowAction(perform: openExistingSurvey)
        )
    }

    private func scanForReading(attempt: Int) async throws -> ScanBatch {
        isScanning = true
        defer { isScanning = false }
        return try await performScan(attempt: attempt)
    }

    private func refreshAvailableNetworks() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        _ = try? await NetworkDiscoveryCoordinator.refresh { attempt in
            try await performScan(attempt: attempt)
        }
    }

    private func performScan(attempt: Int) async throws -> ScanBatch {
        let scanSetID = document.survey.activeScanID
        let batch = try await scanActor.scanOnce(attemptCount: attempt)
        availableNetworks = batch.networks
        latestBatch = batch.networks
        latestScanAt = batch.completedAt
        latestScanSetID = scanSetID
        return batch
    }

    private func importFirstFloorPlan() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Floor Plan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard document.survey.floors.isEmpty else { return }

        document.addFloor(name: "Floor 1")
        guard let floorID = document.survey.floors.last?.id else { return }

        do {
            try document.importFloorPlan(url: url, for: floorID)
            selectedFloorID = floorID
        } catch {
            document.removeFloor(id: floorID)
        }
    }

    private func openExistingSurvey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wifiSurvey]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open Existing Scan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !closeCoordinator.isAssociated(with: url) else { return }
        guard let sourceWindow = closeCoordinator.prepareForDocumentReplacement() else { return }

        Task {
            do {
                try await openDocument(at: url)
                sourceWindow.performClose(nil)
            } catch {
                closeCoordinator.resetCloseApproval()
                let alert = NSAlert(error: error)
                alert.messageText = "The scan could not be opened."
                alert.runModal()
            }
        }
    }

    private var locationDeniedBanner: some View {
        HStack {
            Image(systemName: "location.slash")
            Text("Location access denied \u{2014} BSSIDs will be empty. Grant access in System Settings > Privacy > Location.")
                .font(.caption)
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Location")!)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.85))
    }

    private var migrationOverlay: some View {
        VStack(spacing: 10) {
            if let message = document.migrationFailureMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Couldn’t Migrate Survey")
                    .font(.headline)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Creating a safety backup before migrating this survey…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12)
    }
}

enum UnsavedCloseChoice {
    case save
    case discard
    case cancel
}

enum UnsavedClosePolicy {
    static func shouldClose(
        isDirty: Bool,
        choose: () -> UnsavedCloseChoice,
        save: () -> Bool
    ) -> Bool {
        guard isDirty else { return true }

        switch choose() {
        case .save:
            return save()
        case .discard:
            return true
        case .cancel:
            return false
        }
    }
}

enum DocumentReplacementPolicy {
    static func shouldProceed(
        isDirty: Bool,
        choose: () -> UnsavedCloseChoice,
        save: () -> Bool
    ) -> Bool {
        UnsavedClosePolicy.shouldClose(
            isDirty: isDirty,
            choose: choose,
            save: save
        )
    }
}

enum DocumentSaveDestination {
    static func resolve(
        existingFileURL: URL?,
        chooseSaveAsDestination: () -> URL?
    ) -> URL? {
        existingFileURL ?? chooseSaveAsDestination()
    }
}

enum DirtyWindowTitle {
    private static let suffix = " *"

    static func formatted(_ title: String, isDirty: Bool) -> String {
        let cleanTitle = title.hasSuffix(suffix)
            ? String(title.dropLast(suffix.count))
            : title
        return isDirty ? cleanTitle + suffix : cleanTitle
    }
}

@MainActor
final class DocumentCloseCoordinator: ObservableObject {
    @Published private(set) var isDirty = false

    private let document: WifiSurveyDocument
    private var dirtyState: PersistedDocumentDirtyState
    private var currentFileURL: URL?
    private var documentChanges: AnyCancellable?
    private var exactCheckTask: Task<Void, Never>?
    private var closeWasApproved = false
    private weak var window: NSWindow?
    private var cleanWindowTitle: String?
    private var renderedWindowTitle: String?

    init(document: WifiSurveyDocument, originalFileURL: URL?) {
        self.document = document
        self.dirtyState = PersistedDocumentDirtyState(
            savedSnapshot: try? document.snapshot(contentType: .wifiSurvey)
        )
        self.currentFileURL = originalFileURL
        documentChanges = document.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            dirtyState.notePossibleChange()
            closeWasApproved = false
            setDirty(true)
            scheduleExactCheck()
        }
    }

    func attach(to window: NSWindow) {
        if self.window !== window {
            cleanWindowTitle = DirtyWindowTitle.formatted(window.title, isDirty: false)
            renderedWindowTitle = nil
        }
        self.window = window
        applyWindowState()
    }

    func associate(with fileURL: URL?) {
        guard let fileURL else { return }
        currentFileURL = fileURL
        reconcileWithSavedFile()
    }

    func isAssociated(with fileURL: URL) -> Bool {
        currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL
    }

    func prepareForDocumentReplacement() -> NSWindow? {
        guard let window else { return nil }
        let hasUnsavedChanges = reconcileWithSavedFile()
        let shouldProceed = DocumentReplacementPolicy.shouldProceed(
            isDirty: hasUnsavedChanges,
            choose: { presentSavePrompt(for: window) },
            save: { save() }
        )
        guard shouldProceed else { return nil }

        closeWasApproved = true
        window.isDocumentEdited = false
        return window
    }

    func requestClose(for window: NSWindow) -> Bool {
        if closeWasApproved {
            window.isDocumentEdited = false
            return true
        }

        let hasUnsavedChanges = reconcileWithSavedFile()

        let shouldClose = UnsavedClosePolicy.shouldClose(
            isDirty: hasUnsavedChanges,
            choose: { presentSavePrompt(for: window) },
            save: { save() }
        )

        if shouldClose {
            closeWasApproved = true
            window.isDocumentEdited = false
        }
        return shouldClose
    }

    func resetCloseApproval() {
        closeWasApproved = false
        applyWindowState()
    }

    func windowDidUpdate(_ window: NSWindow) {
        guard self.window === window else { return }
        if !window.isDocumentEdited, isDirty, !closeWasApproved {
            adoptSystemSavedState(from: window)
        }
        synchronizeWindowTitle()
    }

    private func presentSavePrompt(for window: NSWindow) -> UnsavedCloseChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save your changes?"
        alert.informativeText = "Your changes will be lost if you close this document without saving."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = window.level

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func save() -> Bool {
        guard let destinationURL = DocumentSaveDestination.resolve(
            existingFileURL: currentFileURL,
            chooseSaveAsDestination: { presentSaveAsPanel() }
        ) else {
            return false
        }

        do {
            let snapshot = try document.snapshot(contentType: .wifiSurvey)
            let wrapper = try WifiSurveyDocument.encode(snapshot: snapshot)
            try wrapper.write(
                to: destinationURL,
                options: .atomic,
                originalContentsURL: currentFileURL
            )
            currentFileURL = destinationURL
            dirtyState.markSaved(snapshot)
            setDirty(false)
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "The survey could not be saved."
            alert.runModal()
            return false
        }
    }

    private func presentSaveAsPanel() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wifiSurvey]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Save WiFi Survey"
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent
            ?? "\(document.survey.name).wifiheatmap"

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return nil
        }
        return destinationURL
    }

    private func scheduleExactCheck() {
        exactCheckTask?.cancel()
        exactCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self else { return }
            reconcileWithSavedSnapshot()
        }
    }

    @discardableResult
    private func reconcileWithSavedSnapshot() -> Bool {
        exactCheckTask?.cancel()
        let currentSnapshot = try? document.snapshot(contentType: .wifiSurvey)
        let dirty = dirtyState.reconcile(currentSnapshot: currentSnapshot)
        setDirty(dirty)
        return dirty
    }

    @discardableResult
    private func reconcileWithSavedFile() -> Bool {
        if let snapshotOnDisk = loadSnapshotFromDisk() {
            dirtyState.markSaved(snapshotOnDisk)
        }
        return reconcileWithSavedSnapshot()
    }

    private func loadSnapshotFromDisk() -> DocumentSnapshot? {
        guard let currentFileURL,
              let wrapper = try? FileWrapper(url: currentFileURL, options: .immediate),
              let decoded = try? WifiSurveyDocument.decode(fileWrapper: wrapper)
        else {
            return nil
        }
        return DocumentSnapshot(survey: decoded.0, imageCache: decoded.1)
    }

    private func adoptSystemSavedState(from window: NSWindow) {
        exactCheckTask?.cancel()
        if let representedURL = window.representedURL {
            currentFileURL = representedURL
        }
        guard let snapshot = try? document.snapshot(contentType: .wifiSurvey) else {
            reconcileWithSavedFile()
            return
        }
        dirtyState.markSaved(snapshot)
        setDirty(false)
    }

    private func setDirty(_ dirty: Bool) {
        if isDirty != dirty {
            isDirty = dirty
        }
        applyWindowState()
    }

    private func applyWindowState() {
        guard let window else { return }
        if window.isDocumentEdited != isDirty {
            window.isDocumentEdited = isDirty
        }
        synchronizeWindowTitle()
    }

    private func synchronizeWindowTitle() {
        guard let window else { return }

        if renderedWindowTitle == nil || window.title != renderedWindowTitle {
            cleanWindowTitle = DirtyWindowTitle.formatted(window.title, isDirty: false)
        }

        let desiredTitle = DirtyWindowTitle.formatted(
            cleanWindowTitle ?? window.title,
            isDirty: isDirty
        )
        renderedWindowTitle = desiredTitle
        if window.title != desiredTitle {
            window.title = desiredTitle
        }
    }
}

@MainActor
final class WindowTextFieldFocusController {
    private let clearFocus: () -> Void
    private var hasClearedInitialFocus = false

    init(clearFocus: @escaping () -> Void) {
        self.clearFocus = clearFocus
    }

    func clearInitialFocus() {
        guard !hasClearedInitialFocus else { return }
        hasClearedInitialFocus = true
        clearFocus()
    }

    func pointerPressed() {
        clearFocus()
    }
}

struct WindowTextFieldFocusBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowTextFieldFocusView {
        WindowTextFieldFocusView()
    }

    func updateNSView(_ nsView: WindowTextFieldFocusView, context: Context) {
        nsView.install(on: nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowTextFieldFocusView, coordinator: Void) {
        nsView.uninstall()
    }
}

@MainActor
final class WindowTextFieldFocusView: NSView {
    private weak var installedWindow: NSWindow?
    private var eventMonitor: Any?
    private var focusController: WindowTextFieldFocusController?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        install(on: window)
    }

    func install(on window: NSWindow?) {
        guard installedWindow !== window else { return }
        uninstall()
        guard let window else { return }

        installedWindow = window
        window.initialFirstResponder = self
        focusController = WindowTextFieldFocusController { [weak self, weak window] in
            guard let self, let window else { return }
            window.endEditing(for: nil)
            window.makeFirstResponder(self)
        }
        focusController?.clearInitialFocus()

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self, weak window] event in
            guard event.window === window else { return event }
            self?.focusController?.pointerPressed()
            return event
        }
    }

    func uninstall() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil

        if installedWindow?.initialFirstResponder === self {
            installedWindow?.initialFirstResponder = nil
        }
        installedWindow = nil
        focusController = nil
    }

    override func keyDown(with event: NSEvent) {
        nextResponder?.keyDown(with: event)
    }
}

struct WindowCloseBridge: NSViewRepresentable {
    @ObservedObject var coordinator: DocumentCloseCoordinator

    func makeCoordinator() -> BridgeCoordinator {
        BridgeCoordinator()
    }

    func makeNSView(context: Context) -> WindowObservationView {
        let view = WindowObservationView()
        view.onWindowChange = { window in
            context.coordinator.install(on: window, closeCoordinator: coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: WindowObservationView, context: Context) {
        context.coordinator.install(on: nsView.window, closeCoordinator: coordinator)
    }

    static func dismantleNSView(_ nsView: WindowObservationView, coordinator: BridgeCoordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class BridgeCoordinator {
        private weak var installedWindow: NSWindow?
        private var proxy: WindowCloseDelegateProxy?

        func install(on window: NSWindow?, closeCoordinator: DocumentCloseCoordinator) {
            guard let window else { return }
            if installedWindow === window,
               let proxy,
               (window.delegate as AnyObject?) === proxy {
                closeCoordinator.attach(to: window)
                return
            }

            uninstall()
            let proxy = WindowCloseDelegateProxy(
                originalDelegate: window.delegate,
                closeCoordinator: closeCoordinator
            )
            self.proxy = proxy
            installedWindow = window
            window.delegate = proxy
            closeCoordinator.attach(to: window)
        }

        func uninstall() {
            guard let window = installedWindow, let proxy else {
                installedWindow = nil
                self.proxy = nil
                return
            }
            if (window.delegate as AnyObject?) === proxy {
                window.delegate = proxy.originalDelegate
            }
            installedWindow = nil
            self.proxy = nil
        }
    }
}

final class WindowObservationView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

@MainActor
final class WindowCloseDelegateProxy: NSObject, NSWindowDelegate {
    weak var originalDelegate: NSWindowDelegate?
    private let closeCoordinator: DocumentCloseCoordinator

    init(originalDelegate: NSWindowDelegate?, closeCoordinator: DocumentCloseCoordinator) {
        self.originalDelegate = originalDelegate
        self.closeCoordinator = closeCoordinator
    }

    func requestClose(_ window: NSWindow) -> Bool {
        closeCoordinator.requestClose(for: window)
    }

    func resetCloseApproval() {
        closeCoordinator.resetCloseApproval()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard requestClose(sender) else { return false }
        return originalDelegate?.windowShouldClose?(sender) ?? true
    }

    func windowDidUpdate(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            closeCoordinator.windowDidUpdate(window)
        }
        originalDelegate?.windowDidUpdate?(notification)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if originalDelegate?.responds(to: aSelector) == true {
            return originalDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}

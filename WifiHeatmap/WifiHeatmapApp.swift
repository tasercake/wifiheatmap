import SwiftUI
import AppKit

@main
struct WifiHeatmapApp: App {
    @NSApplicationDelegateAdaptor(WifiHeatmapApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: StartupDocumentLauncher.sceneID) {
            StartupDocumentLauncher()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)

        DocumentGroup(newDocument: { WifiSurveyDocument() }) { config in
            ContentView(document: config.document, fileURL: config.fileURL)
        }
        .commands {
            CurrentDocumentFileCommands()
        }

        Settings {
            HelpTooltipSettingsView()
        }
    }
}

struct OpenSurveyInCurrentWindowAction {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }
}

struct DeleteSelectedPointAction {
    let perform: () -> Void

    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }

    func callAsFunction() {
        perform()
    }
}

private struct OpenSurveyInCurrentWindowKey: FocusedValueKey {
    typealias Value = OpenSurveyInCurrentWindowAction
}

private struct DeleteSelectedPointKey: FocusedValueKey {
    typealias Value = DeleteSelectedPointAction
}

extension FocusedValues {
    var openSurveyInCurrentWindow: OpenSurveyInCurrentWindowAction? {
        get { self[OpenSurveyInCurrentWindowKey.self] }
        set { self[OpenSurveyInCurrentWindowKey.self] = newValue }
    }

    var deleteSelectedPoint: DeleteSelectedPointAction? {
        get { self[DeleteSelectedPointKey.self] }
        set { self[DeleteSelectedPointKey.self] = newValue }
    }
}

private struct CurrentDocumentFileCommands: Commands {
    @Environment(\.newDocument) private var newDocument
    @FocusedValue(\.openSurveyInCurrentWindow) private var openSurveyInCurrentWindow
    @FocusedValue(\.deleteSelectedPoint) private var deleteSelectedPoint

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                newDocument { WifiSurveyDocument() }
            }
            .keyboardShortcut("n")

            Button("Open\u{2026}") {
                openSurveyInCurrentWindow?()
            }
            .keyboardShortcut("o")
            .disabled(openSurveyInCurrentWindow == nil)
        }

        CommandGroup(after: .pasteboard) {
            Button("Delete Selected Point") {
                deleteSelectedPoint?()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(deleteSelectedPoint == nil)
        }
    }
}

private struct StartupDocumentLauncher: View {
    static let sceneID = "startup-document-launcher"

    @Environment(\.newDocument) private var newDocument
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var hasCreatedDocument = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .task {
                guard !hasCreatedDocument else { return }
                hasCreatedDocument = true
                newDocument { WifiSurveyDocument() }
                await Task.yield()
                dismissWindow(id: Self.sceneID)
            }
    }
}

enum BlankDocumentLaunchPolicy {
    static let opensUntitledDocumentByDefault = true
}

enum HelpTooltipPreferences {
    static let showHelpTooltipsKey = "showHelpTooltips"
}

enum OnboardingTipID: String, Hashable {
    case importFloorPlan
    case calibrateDistance
    case requiredSSIDs
    case requiredBSSIDs
    case capturePoint

    var title: String {
        switch self {
        case .importFloorPlan: "Start with a floor plan"
        case .calibrateDistance: "Calibrate the floor plan"
        case .requiredSSIDs: "Choose the Wi-Fi networks to map"
        case .requiredBSSIDs: "Optionally require specific BSSIDs"
        case .capturePoint: "Take your first reading"
        }
    }

    var message: String {
        switch self {
        case .importFloorPlan:
            "Add a picture or PDF of your floor plan to begin your survey."
        case .calibrateDistance:
            "Set the scale by marking a known distance on the floor plan and entering its real-world length."
        case .requiredSSIDs:
            "Pick the SSIDs you want to map. The app will scan immediately to discover their available BSSIDs."
        case .requiredBSSIDs:
            "If you need particular radios in every reading, select their BSSIDs here. Leaving this empty accepts whatever BSSIDs are available for each required SSID."
        case .capturePoint:
            "Click the spot on the map where you are standing to take a reading. You can also click and drag to record the direction you are facing."
        }
    }

    var systemImage: String {
        switch self {
        case .importFloorPlan: "photo"
        case .calibrateDistance: "ruler"
        case .requiredSSIDs: "wifi"
        case .requiredBSSIDs: "antenna.radiowaves.left.and.right"
        case .capturePoint: "location.circle"
        }
    }

    var showsSkipButton: Bool {
        self == .requiredBSSIDs
    }
}

struct OnboardingContext: Equatable {
    var hasFloors = false
    var selectedFloorHasPlan = false
    var hasAnyCalibration = false
    var hasRequiredSSIDs = false
    var hasCompletedRequiredSSIDScan = false
    var hasRequiredBSSIDs = false
    var hasAvailableBSSIDs = false
    var canCaptureOnSelectedFloor = false
    var hasRecordedPoints = false
    var showsInspector = false
    var isRequiredSSIDSelectionOpen = false
    var isRequiredBSSIDSelectionOpen = false
}

enum OnboardingFlow {
    static func completedTips(for context: OnboardingContext) -> Set<OnboardingTipID> {
        var completed: Set<OnboardingTipID> = []
        if context.hasFloors { completed.insert(.importFloorPlan) }
        if context.hasAnyCalibration { completed.insert(.calibrateDistance) }
        if context.hasRequiredSSIDs && !context.isRequiredSSIDSelectionOpen {
            completed.insert(.requiredSSIDs)
        }
        if context.hasRequiredBSSIDs && !context.isRequiredBSSIDSelectionOpen {
            completed.insert(.requiredBSSIDs)
        }
        if context.hasRecordedPoints { completed.insert(.capturePoint) }
        return completed
    }

    static func nextTip(
        for context: OnboardingContext,
        dismissed: Set<OnboardingTipID> = [],
        isHelpEnabled: Bool = true
    ) -> OnboardingTipID? {
        guard isHelpEnabled else { return nil }

        guard context.hasFloors else {
            return dismissed.contains(.importFloorPlan) ? nil : .importFloorPlan
        }
        guard context.selectedFloorHasPlan else { return nil }
        guard context.hasAnyCalibration else {
            return dismissed.contains(.calibrateDistance) ? nil : .calibrateDistance
        }
        guard context.showsInspector else { return nil }
        guard context.hasRequiredSSIDs && !context.isRequiredSSIDSelectionOpen else {
            return dismissed.contains(.requiredSSIDs) ? nil : .requiredSSIDs
        }
        if context.hasCompletedRequiredSSIDScan,
           (!context.hasRequiredBSSIDs || context.isRequiredBSSIDSelectionOpen),
           context.hasAvailableBSSIDs,
           !dismissed.contains(.requiredBSSIDs) {
            return .requiredBSSIDs
        }
        guard context.canCaptureOnSelectedFloor else { return nil }
        return dismissed.contains(.capturePoint) ? nil : .capturePoint
    }
}

enum PersistentPopoverPlacement {
    static func preferredEdge(
        anchorRect: CGRect,
        availableRect: CGRect,
        popoverSize: CGSize,
        preferredEdge: NSRectEdge? = nil
    ) -> NSRectEdge {
        let size = CGSize(
            width: popoverSize.width + 14,
            height: popoverSize.height + 14
        )
        let candidates: [(edge: NSRectEdge, frame: CGRect)] = [
            (
                .maxY,
                CGRect(
                    x: anchorRect.midX - size.width / 2,
                    y: anchorRect.maxY,
                    width: size.width,
                    height: size.height
                )
            ),
            (
                .minY,
                CGRect(
                    x: anchorRect.midX - size.width / 2,
                    y: anchorRect.minY - size.height,
                    width: size.width,
                    height: size.height
                )
            ),
            (
                .maxX,
                CGRect(
                    x: anchorRect.maxX,
                    y: anchorRect.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                )
            ),
            (
                .minX,
                CGRect(
                    x: anchorRect.minX - size.width,
                    y: anchorRect.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                )
            )
        ]

        if let fittingPreferred = preferredEdge.flatMap({ preferred in
            candidates.first { $0.edge == preferred && availableRect.contains($0.frame) }
        }) {
            return fittingPreferred.edge
        }

        if let fitting = candidates.first(where: { availableRect.contains($0.frame) }) {
            return fitting.edge
        }

        let availableSpace: [(edge: NSRectEdge, distance: CGFloat)] = [
            (.maxY, availableRect.maxY - anchorRect.maxY),
            (.minY, anchorRect.minY - availableRect.minY),
            (.maxX, availableRect.maxX - anchorRect.maxX),
            (.minX, anchorRect.minX - availableRect.minX)
        ]
        return availableSpace.max(by: { $0.distance < $1.distance })?.edge ?? .maxY
    }
}

@MainActor
final class OnboardingSessionState: ObservableObject {
    @Published private(set) var dismissedTips: Set<OnboardingTipID> = []

    func dismiss(_ tip: OnboardingTipID) {
        dismissedTips.insert(tip)
    }

    func latchCompletedTips(for context: OnboardingContext) {
        let completedTips = OnboardingFlow.completedTips(for: context)
        guard !completedTips.isSubset(of: dismissedTips) else { return }
        dismissedTips.formUnion(completedTips)
    }
}

struct HelpTooltipSettingsView: View {
    @AppStorage(HelpTooltipPreferences.showHelpTooltipsKey)
    private var showHelpTooltips = true

    var body: some View {
        Form {
            Toggle("Show help tooltips", isOn: $showHelpTooltips)
                .help("Show contextual guidance while setting up and recording a survey.")
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}

private struct OnboardingTooltipModifier: ViewModifier {
    let tip: OnboardingTipID
    let isPresented: Bool
    let onDismiss: () -> Void

    @AppStorage(HelpTooltipPreferences.showHelpTooltipsKey)
    private var showHelpTooltips = true
    @State private var dontShowAgain = false

    func body(content: Content) -> some View {
        content
            .background {
                PersistentPopoverPresenter(
                    isPresented: isPresented && showHelpTooltips,
                    preferredEdge: tip == .importFloorPlan ? .maxX : nil
                ) {
                    tooltipContent
                }
            }
            .onChange(of: isPresented) {
                if isPresented { dontShowAgain = false }
            }
    }

    private var tooltipContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tip.systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 5) {
                    Text(tip.title)
                        .font(.headline)
                    Text(tip.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss help tooltip")
            }

            Divider()

            HStack {
                Toggle("Don’t show again", isOn: $dontShowAgain)
                    .toggleStyle(.checkbox)

                Spacer(minLength: 12)

                if tip.showsSkipButton {
                    Button("Skip", action: dismiss)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .frame(width: 350)
    }

    private func dismiss() {
        if dontShowAgain {
            showHelpTooltips = false
        }
        onDismiss()
    }
}

private struct PersistentPopoverPresenter<PopoverContent: View>: NSViewRepresentable {
    let isPresented: Bool
    let preferredEdge: NSRectEdge?
    @ViewBuilder let popoverContent: () -> PopoverContent

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ anchorView: NSView, context: Context) {
        context.coordinator.update(
            isPresented: isPresented,
            preferredEdge: preferredEdge,
            anchorView: anchorView,
            content: popoverContent()
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator {
        private var popover: NSPopover?
        private var hostingController: NSHostingController<PopoverContent>?
        private var shouldBePresented = false
        private var preferredEdge: NSRectEdge?
        private weak var anchorView: NSView?
        private weak var observedWindow: NSWindow?
        private var notificationTokens: [NSObjectProtocol] = []
        private var currentEdge: NSRectEdge?
        private var lastAnchorRectOnScreen: CGRect?
        private var lastAvailableRect: CGRect?
        private var lastPopoverSize: CGSize?

        func update(
            isPresented: Bool,
            preferredEdge: NSRectEdge?,
            anchorView: NSView,
            content: PopoverContent
        ) {
            shouldBePresented = isPresented
            self.preferredEdge = preferredEdge
            self.anchorView = anchorView

            guard isPresented else {
                close()
                return
            }

            if let hostingController {
                hostingController.rootView = content
            } else {
                let controller = NSHostingController(rootView: content)
                let popover = NSPopover()
                popover.behavior = .applicationDefined
                popover.animates = true
                popover.contentViewController = controller
                self.hostingController = controller
                self.popover = popover
            }

            observeGeometryChanges(for: anchorView)
            showWhenAttached(to: anchorView)
        }

        func close() {
            shouldBePresented = false
            popover?.close()
            currentEdge = nil
            lastAnchorRectOnScreen = nil
            lastAvailableRect = nil
            lastPopoverSize = nil
            stopObservingGeometryChanges()
        }

        private func showWhenAttached(to anchorView: NSView) {
            guard let popover else { return }
            guard let window = anchorView.window else {
                DispatchQueue.main.async { [weak self, weak anchorView] in
                    guard let self, let anchorView, self.shouldBePresented else { return }
                    self.observeGeometryChanges(for: anchorView)
                    self.showWhenAttached(to: anchorView)
                }
                return
            }

            let placement = placement(for: anchorView, in: window, popover: popover)
            let edge = placement.edge
            if popover.isShown {
                let geometryChanged = lastAnchorRectOnScreen != placement.anchorRectOnScreen
                    || lastAvailableRect != placement.availableRect
                    || lastPopoverSize != placement.popoverSize
                guard geometryChanged || currentEdge != edge else { return }

                lastAnchorRectOnScreen = placement.anchorRectOnScreen
                lastAvailableRect = placement.availableRect
                lastPopoverSize = placement.popoverSize
                if currentEdge == edge {
                    popover.positioningRect = anchorView.bounds
                    return
                }
                popover.close()
            }

            currentEdge = edge
            lastAnchorRectOnScreen = placement.anchorRectOnScreen
            lastAvailableRect = placement.availableRect
            lastPopoverSize = placement.popoverSize
            popover.show(
                relativeTo: anchorView.bounds,
                of: anchorView,
                preferredEdge: edge
            )
        }

        private func placement(
            for anchorView: NSView,
            in window: NSWindow,
            popover: NSPopover
        ) -> (edge: NSRectEdge, anchorRectOnScreen: CGRect, availableRect: CGRect, popoverSize: CGSize) {
            let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let anchorRectOnScreen = window.convertToScreen(anchorRectInWindow)
            let screen = window.screen ?? NSScreen.main
            let visibleScreenRect: CGRect
            if let screen {
                visibleScreenRect = screen.visibleFrame
            } else {
                visibleScreenRect = window.frame
            }
            let availableRect = window.frame.intersection(visibleScreenRect).insetBy(dx: 12, dy: 12)
            let contentSize = popover.contentSize == .zero
                ? CGSize(width: 350, height: 200)
                : popover.contentSize

            let edge = PersistentPopoverPlacement.preferredEdge(
                anchorRect: anchorRectOnScreen,
                availableRect: availableRect,
                popoverSize: contentSize,
                preferredEdge: preferredEdge
            )
            return (edge, anchorRectOnScreen, availableRect, contentSize)
        }

        private func observeGeometryChanges(for anchorView: NSView) {
            guard let window = anchorView.window, observedWindow !== window else { return }
            stopObservingGeometryChanges()
            observedWindow = window

            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.didChangeBackingPropertiesNotification
            ]
            notificationTokens = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let anchorView = self.anchorView, self.shouldBePresented else { return }
                        self.showWhenAttached(to: anchorView)
                    }
                }
            }
        }

        private func stopObservingGeometryChanges() {
            let center = NotificationCenter.default
            notificationTokens.forEach(center.removeObserver)
            notificationTokens.removeAll()
            observedWindow = nil
        }
    }
}

extension View {
    func onboardingTooltip(
        tip: OnboardingTipID,
        isPresented: Bool,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(OnboardingTooltipModifier(
            tip: tip,
            isPresented: isPresented,
            onDismiss: onDismiss
        ))
    }
}

final class WifiHeatmapApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        BlankDocumentLaunchPolicy.opensUntitledDocumentByDefault
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        var approvedProxies: [WindowCloseDelegateProxy] = []
        for window in sender.windows where window.isVisible {
            guard let proxy = window.delegate as? WindowCloseDelegateProxy else { continue }
            if !proxy.requestClose(window) {
                approvedProxies.forEach { $0.resetCloseApproval() }
                return .terminateCancel
            }
            approvedProxies.append(proxy)
        }
        return .terminateNow
    }
}

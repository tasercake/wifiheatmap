import SwiftUI

struct ContentView: View {
    @ObservedObject var document: WifiSurveyDocument
    let fileURL: URL?
    @State private var selectedFloorID: UUID? = nil
    @State private var showInspector: Bool = true
    @StateObject private var locationAuth = LocationAuthManager()
    private let scanActor = ScanActor.shared
    @State private var latestBatch: [ScannedNetwork] = []
    @State private var latestScanAt: Date? = nil
    @State private var isScanning = false

    private var selectedFloorIndex: Int? {
        document.survey.floors.firstIndex(where: { $0.id == selectedFloorID })
    }

    var body: some View {
        VStack(spacing: 0) {
            FloorTabBar(
                document: document,
                selectedFloorID: $selectedFloorID,
                showInspector: $showInspector
            )

            if let idx = selectedFloorIndex {
                FloorDetailView(
                    document: document,
                    floor: $document.survey.floors[idx],
                    latestBatch: latestBatch,
                    latestScanAt: latestScanAt,
                    isScanning: isScanning,
                    scanForReading: scanForReading,
                    showInspector: $showInspector
                )
            } else {
                Text("Add a floor using the \u{2060}+\u{2060} button above.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        .task(id: fileURL) {
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
    }

    private func scanForReading(attempt: Int) async throws -> ScanBatch {
        isScanning = true
        defer { isScanning = false }

        let batch = try await scanActor.scanOnce(attemptCount: attempt)
        latestBatch = batch.networks
        latestScanAt = batch.completedAt
        return batch
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

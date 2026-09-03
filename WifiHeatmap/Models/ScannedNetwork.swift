import Foundation

struct ScannedNetwork {
    var ssid: String
    var bssid: String
    var rssi: Int
    var noise: Int
    var band: WiFiBand
    var channel: Int
}

struct ScanSnapshot: Equatable {
    struct Entry: Equatable {
        let bssid: String
        let rssi: Int
        let noise: Int
    }

    let entries: [Entry]

    init(networks: [ScannedNetwork]) {
        entries = networks
            .map { Entry(bssid: $0.bssid, rssi: $0.rssi, noise: $0.noise) }
            .sorted {
                if $0.bssid != $1.bssid { return $0.bssid < $1.bssid }
                if $0.rssi != $1.rssi { return $0.rssi < $1.rssi }
                return $0.noise < $1.noise
            }
    }
}

struct ScanBatch {
    let networks: [ScannedNetwork]
    let startedAt: Date
    let completedAt: Date
    let scanCacheUpdated: Bool
    let snapshotChanged: Bool?
    let attemptCount: Int

    var duration: TimeInterval {
        max(0, completedAt.timeIntervalSince(startedAt))
    }
}

enum FullScanPoint {
    static func record(
        at position: CGPoint,
        id: UUID = UUID(),
        scan: () async throws -> ScanBatch
    ) async throws -> SurveyPoint {
        let batch = try await scan()
        return SurveyPoint(
            id: id,
            position: position,
            startedAt: batch.startedAt,
            completedAt: batch.completedAt,
            scanCacheUpdated: batch.scanCacheUpdated,
            snapshotChanged: batch.snapshotChanged,
            attemptCount: batch.attemptCount,
            readings: batch.networks.map {
                WifiNetworkReading(
                    ssid: $0.ssid,
                    bssid: $0.bssid,
                    rssi: $0.rssi,
                    noise: $0.noise,
                    band: $0.band,
                    channel: $0.channel
                )
            }
        )
    }
}

enum ScanRetryPolicy {
    static let unusuallyFastThreshold: TimeInterval = 0.75

    static func shouldRetry(_ batch: ScanBatch) -> Bool {
        batch.duration < unusuallyFastThreshold
            && batch.snapshotChanged == false
            && !batch.scanCacheUpdated
    }
}

struct CaptureRequirements: Equatable {
    let requiredSSIDs: Set<String>
    let requiredBSSIDs: Set<String>
    let requiredBSSIDBands: [String: WiFiBand]
    let trackedBands: Set<WiFiBand>

    init(
        requiredSSIDs: Set<String>,
        requiredBSSIDs: Set<String>,
        requiredBSSIDBands: [String: WiFiBand] = [:],
        trackedBands: Set<WiFiBand>
    ) {
        self.requiredSSIDs = requiredSSIDs
        self.requiredBSSIDs = requiredBSSIDs
        self.requiredBSSIDBands = requiredBSSIDBands
        self.trackedBands = trackedBands
    }
}

enum CaptureRetryReason: Equatable {
    case potentiallyStale
    case missingSSIDs(Set<String>)
    case missingBSSIDs(Set<String>)
    case missingBands(Set<WiFiBand>)
    case scanFailed(String)

    var message: String {
        switch self {
        case .potentiallyStale:
            return "Results may be cached"
        case .missingSSIDs(let ssids):
            return "Missing network: \(ssids.sorted().joined(separator: ", "))"
        case .missingBSSIDs(let bssids):
            return "Missing access point: \(bssids.sorted().joined(separator: ", "))"
        case .missingBands(let bands):
            return "Missing required band data: \(bands.sorted { $0.displayName < $1.displayName }.map(\.displayName).joined(separator: ", "))"
        case .scanFailed(let message):
            return message
        }
    }
}

enum CaptureProgress: Equatable {
    case scanning(attempt: Int, maxAttempts: Int)
    case retrying(reason: CaptureRetryReason, nextAttempt: Int, maxAttempts: Int)
}

struct PointCaptureError: LocalizedError, Equatable {
    let reason: CaptureRetryReason
    let attempts: Int

    var errorDescription: String? {
        "No complete reading after \(attempts) attempts. \(reason.message)."
    }
}

enum PointCaptureCoordinator {
    static let maximumAttempts = 4
    static let standardBackoffNanoseconds: [UInt64] = [500_000_000, 1_000_000_000, 2_000_000_000]

    static func capture(
        at position: CGPoint,
        id: UUID = UUID(),
        requirements: CaptureRequirements,
        maxAttempts: Int = maximumAttempts,
        backoffNanoseconds: [UInt64] = standardBackoffNanoseconds,
        scan: (Int) async throws -> ScanBatch,
        sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        onProgress: (CaptureProgress) -> Void = { _ in }
    ) async throws -> SurveyPoint {
        guard !requirements.trackedBands.isEmpty else {
            throw PointCaptureError(reason: .missingBands([]), attempts: 0)
        }

        var lastReason = CaptureRetryReason.scanFailed("The scan did not run")
        let attemptLimit = max(1, maxAttempts)

        for attempt in 1...attemptLimit {
            onProgress(.scanning(attempt: attempt, maxAttempts: attemptLimit))
            do {
                let batch = try await scan(attempt)
                if let reason = rejectionReason(for: batch, requirements: requirements) {
                    lastReason = reason
                } else {
                    let trackedNetworks = batch.networks.filter { requirements.trackedBands.contains($0.band) }
                    let acceptedBatch = ScanBatch(
                        networks: trackedNetworks,
                        startedAt: batch.startedAt,
                        completedAt: batch.completedAt,
                        scanCacheUpdated: batch.scanCacheUpdated,
                        snapshotChanged: batch.snapshotChanged,
                        attemptCount: attempt
                    )
                    return try await FullScanPoint.record(at: position, id: id) { acceptedBatch }
                }
            } catch ScanActor.ScanError.interfaceUnavailable {
                throw ScanActor.ScanError.interfaceUnavailable
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastReason = .scanFailed(error.localizedDescription)
            }

            guard attempt < attemptLimit else {
                throw PointCaptureError(reason: lastReason, attempts: attempt)
            }
            onProgress(.retrying(reason: lastReason, nextAttempt: attempt + 1, maxAttempts: attemptLimit))
            let delayIndex = min(attempt - 1, max(0, backoffNanoseconds.count - 1))
            if !backoffNanoseconds.isEmpty {
                try await sleep(backoffNanoseconds[delayIndex])
            }
        }

        throw PointCaptureError(reason: lastReason, attempts: attemptLimit)
    }

    static func rejectionReason(
        for batch: ScanBatch,
        requirements: CaptureRequirements
    ) -> CaptureRetryReason? {
        if ScanRetryPolicy.shouldRetry(batch) {
            return .potentiallyStale
        }

        let tracked = batch.networks.filter { requirements.trackedBands.contains($0.band) }
        let presentSSIDs = Set(tracked.map(\.ssid))
        let missingSSIDs = requirements.requiredSSIDs.subtracting(presentSSIDs)
        if !missingSSIDs.isEmpty {
            return .missingSSIDs(missingSSIDs)
        }

        let applicableBSSIDs = requirements.requiredBSSIDs.filter { bssid in
            guard let band = requirements.requiredBSSIDBands[bssid] else { return true }
            return requirements.trackedBands.contains(band)
        }
        let missingBSSIDs = applicableBSSIDs.filter { bssid in
            guard let knownBand = requirements.requiredBSSIDBands[bssid] else {
                return !tracked.contains { $0.bssid == bssid }
            }
            return !tracked.contains { $0.bssid == bssid && $0.band == knownBand }
        }
        if !missingBSSIDs.isEmpty {
            return .missingBSSIDs(Set(missingBSSIDs))
        }

        let missingBands = requirements.trackedBands.filter { band in
            if requirements.requiredSSIDs.isEmpty {
                return !tracked.contains { $0.band == band }
            }
            return requirements.requiredSSIDs.contains { requiredSSID in
                !tracked.contains { $0.band == band && $0.ssid == requiredSSID }
            }
        }
        if !missingBands.isEmpty {
            return .missingBands(Set(missingBands))
        }

        return nil
    }
}

struct SignalUpdateStatus {
    enum Freshness: Equatable {
        case noSignal
        case readyToLog
        case waitingForNewScan
        case freshScanAvailable
    }

    let latestScanAt: Date?
    let lastTaggedAt: Date?

    var freshness: Freshness {
        guard let latestScanAt else { return .noSignal }
        guard let lastTaggedAt else { return .readyToLog }
        return latestScanAt > lastTaggedAt ? .freshScanAvailable : .waitingForNewScan
    }

    func updatedText(at now: Date) -> String {
        guard let latestScanAt else { return "No scan received yet" }
        let elapsed = max(0, Int(now.timeIntervalSince(latestScanAt)))
        if elapsed < 2 { return "Updated just now" }
        if elapsed < 60 { return "Updated \(elapsed)s ago" }
        if elapsed < 3_600 { return "Updated \(elapsed / 60)m ago" }
        return "Updated \(elapsed / 3_600)h ago"
    }
}

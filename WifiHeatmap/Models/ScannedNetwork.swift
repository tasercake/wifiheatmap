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
        orientationDegrees: Double? = nil,
        id: UUID = UUID(),
        scan: () async throws -> ScanBatch
    ) async throws -> SurveyPoint {
        let batch = try await scan()
        return SurveyPoint(
            id: id,
            position: position,
            orientationDegrees: orientationDegrees,
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
    // CoreWLAN can deliver the cache-update event shortly after scanForNetworks returns.
    // Give the event callback a meaningful grace period before treating the batch as cached.
    static let cacheEventWaitTimeout: TimeInterval = 1.0

    static func shouldRetry(_ batch: ScanBatch) -> Bool {
        !batch.scanCacheUpdated
    }
}

enum NetworkDiscoveryCoordinator {
    static func refresh(
        maxAttempts: Int = PointCaptureCoordinator.maximumAttempts,
        cacheRefreshBackoffNanoseconds: [UInt64] = PointCaptureCoordinator.standardCacheRefreshBackoffNanoseconds,
        scan: (Int) async throws -> ScanBatch,
        sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async throws -> ScanBatch {
        let attemptLimit = max(1, maxAttempts)
        var latestSuccessfulBatch: ScanBatch?
        var latestError: Error?

        for attempt in 1...attemptLimit {
            do {
                let batch = try await scan(attempt)
                latestSuccessfulBatch = batch
                if !ScanRetryPolicy.shouldRetry(batch) {
                    return batch
                }
            } catch ScanActor.ScanError.interfaceUnavailable {
                throw ScanActor.ScanError.interfaceUnavailable
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                latestError = error
            }

            guard attempt < attemptLimit else { break }
            let delayIndex = min(attempt - 1, max(0, cacheRefreshBackoffNanoseconds.count - 1))
            if !cacheRefreshBackoffNanoseconds.isEmpty {
                try await sleep(cacheRefreshBackoffNanoseconds[delayIndex])
            }
        }

        if let latestSuccessfulBatch { return latestSuccessfulBatch }
        throw latestError ?? ScanActor.ScanError.failed("Wi-Fi discovery scan did not return a result")
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

    var effectiveRecordBands: Set<WiFiBand> {
        RecordBandPolicy.normalizedRecordBands(
            trackedBands,
            selectedBSSIDs: requiredBSSIDs,
            knownBSSIDBands: requiredBSSIDBands
        )
    }

    func recordBands(for networks: [ScannedNetwork]) -> Set<WiFiBand> {
        effectiveRecordBands.union(
            networks.compactMap { network in
                requiredBSSIDs.contains(network.bssid) ? network.band : nil
            }
        )
    }
}

enum RecordBandPolicy {
    static func requiredBands(
        selectedBSSIDs: Set<String>,
        knownBSSIDBands: [String: WiFiBand]
    ) -> Set<WiFiBand> {
        Set(selectedBSSIDs.compactMap { knownBSSIDBands[$0] })
    }

    static func normalizedRecordBands(
        _ recordBands: Set<WiFiBand>,
        selectedBSSIDs: Set<String>,
        knownBSSIDBands: [String: WiFiBand]
    ) -> Set<WiFiBand> {
        recordBands.union(requiredBands(
            selectedBSSIDs: selectedBSSIDs,
            knownBSSIDBands: knownBSSIDBands
        ))
    }
}

enum CaptureRetryReason: Equatable {
    case potentiallyStale
    case missingSSIDs(Set<String>)
    case missingBSSIDs(Set<String>)
    case missingRequirements(ssids: Set<String>, bssids: Set<String>)
    case noRecordBandsSelected
    case noNetworksOnRecordBands(Set<WiFiBand>)
    case scanFailed(String)

    var message: String {
        switch self {
        case .potentiallyStale:
            return "Results may be cached"
        case .missingSSIDs(let ssids):
            return "Missing required SSID: \(ssids.sorted().joined(separator: ", "))"
        case .missingBSSIDs(let bssids):
            return "Missing required BSSID: \(bssids.sorted().joined(separator: ", "))"
        case .missingRequirements(let ssids, let bssids):
            return [
                Self.missingSSIDMessage(ssids),
                Self.missingBSSIDMessage(bssids)
            ].joined(separator: " · ")
        case .noRecordBandsSelected:
            return "Select at least one Record Band"
        case .noNetworksOnRecordBands(let bands):
            let names = bands
                .sorted { $0.displayName < $1.displayName }
                .map(\.displayName)
                .joined(separator: ", ")
            return "No networks were observed on the selected Record Bands: \(names)"
        case .scanFailed(let message):
            return message
        }
    }

    var summaryLines: [String] {
        switch self {
        case .missingRequirements(let ssids, let bssids):
            return [Self.missingSSIDMessage(ssids), Self.missingBSSIDMessage(bssids)]
        default:
            return [message]
        }
    }

    private static func missingSSIDMessage(_ ssids: Set<String>) -> String {
        "Missing required SSID: \(ssids.sorted().joined(separator: ", "))"
    }

    private static func missingBSSIDMessage(_ bssids: Set<String>) -> String {
        "Missing required BSSID: \(bssids.sorted().joined(separator: ", "))"
    }
}

enum CaptureProgress: Equatable {
    case scanning(attempt: Int, maxAttempts: Int)
    case retrying(
        reason: CaptureRetryReason,
        nextAttempt: Int,
        maxAttempts: Int,
        delayNanoseconds: UInt64
    )
}

struct PointCaptureError: LocalizedError, Equatable {
    let reason: CaptureRetryReason
    let attempts: Int

    var errorDescription: String? {
        (["No complete reading after \(attempts) attempts."] + reason.summaryLines)
            .joined(separator: "\n")
    }
}

enum RetryCountdown {
    static func secondsRemaining(until retryAt: Date, at now: Date) -> Int {
        max(0, Int(ceil(retryAt.timeIntervalSince(now))))
    }
}

enum PointCaptureCoordinator {
    static let maximumAttempts = 5
    static let minimumRetryDelayNanoseconds: UInt64 = 5_000_000_000
    static let standardBackoffNanoseconds: [UInt64] = Array(
        repeating: minimumRetryDelayNanoseconds,
        count: maximumAttempts - 1
    )
    static let standardCacheRefreshBackoffNanoseconds = standardBackoffNanoseconds

    static func capture(
        at position: CGPoint,
        orientationDegrees: Double? = nil,
        id: UUID = UUID(),
        requirements: CaptureRequirements,
        maxAttempts: Int = maximumAttempts,
        backoffNanoseconds: [UInt64] = standardBackoffNanoseconds,
        cacheRefreshBackoffNanoseconds: [UInt64] = standardCacheRefreshBackoffNanoseconds,
        scan: (Int) async throws -> ScanBatch,
        sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        onProgress: (CaptureProgress) -> Void = { _ in }
    ) async throws -> SurveyPoint {
        guard !requirements.effectiveRecordBands.isEmpty else {
            throw PointCaptureError(reason: .noRecordBandsSelected, attempts: 0)
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
                    let recordBands = requirements.recordBands(for: batch.networks)
                    let trackedNetworks = batch.networks.filter { recordBands.contains($0.band) }
                    let acceptedBatch = ScanBatch(
                        networks: trackedNetworks,
                        startedAt: batch.startedAt,
                        completedAt: batch.completedAt,
                        scanCacheUpdated: batch.scanCacheUpdated,
                        snapshotChanged: batch.snapshotChanged,
                        attemptCount: attempt
                    )
                    return try await FullScanPoint.record(
                        at: position,
                        orientationDegrees: orientationDegrees,
                        id: id
                    ) { acceptedBatch }
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
            let retryDelays = lastReason == .potentiallyStale
                ? cacheRefreshBackoffNanoseconds
                : backoffNanoseconds
            let configuredDelay = retryDelays.isEmpty
                ? minimumRetryDelayNanoseconds
                : retryDelays[min(attempt - 1, retryDelays.count - 1)]
            let delay = max(minimumRetryDelayNanoseconds, configuredDelay)
            onProgress(.retrying(
                reason: lastReason,
                nextAttempt: attempt + 1,
                maxAttempts: attemptLimit,
                delayNanoseconds: delay
            ))
            try await sleep(delay)
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

        let recordBands = requirements.recordBands(for: batch.networks)
        let tracked = batch.networks.filter { recordBands.contains($0.band) }
        if tracked.isEmpty {
            return .noNetworksOnRecordBands(recordBands)
        }

        let presentSSIDs = Set(tracked.map(\.ssid))
        let missingSSIDs = requirements.requiredSSIDs.subtracting(presentSSIDs)
        let missingBSSIDs = requirements.requiredBSSIDs.filter { bssid in
            !tracked.contains { $0.bssid == bssid }
        }

        if !missingSSIDs.isEmpty && !missingBSSIDs.isEmpty {
            return .missingRequirements(ssids: missingSSIDs, bssids: Set(missingBSSIDs))
        }
        if !missingSSIDs.isEmpty {
            return .missingSSIDs(missingSSIDs)
        }
        if !missingBSSIDs.isEmpty {
            return .missingBSSIDs(Set(missingBSSIDs))
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

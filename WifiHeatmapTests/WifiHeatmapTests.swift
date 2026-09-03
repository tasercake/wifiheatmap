import XCTest
@testable import WifiHeatmap

final class WifiHeatmapTests: XCTestCase {

    func testBottomStatusBarHasAStableFootprint() {
        XCTAssertEqual(BottomStatusBarLayout.height, 112)
        XCTAssertEqual(BottomStatusBarLayout.statusCardWidth, 440)
        XCTAssertEqual(BottomStatusBarLayout.statusCardHeight, 96)
        XCTAssertGreaterThanOrEqual(
            BottomStatusBarLayout.height,
            BottomStatusBarLayout.statusCardHeight + 16
        )
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

    func testRetryPolicyRetriesOnlyFastUnchangedScansWithoutCacheUpdateEvent() {
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
        XCTAssertFalse(ScanRetryPolicy.shouldRetry(batch(duration: 1.0)))
        XCTAssertFalse(ScanRetryPolicy.shouldRetry(batch(cacheUpdated: true)))
        XCTAssertFalse(ScanRetryPolicy.shouldRetry(batch(snapshotChanged: true)))
        XCTAssertFalse(ScanRetryPolicy.shouldRetry(batch(snapshotChanged: nil)))
    }

    func testCaptureRetriesUntilEveryRequiredSSIDExistsOnEveryTrackedBand() async throws {
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
                let networks = attempt == 1
                    ? [self.network("Home", "home-2", .ghz2_4), self.network("Home", "home-5", .ghz5)]
                    : [
                        self.network("Home", "home-2", .ghz2_4),
                        self.network("Office", "office-2", .ghz2_4),
                        self.network("Home", "home-5", .ghz5),
                        self.network("Office", "office-5", .ghz5),
                        self.network("Guest", "guest-6", .ghz6)
                    ]
                return self.batch(networks, attempt: attempt)
            },
            sleep: { _ in },
            onProgress: { progress.append($0) }
        )

        XCTAssertEqual(attempts, [1, 2])
        XCTAssertEqual(point.attemptCount, 2)
        XCTAssertEqual(Set(point.readings.map(\.ssid)), ["Home", "Office"])
        XCTAssertFalse(point.readings.contains { $0.band == .ghz6 })
        XCTAssertTrue(progress.contains(.retrying(reason: .missingSSIDs(["Office"]), nextAttempt: 2, maxAttempts: 4)))
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

    func testBSSIDKnownToBelongToDisabledBandIsNotRequired() async throws {
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
                return self.batch([self.network("Home", "home-5", .ghz5)], attempt: attempt)
            },
            sleep: { _ in }
        )

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(point.readings.map(\.bssid), ["home-5"])
    }

    func testCaptureWithAllSelectionsRequiresAtLeastOneReadingPerTrackedBand() async throws {
        let requirements = CaptureRequirements(
            requiredSSIDs: [], requiredBSSIDs: [], trackedBands: [.ghz2_4, .ghz5, .ghz6]
        )
        var attempts = 0

        _ = try await PointCaptureCoordinator.capture(
            at: .zero,
            requirements: requirements,
            backoffNanoseconds: [0, 0, 0],
            scan: { attempt in
                attempts += 1
                var networks = [
                    self.network("Home", "home-2", .ghz2_4),
                    self.network("Home", "home-5", .ghz5)
                ]
                if attempt == 2 { networks.append(self.network("Home", "home-6", .ghz6)) }
                return self.batch(networks, attempt: attempt)
            },
            sleep: { _ in }
        )

        XCTAssertEqual(attempts, 2)
    }

    func testCaptureRetriesSuspiciouslyStaleResult() async throws {
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
                    cacheUpdated: false,
                    snapshotChanged: false
                )
            },
            sleep: { _ in }
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(point.attemptCount, 2)
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
        XCTAssertEqual(delays, [500, 1_000])
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
            requiredSSIDs: ["Home"], requiredBSSIDs: [], trackedBands: [.ghz2_4, .ghz5]
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
                        ? self.network("Home", "home-5", .ghz5)
                        : self.network("Home", "home-2", .ghz2_4)
                    return self.batch([network], attempt: attempt)
                },
                sleep: { _ in }
            )
            XCTFail("Expected atomic failure rather than merged readings")
        } catch let error as PointCaptureError {
            XCTAssertEqual(attempts, 4)
            XCTAssertEqual(error.attempts, 4)
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

}

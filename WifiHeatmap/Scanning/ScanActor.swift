import CoreWLAN
import Foundation

private final class ScanCacheEventMonitor: NSObject, CWEventDelegate {
    private let condition = NSCondition()
    private var generation = 0

    func token() -> Int {
        condition.lock()
        defer { condition.unlock() }
        return generation
    }

    func scanCacheUpdatedForWiFiInterface(withName interfaceName: String) {
        condition.lock()
        generation += 1
        condition.broadcast()
        condition.unlock()
    }

    func didUpdate(after token: Int, waiting timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        if generation == token {
            condition.wait(until: Date().addingTimeInterval(timeout))
        }
        return generation != token
    }
}

actor ScanActor {
    static let shared = ScanActor()

    enum ScanError: Swift.Error, LocalizedError {
        case interfaceUnavailable
        case noNetworksFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .interfaceUnavailable:
                return "No WiFi interface is available."
            case .noNetworksFound:
                return "The scan completed without finding any networks."
            case .failed(let message):
                return "WiFi scan failed: \(message)"
            }
        }
    }

    private let client: CWWiFiClient
    private let eventMonitor: ScanCacheEventMonitor
    private let isMonitoringScanCache: Bool
    private(set) var isScanning = false
    private var previousSnapshot: ScanSnapshot?

    private init() {
        let client = CWWiFiClient.shared()
        let eventMonitor = ScanCacheEventMonitor()
        self.client = client
        self.eventMonitor = eventMonitor
        client.delegate = eventMonitor

        do {
            try client.startMonitoringEvent(with: .scanCacheUpdated)
            isMonitoringScanCache = true
        } catch {
            isMonitoringScanCache = false
        }
    }

    func scanOnce(attemptCount: Int) throws -> ScanBatch {
        isScanning = true
        defer { isScanning = false }

        let batch = try performScan(attemptCount: attemptCount)
        previousSnapshot = ScanSnapshot(networks: batch.networks)
        return batch
    }

    private func performScan(attemptCount: Int) throws -> ScanBatch {
        guard let interface = client.interface() else {
            throw ScanError.interfaceUnavailable
        }

        let startedAt = Date()
        let eventToken = eventMonitor.token()

        do {
            let networks = try interface.scanForNetworks(withSSID: nil)
            let batch = networks.compactMap { Self.map($0) }
            guard !batch.isEmpty else { throw ScanError.noNetworksFound }
            let completedAt = Date()
            let snapshot = ScanSnapshot(networks: batch)
            let snapshotChanged = previousSnapshot.map { $0 != snapshot }
            let scanCacheUpdated = isMonitoringScanCache
                && eventMonitor.didUpdate(after: eventToken, waiting: 0.15)

            return ScanBatch(
                networks: batch,
                startedAt: startedAt,
                completedAt: completedAt,
                scanCacheUpdated: scanCacheUpdated,
                snapshotChanged: snapshotChanged,
                attemptCount: attemptCount
            )
        } catch let error as ScanError {
            throw error
        } catch {
            throw ScanError.failed(error.localizedDescription)
        }
    }

    private static func map(_ network: CWNetwork) -> ScannedNetwork? {
        guard let bssid = network.bssid,
              let ssid  = network.ssid,
              let ch    = network.wlanChannel else { return nil }

        let band: WiFiBand
        switch ch.channelBand {
        case .band2GHz: band = .ghz2_4
        case .band5GHz: band = .ghz5
        case .band6GHz: band = .ghz6
        default: return nil
        }

        return ScannedNetwork(
            ssid:    ssid,
            bssid:   bssid,
            rssi:    network.rssiValue,
            noise:   network.noiseMeasurement,
            band:    band,
            channel: ch.channelNumber
        )
    }
}

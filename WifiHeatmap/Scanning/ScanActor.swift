import CoreWLAN

actor ScanActor {
    private let client = CWWiFiClient.shared()
    private(set) var isScanning = false
    private var scanTask: Task<Void, Never>?

    func startScanning() -> AsyncStream<[ScannedNetwork]> {
        isScanning = true
        let (stream, continuation) = AsyncStream<[ScannedNetwork]>.makeStream()

        scanTask = Task {
            while !Task.isCancelled {
                guard let interface = self.client.interface() else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                do {
                    let networks = try interface.scanForNetworks(withSSID: nil)
                    let batch = networks.compactMap { Self.map($0) }
                    if !batch.isEmpty {
                        continuation.yield(batch)
                    }
                } catch {
                    // scan failed; loop immediately to retry
                }
            }
            continuation.finish()
        }

        return stream
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
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
            ssid:  ssid,
            bssid: bssid,
            rssi:  network.rssiValue,
            noise: network.noiseMeasurement,
            band:  band
        )
    }
}

import Foundation

struct WifiSurvey: Codable, Equatable {
    var name: String
    var floors: [Floor]
    var scanSets: [ScanSet]
    var activeScanID: UUID?
    var viewSettings: SurveyViewSettings

    init(
        name: String,
        floors: [Floor],
        scanSets: [ScanSet] = [],
        activeScanID: UUID? = nil,
        viewSettings: SurveyViewSettings = .standard
    ) {
        self.name = name
        self.floors = floors
        self.scanSets = scanSets
        self.activeScanID = scanSets.contains(where: { $0.id == activeScanID }) ? activeScanID : nil
        self.viewSettings = viewSettings
    }

    private enum CodingKeys: String, CodingKey {
        case name, floors, scanSets, activeScanID, viewSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        floors = try container.decode([Floor].self, forKey: .floors)
        let floorIDs = floors.map(\.id)
        scanSets = try container.decodeIfPresent([ScanSet].self, forKey: .scanSets)?
            .map { $0.normalized(for: floorIDs) } ?? []
        let decodedActiveScanID = try container.decodeIfPresent(UUID.self, forKey: .activeScanID)
        activeScanID = scanSets.contains(where: { $0.id == decodedActiveScanID })
            ? decodedActiveScanID
            : nil
        viewSettings = try container.decodeIfPresent(SurveyViewSettings.self, forKey: .viewSettings) ?? .standard
    }
}

struct ScanFloor: Codable, Equatable {
    var floorID: UUID
    var points: [SurveyPoint]
}

struct ScanSet: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var floors: [ScanFloor]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        floorIDs: [UUID]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        floors = floorIDs.map { ScanFloor(floorID: $0, points: []) }
    }

    func points(for floorID: UUID) -> [SurveyPoint] {
        floors.first(where: { $0.floorID == floorID })?.points ?? []
    }

    @discardableResult
    mutating func replacePoints(_ points: [SurveyPoint], for floorID: UUID) -> Bool {
        guard let index = floors.firstIndex(where: { $0.floorID == floorID }) else {
            return false
        }
        floors[index].points = points
        return true
    }

    mutating func addFloor(_ floorID: UUID) {
        guard !floors.contains(where: { $0.floorID == floorID }) else { return }
        floors.append(ScanFloor(floorID: floorID, points: []))
    }

    mutating func removeFloor(_ floorID: UUID) {
        floors.removeAll { $0.floorID == floorID }
    }

    func normalized(for floorIDs: [UUID]) -> ScanSet {
        var normalized = self
        let validFloorIDs = Set(floorIDs)
        normalized.floors.removeAll { !validFloorIDs.contains($0.floorID) }
        for floorID in floorIDs {
            normalized.addFloor(floorID)
        }
        return normalized
    }
}

struct SurveyViewSettings: Codable, Equatable {
    var requiredSSIDs: Set<String>
    var requiredBSSIDs: Set<String>
    var trackedBands: Set<WiFiBand>
    var displayBand: WiFiBand
    var displaySSID: String?
    var displayBSSIDs: Set<String>
    var showHeatmap: Bool
    var showContours: Bool
    var contourSmoothingMeters: Double
    var metric: HeatmapMetric
    var colorScheme: HeatmapColorScheme
    var fadeRadius: Double
    var rssiRange: HeatmapValueRange
    var snrRange: HeatmapValueRange

    init(
        requiredSSIDs: Set<String>,
        requiredBSSIDs: Set<String>,
        trackedBands: Set<WiFiBand>,
        displayBand: WiFiBand,
        displaySSID: String?,
        displayBSSIDs: Set<String>,
        showHeatmap: Bool,
        showContours: Bool = false,
        contourSmoothingMeters: Double = 1.0,
        metric: HeatmapMetric,
        colorScheme: HeatmapColorScheme,
        fadeRadius: Double,
        rssiRange: HeatmapValueRange = HeatmapMetric.rssi.defaultValueRange,
        snrRange: HeatmapValueRange = HeatmapMetric.snr.defaultValueRange
    ) {
        self.requiredSSIDs = requiredSSIDs
        self.requiredBSSIDs = requiredBSSIDs
        self.trackedBands = trackedBands.isEmpty ? Set(WiFiBand.allCases) : trackedBands
        self.displayBand = displayBand
        self.displaySSID = displaySSID
        self.displayBSSIDs = displayBSSIDs
        self.showHeatmap = showHeatmap
        self.showContours = showContours
        self.contourSmoothingMeters = max(0, min(3, contourSmoothingMeters))
        self.metric = metric
        self.colorScheme = colorScheme
        self.fadeRadius = fadeRadius
        self.rssiRange = rssiRange
        self.snrRange = snrRange
    }

    private enum CodingKeys: String, CodingKey {
        case requiredSSIDs, requiredBSSIDs, trackedBands
        case displayBand, displaySSID, displayBSSIDs
        case selectedSSIDs, selectedBSSIDs
        case selectedSSID, selectedBSSID
        case activeBand, showHeatmap, showContours, contourSmoothingMeters, metric
        case colorScheme, fadeRadius, rssiRange, snrRange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.standard
        requiredSSIDs = try container.decodeIfPresent(Set<String>.self, forKey: .requiredSSIDs)
            ?? container.decodeIfPresent(Set<String>.self, forKey: .selectedSSIDs)
            ?? container.decodeIfPresent(String.self, forKey: .selectedSSID).map { [$0] }
            ?? []
        requiredBSSIDs = try container.decodeIfPresent(Set<String>.self, forKey: .requiredBSSIDs)
            ?? container.decodeIfPresent(Set<String>.self, forKey: .selectedBSSIDs)
            ?? container.decodeIfPresent(String.self, forKey: .selectedBSSID).map { [$0] }
            ?? []
        let decodedBands = try container.decodeIfPresent(Set<WiFiBand>.self, forKey: .trackedBands)
        if let decodedBands, !decodedBands.isEmpty {
            trackedBands = decodedBands
        } else {
            trackedBands = Set(WiFiBand.allCases)
        }
        displayBand = try container.decodeIfPresent(WiFiBand.self, forKey: .displayBand)
            ?? container.decodeIfPresent(WiFiBand.self, forKey: .activeBand)
            ?? defaults.displayBand
        if container.contains(.displaySSID) {
            displaySSID = try container.decodeIfPresent(String.self, forKey: .displaySSID)
        } else {
            displaySSID = requiredSSIDs.count == 1 ? requiredSSIDs.first : nil
        }
        if container.contains(.displayBSSIDs) {
            displayBSSIDs = try container.decodeIfPresent(Set<String>.self, forKey: .displayBSSIDs) ?? []
        } else {
            displayBSSIDs = displaySSID == nil ? [] : requiredBSSIDs
        }
        showHeatmap = try container.decodeIfPresent(Bool.self, forKey: .showHeatmap) ?? defaults.showHeatmap
        showContours = try container.decodeIfPresent(Bool.self, forKey: .showContours) ?? defaults.showContours
        contourSmoothingMeters = max(
            0,
            min(3, try container.decodeIfPresent(Double.self, forKey: .contourSmoothingMeters)
                ?? defaults.contourSmoothingMeters)
        )
        metric = try container.decodeIfPresent(HeatmapMetric.self, forKey: .metric) ?? defaults.metric
        colorScheme = try container.decodeIfPresent(HeatmapColorScheme.self, forKey: .colorScheme) ?? defaults.colorScheme
        fadeRadius = try container.decodeIfPresent(Double.self, forKey: .fadeRadius) ?? defaults.fadeRadius
        rssiRange = try container.decodeIfPresent(HeatmapValueRange.self, forKey: .rssiRange) ?? defaults.rssiRange
        snrRange = try container.decodeIfPresent(HeatmapValueRange.self, forKey: .snrRange) ?? defaults.snrRange
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requiredSSIDs, forKey: .requiredSSIDs)
        try container.encode(requiredBSSIDs, forKey: .requiredBSSIDs)
        try container.encode(trackedBands, forKey: .trackedBands)
        try container.encode(displayBand, forKey: .displayBand)
        try container.encode(displaySSID, forKey: .displaySSID)
        try container.encode(displayBSSIDs, forKey: .displayBSSIDs)
        try container.encode(showHeatmap, forKey: .showHeatmap)
        try container.encode(showContours, forKey: .showContours)
        try container.encode(contourSmoothingMeters, forKey: .contourSmoothingMeters)
        try container.encode(metric, forKey: .metric)
        try container.encode(colorScheme, forKey: .colorScheme)
        try container.encode(fadeRadius, forKey: .fadeRadius)
        try container.encode(rssiRange, forKey: .rssiRange)
        try container.encode(snrRange, forKey: .snrRange)
    }

    func valueRange(for metric: HeatmapMetric) -> HeatmapValueRange {
        switch metric {
        case .rssi: return rssiRange
        case .snr: return snrRange
        case .channel: return metric.defaultValueRange
        }
    }

    static let standard = SurveyViewSettings(
        requiredSSIDs: [],
        requiredBSSIDs: [],
        trackedBands: Set(WiFiBand.allCases),
        displayBand: .ghz5,
        displaySSID: nil,
        displayBSSIDs: [],
        showHeatmap: false,
        showContours: false,
        contourSmoothingMeters: 1.0,
        metric: .rssi,
        colorScheme: .classic,
        fadeRadius: IDWInterpolator.outerRadiusMeters,
        rssiRange: HeatmapMetric.rssi.defaultValueRange,
        snrRange: HeatmapMetric.snr.defaultValueRange
    )

}

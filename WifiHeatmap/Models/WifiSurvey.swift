import Foundation

struct WifiSurvey: Codable, Equatable {
    var name: String
    var floors: [Floor]
    var viewSettings: SurveyViewSettings

    init(name: String, floors: [Floor], viewSettings: SurveyViewSettings = .standard) {
        self.name = name
        self.floors = floors
        self.viewSettings = viewSettings
    }

    private enum CodingKeys: String, CodingKey {
        case name, floors, viewSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        floors = try container.decode([Floor].self, forKey: .floors)
        viewSettings = try container.decodeIfPresent(SurveyViewSettings.self, forKey: .viewSettings) ?? .standard
    }
}

struct SurveyViewSettings: Codable, Equatable {
    var selectedSSIDs: Set<String>
    var selectedBSSIDs: Set<String>
    var trackedBands: Set<WiFiBand>
    var activeBand: WiFiBand
    var showHeatmap: Bool
    var showContours: Bool
    var contourSmoothingMeters: Double
    var metric: HeatmapMetric
    var colorScheme: HeatmapColorScheme
    var fadeRadius: Double
    var rssiRange: HeatmapValueRange
    var snrRange: HeatmapValueRange

    init(
        selectedSSIDs: Set<String>,
        selectedBSSIDs: Set<String>,
        trackedBands: Set<WiFiBand>,
        activeBand: WiFiBand,
        showHeatmap: Bool,
        showContours: Bool = false,
        contourSmoothingMeters: Double = 1.0,
        metric: HeatmapMetric,
        colorScheme: HeatmapColorScheme,
        fadeRadius: Double,
        rssiRange: HeatmapValueRange = HeatmapMetric.rssi.defaultValueRange,
        snrRange: HeatmapValueRange = HeatmapMetric.snr.defaultValueRange
    ) {
        self.selectedSSIDs = selectedSSIDs
        self.selectedBSSIDs = selectedBSSIDs
        self.trackedBands = trackedBands.isEmpty ? Set(WiFiBand.allCases) : trackedBands
        self.activeBand = activeBand
        self.showHeatmap = showHeatmap
        self.showContours = showContours
        self.contourSmoothingMeters = max(0, min(3, contourSmoothingMeters))
        self.metric = metric
        self.colorScheme = colorScheme
        self.fadeRadius = fadeRadius
        self.rssiRange = rssiRange
        self.snrRange = snrRange
    }

    init(
        selectedSSID: String?,
        selectedBSSID: String?,
        activeBand: WiFiBand,
        showHeatmap: Bool,
        showContours: Bool = false,
        contourSmoothingMeters: Double = 1.0,
        metric: HeatmapMetric,
        colorScheme: HeatmapColorScheme,
        fadeRadius: Double,
        rssiRange: HeatmapValueRange = HeatmapMetric.rssi.defaultValueRange,
        snrRange: HeatmapValueRange = HeatmapMetric.snr.defaultValueRange
    ) {
        self.init(
            selectedSSIDs: selectedSSID.map { [$0] } ?? [],
            selectedBSSIDs: selectedBSSID.map { [$0] } ?? [],
            trackedBands: Set(WiFiBand.allCases),
            activeBand: activeBand,
            showHeatmap: showHeatmap,
            showContours: showContours,
            contourSmoothingMeters: contourSmoothingMeters,
            metric: metric,
            colorScheme: colorScheme,
            fadeRadius: fadeRadius,
            rssiRange: rssiRange,
            snrRange: snrRange
        )
    }

    private enum CodingKeys: String, CodingKey {
        case selectedSSIDs, selectedBSSIDs, trackedBands
        case selectedSSID, selectedBSSID
        case activeBand, showHeatmap, showContours, contourSmoothingMeters, metric
        case colorScheme, fadeRadius, rssiRange, snrRange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.standard
        selectedSSIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedSSIDs)
            ?? container.decodeIfPresent(String.self, forKey: .selectedSSID).map { [$0] }
            ?? []
        selectedBSSIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedBSSIDs)
            ?? container.decodeIfPresent(String.self, forKey: .selectedBSSID).map { [$0] }
            ?? []
        let decodedBands = try container.decodeIfPresent(Set<WiFiBand>.self, forKey: .trackedBands)
        if let decodedBands, !decodedBands.isEmpty {
            trackedBands = decodedBands
        } else {
            trackedBands = Set(WiFiBand.allCases)
        }
        activeBand = try container.decodeIfPresent(WiFiBand.self, forKey: .activeBand) ?? defaults.activeBand
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
        try container.encode(selectedSSIDs, forKey: .selectedSSIDs)
        try container.encode(selectedBSSIDs, forKey: .selectedBSSIDs)
        try container.encode(trackedBands, forKey: .trackedBands)
        try container.encode(activeBand, forKey: .activeBand)
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
        selectedSSIDs: [],
        selectedBSSIDs: [],
        trackedBands: Set(WiFiBand.allCases),
        activeBand: .ghz5,
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

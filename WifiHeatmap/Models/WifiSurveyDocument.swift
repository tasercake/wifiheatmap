import SwiftUI
import UniformTypeIdentifiers

// MARK: - UTType

extension UTType {
    static let wifiSurvey = UTType(exportedAs: "com.yourname.wifiheatmap")
}

// MARK: - Snapshot

struct DocumentSnapshot {
    var survey: WifiSurvey
    var imageCache: [String: Data]
}

// MARK: - Manifest (private helper)

private struct Manifest: Codable {
    var name: String
    var createdAt: Date
    var floorIDs: [UUID]
}

// MARK: - Document

final class WifiSurveyDocument: ReferenceFileDocument {
    typealias Snapshot = DocumentSnapshot

    static var readableContentTypes: [UTType] { [.wifiSurvey] }

    @Published var survey: WifiSurvey
    private(set) var imageCache: [String: Data] = [:]

    // MARK: Init — new empty document

    init() {
        survey = WifiSurvey(name: "New Survey", floors: [])
    }

    // MARK: Init — read from ReferenceFileDocument configuration

    required init(configuration: ReadConfiguration) throws {
        survey = WifiSurvey(name: "New Survey", floors: [])
        let (loadedSurvey, cache) = try WifiSurveyDocument.decode(fileWrapper: configuration.file)
        survey = loadedSurvey
        imageCache = cache
    }

    // MARK: Snapshot

    func snapshot(contentType: UTType) throws -> DocumentSnapshot {
        DocumentSnapshot(survey: survey, imageCache: imageCache)
    }

    // MARK: Write

    func fileWrapper(snapshot: DocumentSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        try WifiSurveyDocument.encode(snapshot: snapshot)
    }

    // MARK: Mutations

    func addFloor(name: String) {
        let id = UUID()
        survey.floors.append(Floor(
            id: id,
            name: name,
            floorPlanFilename: "\(id.uuidString).png",
            calibration: nil,
            samples: []
        ))
    }

    func importFloorPlan(url: URL, for floorID: UUID) throws {
        guard let idx = survey.floors.firstIndex(where: { $0.id == floorID }) else { return }
        let data = try Data(contentsOf: url)
        let key = "\(floorID.uuidString).png"
        survey.floors[idx].floorPlanFilename = key
        imageCache[key] = data
    }

    // MARK: - Core encode / decode (static, FileWrapper-based)
    //
    // These are internal so tests can call them directly without having to
    // construct FileDocumentReadConfiguration / FileDocumentWriteConfiguration,
    // whose public initialisers are not exposed on all SDK versions.

    static func encode(snapshot: DocumentSnapshot) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let manifest = Manifest(
            name: snapshot.survey.name,
            createdAt: Date(),
            floorIDs: snapshot.survey.floors.map(\.id)
        )
        let manifestWrapper = FileWrapper(
            regularFileWithContents: try encoder.encode(manifest)
        )
        manifestWrapper.preferredFilename = "manifest.json"

        var floorDict: [String: FileWrapper] = [:]
        for floor in snapshot.survey.floors {
            let jsonKey = "\(floor.id.uuidString).json"
            let pngKey  = "\(floor.id.uuidString).png"
            let jsonWrapper = FileWrapper(regularFileWithContents: try encoder.encode(floor))
            jsonWrapper.preferredFilename = jsonKey
            floorDict[jsonKey] = jsonWrapper
            if let imgData = snapshot.imageCache[pngKey] {
                let pngWrapper = FileWrapper(regularFileWithContents: imgData)
                pngWrapper.preferredFilename = pngKey
                floorDict[pngKey] = pngWrapper
            }
        }

        let floorsWrapper = FileWrapper(directoryWithFileWrappers: floorDict)
        floorsWrapper.preferredFilename = "floors"

        return FileWrapper(directoryWithFileWrappers: [
            "manifest.json": manifestWrapper,
            "floors": floorsWrapper
        ])
    }

    static func decode(fileWrapper: FileWrapper) throws -> (WifiSurvey, [String: Data]) {
        guard let wrappers = fileWrapper.fileWrappers else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let manifestData = wrappers["manifest.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manifest = try decoder.decode(Manifest.self, from: manifestData)

        let floorWrappers = wrappers["floors"]?.fileWrappers ?? [:]
        var floors: [Floor] = []
        var cache: [String: Data] = [:]

        for id in manifest.floorIDs {
            let jsonKey = "\(id.uuidString).json"
            let pngKey  = "\(id.uuidString).png"
            if let data = floorWrappers[jsonKey]?.regularFileContents {
                floors.append(try decoder.decode(Floor.self, from: data))
            }
            if let imgData = floorWrappers[pngKey]?.regularFileContents {
                cache[pngKey] = imgData
            }
        }

        return (WifiSurvey(name: manifest.name, floors: floors), cache)
    }
}

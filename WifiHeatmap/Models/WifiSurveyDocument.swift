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

private struct DecodedDocument {
    var survey: WifiSurvey
    var imageCache: [String: Data]
    var schemaVersion: Int
}

private struct PendingDocumentMigration {
    var decoded: DecodedDocument
}

enum DocumentMigrationError: LocalizedError {
    case backupRequired
    case missingSourceURL
    case backupIncomplete
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .backupRequired:
            return "This older survey must be backed up before it can be edited."
        case .missingSourceURL:
            return "The older survey's file location is unavailable, so a safety backup could not be created."
        case .backupIncomplete:
            return "The safety backup was incomplete. The original survey was not migrated."
        case .unsupportedSchema(let version):
            return "This survey uses unsupported schema version \(version)."
        }
    }
}

// MARK: - Manifest (private helper)

private struct Manifest: Codable {
    var schemaVersion: Int?
    var name: String
    var createdAt: Date
    var floorIDs: [UUID]
    var viewSettings: SurveyViewSettings?
}

// MARK: - Document

final class WifiSurveyDocument: ReferenceFileDocument {
    typealias Snapshot = DocumentSnapshot

    static var readableContentTypes: [UTType] { [.wifiSurvey] }
    static let currentSchemaVersion = 3

    @Published var survey: WifiSurvey
    @Published private(set) var requiresMigration = false
    @Published private(set) var migrationFailureMessage: String?
    @Published private(set) var migrationSuccessMessage: String?
    private(set) var imageCache: [String: Data] = [:]
    private var pendingMigration: PendingDocumentMigration?

    // MARK: Init — new empty document

    init() {
        survey = WifiSurvey(name: "New Survey", floors: [])
    }

    // MARK: Init — read from ReferenceFileDocument configuration

    required init(configuration: ReadConfiguration) throws {
        let decoded = try WifiSurveyDocument.decodeDocument(fileWrapper: configuration.file)
        if decoded.schemaVersion < Self.currentSchemaVersion {
            survey = WifiSurvey(name: "Preparing Migration", floors: [])
            pendingMigration = PendingDocumentMigration(decoded: decoded)
            requiresMigration = true
        } else {
            survey = decoded.survey
            imageCache = decoded.imageCache
        }
    }

    init(fileWrapper: FileWrapper) throws {
        let decoded = try WifiSurveyDocument.decodeDocument(fileWrapper: fileWrapper)
        if decoded.schemaVersion < Self.currentSchemaVersion {
            survey = WifiSurvey(name: "Preparing Migration", floors: [])
            pendingMigration = PendingDocumentMigration(decoded: decoded)
            requiresMigration = true
        } else {
            survey = decoded.survey
            imageCache = decoded.imageCache
        }
    }

    // MARK: Snapshot

    func snapshot(contentType: UTType) throws -> DocumentSnapshot {
        guard pendingMigration == nil else {
            throw DocumentMigrationError.backupRequired
        }
        return DocumentSnapshot(survey: survey, imageCache: imageCache)
    }

    @discardableResult
    func completePendingMigration(sourceURL: URL?, now: Date = Date()) throws -> URL? {
        try completePendingMigration(sourceURL: sourceURL, now: now) { source, destination in
            try Self.copyPackage(from: source, to: destination)
        }
    }

    @discardableResult
    func completePendingMigration(
        sourceURL: URL?,
        now: Date = Date(),
        backup: (URL, URL) throws -> Void
    ) throws -> URL? {
        guard let pendingMigration else { return nil }
        guard let sourceURL else {
            migrationFailureMessage = DocumentMigrationError.missingSourceURL.localizedDescription
            throw DocumentMigrationError.missingSourceURL
        }

        let backupURL = Self.backupURL(for: sourceURL, now: now)
        do {
            try backup(sourceURL, backupURL)
            guard Self.isCompletePackage(at: backupURL) else {
                throw DocumentMigrationError.backupIncomplete
            }
        } catch {
            migrationFailureMessage = "Could not back up and migrate this survey: \(error.localizedDescription)"
            throw error
        }

        survey = pendingMigration.decoded.survey
        imageCache = pendingMigration.decoded.imageCache
        self.pendingMigration = nil
        requiresMigration = false
        migrationFailureMessage = nil
        migrationSuccessMessage = "Survey updated to the new point format. Backup saved as \(backupURL.lastPathComponent)."
        return backupURL
    }

    func dismissMigrationSuccess() {
        migrationSuccessMessage = nil
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
            points: []
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
            schemaVersion: currentSchemaVersion,
            name: snapshot.survey.name,
            createdAt: Date(),
            floorIDs: snapshot.survey.floors.map(\.id),
            viewSettings: snapshot.survey.viewSettings
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
        let decoded = try decodeDocument(fileWrapper: fileWrapper)
        return (decoded.survey, decoded.imageCache)
    }

    private static func decodeDocument(fileWrapper: FileWrapper) throws -> DecodedDocument {
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

        let schemaVersion = try detectedSchemaVersion(
            manifestVersion: manifest.schemaVersion,
            floorIDs: manifest.floorIDs,
            floorWrappers: floorWrappers
        )
        guard schemaVersion <= currentSchemaVersion else {
            throw DocumentMigrationError.unsupportedSchema(schemaVersion)
        }

        return DecodedDocument(
            survey: WifiSurvey(
                name: manifest.name,
                floors: floors,
                viewSettings: manifest.viewSettings ?? .standard
            ),
            imageCache: cache,
            schemaVersion: schemaVersion
        )
    }

    private static func detectedSchemaVersion(
        manifestVersion: Int?,
        floorIDs: [UUID],
        floorWrappers: [String: FileWrapper]
    ) throws -> Int {
        if let manifestVersion { return manifestVersion }
        for id in floorIDs {
            let key = "\(id.uuidString).json"
            guard let data = floorWrappers[key]?.regularFileContents,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if json["points"] != nil { return 3 }
            if json["captures"] != nil { return 2 }
            if json["samples"] != nil { return 1 }
        }
        return 1
    }

    private static func backupURL(for sourceURL: URL, now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let stem = "\(base).pre-v3-backup-\(formatter.string(from: now))"
        let directory = sourceURL.deletingLastPathComponent()
        var suffix = 1
        while true {
            let numberedStem = suffix == 1 ? stem : "\(stem)-\(suffix)"
            let filename = numberedStem + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func copyPackage(from sourceURL: URL, to destinationURL: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try FileManager.default.copyItem(at: coordinatedURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    private static func isCompletePackage(at url: URL) -> Bool {
        let manager = FileManager.default
        return manager.fileExists(atPath: url.path)
            && manager.fileExists(atPath: url.appendingPathComponent("manifest.json").path)
            && manager.fileExists(atPath: url.appendingPathComponent("floors").path)
    }
}

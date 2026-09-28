import Foundation

struct DisplayRecallCommandStatus: Codable, Equatable {
    enum State: String, Codable {
        case pending
        case completed
        case failed
    }

    var requestID: String
    var command: DisplayRecallCommandRequest.Action
    var state: State
    var message: String
    var updatedAt: Date
    var permissionGranted: Bool
    var hasExternalDisplay: Bool
    var savedWindowCount: Int?
    var savedAt: Date?
    var externalDisplayName: String?
    var matchedWindowCount: Int?
    var restoredWindowCount: Int?
    var failedWindowCount: Int?
}

final class CommandStatusStore {
    private let fileManager: FileManager
    let fileURL: URL

    init(
        fileManager: FileManager = .default,
        directoryURL: URL
    ) {
        self.fileManager = fileManager
        fileURL = directoryURL.appendingPathComponent("command-status-v1.json")
    }

    func save(_ status: DisplayRecallCommandStatus) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(status).write(to: fileURL, options: .atomic)
    }

    func load() throws -> DisplayRecallCommandStatus? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            DisplayRecallCommandStatus.self,
            from: Data(contentsOf: fileURL)
        )
    }
}

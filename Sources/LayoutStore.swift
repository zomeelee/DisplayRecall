import Foundation

final class LayoutStore {
    private let fileManager: FileManager
    let directoryURL: URL
    let fileURL: URL
    private let backupURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = applicationSupport.appendingPathComponent("com.zomeelee.DisplayRecall", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("layout-v1.json")
        backupURL = directoryURL.appendingPathComponent("layout-v1.backup.json")
    }

    func load() throws -> LayoutSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LayoutSnapshot.self, from: data)
    }

    func save(_ snapshot: LayoutSnapshot) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: fileURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func summary() -> SnapshotSummary? {
        guard let snapshot = try? load() else {
            return nil
        }
        return SnapshotSummary(
            savedAt: snapshot.savedAt,
            windowCount: snapshot.windows.count,
            externalDisplayName: snapshot.displays.first(where: { $0.slot.role == .external })?.name
        )
    }
}

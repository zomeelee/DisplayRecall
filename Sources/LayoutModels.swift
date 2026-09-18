import Foundation

struct RectRecord: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct NormalizedFrame: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum DisplayRole: String, Codable, Sendable {
    case builtIn
    case external
}

struct DisplaySlot: Codable, Equatable, Hashable, Sendable {
    var role: DisplayRole
    var index: Int
    var exactUUID: String?
}

struct SavedDisplay: Codable, Equatable, Sendable {
    var slot: DisplaySlot
    var name: String
    var visibleFrame: RectRecord
    var rotation: Double
}

struct WindowMatchKey: Codable, Equatable, Sendable {
    var bundleIdentifier: String
    var identifier: String?
    var titleHash: String?
    var documentHash: String?
    var role: String
    var subrole: String?
    var ordinal: Int
}

struct SavedWindow: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var appName: String
    var matchKey: WindowMatchKey
    var displaySlot: DisplaySlot
    var normalizedFrame: NormalizedFrame
    var sourceFrame: RectRecord
}

struct LayoutSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var savedAt: Date
    var topologySignature: String
    var displays: [SavedDisplay]
    var windows: [SavedWindow]

    static let currentSchemaVersion = 1
}

struct SnapshotSummary: Equatable, Sendable {
    var savedAt: Date
    var windowCount: Int
    var externalDisplayName: String?
}

import Foundation

struct DisplayRecallCommandRequest: Equatable {
    enum Action: String, Codable {
        case save
        case restore
        case status
    }

    let action: Action
    let requestID: String

    init?(url: URL) {
        guard url.scheme?.lowercased() == "displayrecall" else {
            return nil
        }

        let rawAction = (url.host?.isEmpty == false ? url.host : nil) ??
            url.pathComponents.first(where: { $0 != "/" })
        guard let rawAction,
              let action = Action(rawValue: rawAction.lowercased()) else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let suppliedRequestID = components?.queryItems?
            .first(where: { $0.name == "request" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.action = action
        requestID = suppliedRequestID?.isEmpty == false
            ? suppliedRequestID!
            : UUID().uuidString.lowercased()
    }
}

import Foundation
import SuperFlowCore

/// `superflow://` URLs (behaviour.md §1.3): `open`, `open/<page>`, `start-hands-free`, `stop-hands-free`.
enum AppRoute: Equatable {
    case open(HubPage)
    case startHandsFree
    case stopHandsFree

    static let scheme = "superflow"

    init?(url: URL) {
        guard url.scheme == AppRoute.scheme, let host = url.host else { return nil }
        let path = url.path.split(separator: "/").map(String.init)
        switch (host, path.first) {
        case ("open", nil): self = .open(.home)
        case ("open", let page?): guard let page = HubPage(rawValue: page) else { return nil }; self = .open(page)
        case ("start-hands-free", nil): self = .startHandsFree
        case ("stop-hands-free", nil): self = .stopHandsFree
        default: return nil
        }
    }
}

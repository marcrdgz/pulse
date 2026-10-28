import Foundation

/// Like Arc's profiles: spaces in different profiles keep their own cookies, site data and
/// favorites, so the same site can be signed into with different accounts side by side.
struct Profile: Identifiable, Equatable {
    /// The profile every space starts in. It uses WebKit's default data store, so the cookies and
    /// site data from before profiles existed stay in it.
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let `default` = Profile(id: defaultID, name: "Default")

    let id: UUID
    var name: String

    var isDefault: Bool { id == Self.defaultID }
}

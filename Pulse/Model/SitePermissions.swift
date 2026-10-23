import Foundation
import WebKit

/// A device a site asks to use; stored per kind so camera and microphone can differ.
enum PermissionKind: String, CaseIterable {
    case camera
    case microphone

    static func kinds(for type: WKMediaCaptureType) -> [PermissionKind] {
        switch type {
        case .camera: [.camera]
        case .microphone: [.microphone]
        case .cameraAndMicrophone: [.camera, .microphone]
        @unknown default: [.camera, .microphone]
        }
    }
}

/// The choices of Chrome's permission prompt.
enum PermissionChoice {
    case allowAlways
    case allowOnce
    case neverAllow
}

/// A site waiting for the user to answer the permission prompt.
struct PermissionRequest: Identifiable {
    let id = UUID()
    let tabID: Tab.ID
    /// e.g. `meet.google.com`; decisions are remembered per origin.
    let origin: String
    let kinds: [PermissionKind]
    let respond: (WKPermissionDecision) -> Void
}

/// Remembers "Allow on every visit" and "Never allow" per site and device.
struct SitePermissionStore {
    let defaults: UserDefaults
    private let key = "sitePermissions"

    /// `nil` when the user hasn't decided for every requested kind, or the decisions disagree.
    func decision(for origin: String, kinds: [PermissionKind]) -> Bool? {
        let saved = (defaults.dictionary(forKey: key)?[origin] as? [String: Bool]) ?? [:]
        let decisions = Set(kinds.map { saved[$0.rawValue] })
        guard decisions.count == 1, let decision = decisions.first else { return nil }
        return decision
    }

    /// Every site with a remembered decision, for the site settings list.
    func allDecisions() -> [(origin: String, decisions: [PermissionKind: Bool])] {
        let all = defaults.dictionary(forKey: key) ?? [:]
        return all.keys.sorted().compactMap { origin in
            guard let site = all[origin] as? [String: Bool] else { return nil }
            let decisions = Dictionary(uniqueKeysWithValues: site.compactMap { key, value in
                PermissionKind(rawValue: key).map { ($0, value) }
            })
            return decisions.isEmpty ? nil : (origin, decisions)
        }
    }

    /// `nil` forgets the decision, so the site asks again.
    func setDecision(_ isAllowed: Bool?, for origin: String, kind: PermissionKind) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        var site = (all[origin] as? [String: Bool]) ?? [:]
        site[kind.rawValue] = isAllowed
        all[origin] = site.isEmpty ? nil : site
        defaults.set(all, forKey: key)
    }

    func save(_ isAllowed: Bool, for origin: String, kinds: [PermissionKind]) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        var site = (all[origin] as? [String: Bool]) ?? [:]
        for kind in kinds { site[kind.rawValue] = isAllowed }
        all[origin] = site
        defaults.set(all, forKey: key)
    }
}

extension URL {
    /// The site a page's permissions are remembered under, named like `WKSecurityOrigin.displayName`.
    var permissionOrigin: String? {
        guard let host = host(), !host.isEmpty else { return nil }
        guard let port, !(scheme == "https" && port == 443), !(scheme == "http" && port == 80) else { return host }
        return "\(host):\(port)"
    }
}

extension WKSecurityOrigin {
    /// Host plus a non-default port, the way Chrome names a site in its prompts.
    var displayName: String {
        let isDefaultPort = port == 0 || (`protocol` == "https" && port == 443) || (`protocol` == "http" && port == 80)
        return isDefaultPort ? host : "\(host):\(port)"
    }
}

import Foundation

/// A WebKit content blocker rule, as `WKContentRuleListStore` compiles it.
nonisolated struct ContentRule: Encodable, Equatable, Sendable {
    struct Trigger: Encodable, Equatable, Sendable {
        var urlFilter: String
        var isCaseSensitive: Bool?
        var resourceTypes: [String]?
        var loadTypes: [String]?
        var ifDomains: [String]?
        var unlessDomains: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case isCaseSensitive = "url-filter-is-case-sensitive"
            case resourceTypes = "resource-type"
            case loadTypes = "load-type"
            case ifDomains = "if-domain"
            case unlessDomains = "unless-domain"
        }
    }

    struct Action: Encodable, Equatable, Sendable {
        enum Kind: String, Encodable, Sendable {
            case block
            case cssDisplayNone = "css-display-none"
            case ignorePreviousRules = "ignore-previous-rules"
        }

        var type: Kind
        var selector: String?
    }

    var trigger: Trigger
    var action: Action
}

/// Converts Adblock Plus filter lists (EasyList, EasyPrivacy) into WebKit content rules.
///
/// WebKit's rules are a strict subset of what filter lists express (no regex alternation, no
/// scriptlets, no procedural selectors), so anything that can't be translated faithfully is
/// dropped: missing a few ads is harmless, while an over-broad rule breaks sites.
nonisolated enum FilterList {
    /// WebKit rejects lists above its rule limit, so big lists are split across several.
    static let maxRulesPerList = 50_000

    struct Rules: Equatable {
        /// Network blocks and element hiding, applied first.
        var blocking: [ContentRule] = []
        /// `@@` exceptions; WebKit only honors them after the rules they override.
        var exceptions: [ContentRule] = []
    }

    /// The encoded rule lists to compile, each holding every exception so they apply to all.
    static func encodedRuleLists(from lists: [String], maxRules: Int = maxRulesPerList) throws -> [String] {
        let rules = lists.map(rules(from:)).reduce(into: Rules()) {
            $0.blocking += $1.blocking
            $0.exceptions += $1.exceptions
        }
        let chunkSize = max(maxRules - rules.exceptions.count, 1)
        let encoder = JSONEncoder()
        return try stride(from: 0, to: rules.blocking.count, by: chunkSize).map { start in
            let chunk = rules.blocking[start..<min(start + chunkSize, rules.blocking.count)] + rules.exceptions
            return String(decoding: try encoder.encode(Array(chunk)), as: UTF8.self)
        }
    }

    static func rules(from list: String) -> Rules {
        var rules = Rules()
        var hidingRules: [(rule: ContentRule, selector: String)] = []
        /// `example.com#@#.ad`: selectors the list stops hiding on some sites, or everywhere.
        var hidingExceptions: [String: Set<String>] = [:]
        var unhiddenSelectors: Set<String> = []

        for line in list.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("[") else { continue }

            // The cheap check first: a regex search on every line triples conversion time.
            if line.contains("#"), let marker = line.range(of: #"#@?[?$%]?#"#, options: .regularExpression) {
                let domains = String(line[..<marker.lowerBound])
                let selector = String(line[marker.upperBound...])
                switch line[marker] {
                case "##":
                    if let rule = hidingRule(domains: domains, selector: selector) {
                        hidingRules.append((rule, selector))
                    }
                case "#@#":
                    // Exceptions limited to some sites only matter for rules that hide everywhere.
                    guard let scope = DomainScope(domains, separator: ","), scope.excluded.isEmpty else { continue }
                    if scope.included.isEmpty {
                        unhiddenSelectors.insert(selector)
                    } else {
                        hidingExceptions[selector, default: []].formUnion(scope.included)
                    }
                default:
                    continue // Procedural and scriptlet filters (#?#, #$#, #%#) have no WebKit equivalent.
                }
                continue
            }

            if line.hasPrefix("@@") {
                if let rule = networkRule(String(line.dropFirst(2)), isException: true) {
                    rules.exceptions.append(rule)
                }
            } else if let rule = networkRule(line, isException: false) {
                rules.blocking.append(rule)
            }
        }

        for (rule, selector) in hidingRules where !unhiddenSelectors.contains(selector) {
            var rule = rule
            if let sites = hidingExceptions[selector], rule.trigger.ifDomains == nil {
                rule.trigger.unlessDomains = (rule.trigger.unlessDomains ?? []) + sites.sorted().map { "*" + $0 }
            }
            rules.blocking.append(rule)
        }
        return rules
    }

    // MARK: Element hiding

    /// Extended selectors from Adblock Plus, AdGuard and uBlock Origin that aren't CSS.
    private static let proceduralPseudoClasses = [
        ":-abp-", ":has-text(", ":contains(", ":xpath(", ":upward(", ":remove(", ":style(",
        ":matches-css", ":matches-attr(", ":matches-path(", ":min-text-length(", ":watch-attr(", ":others(",
    ]

    private static func hidingRule(domains: String, selector: String) -> ContentRule? {
        guard !selector.isEmpty, selector.allSatisfy(\.isASCII),
              !selector.hasPrefix("+js"), !selector.hasPrefix("^"),
              !proceduralPseudoClasses.contains(where: selector.contains),
              let scope = DomainScope(domains, separator: ",")
        else { return nil }
        return ContentRule(
            trigger: scope.trigger(urlFilter: ".*"),
            action: ContentRule.Action(type: .cssDisplayNone, selector: selector)
        )
    }

    // MARK: Network rules

    /// Types a filter without type options applies to: Adblock Plus never blocks pages by default.
    private static let defaultResourceTypes = ["image", "style-sheet", "script", "font", "raw", "svg-document", "media"]

    private static let resourceTypes = [
        "script": "script",
        "image": "image",
        "stylesheet": "style-sheet",
        "font": "font",
        "media": "media",
        "xmlhttprequest": "raw",
        "websocket": "raw",
        "ping": "raw",
        "other": "raw",
        "subdocument": "document",
        "document": "document",
        "popup": "popup",
    ]

    /// Types WebKit can't tell apart; filters limited to them can't be applied.
    private static let unsupportedResourceTypes: Set<String> = ["object", "object-subrequest", "font-face"]

    private static func networkRule(_ filter: String, isException: Bool) -> ContentRule? {
        var pattern = filter
        var options: [Substring] = []
        if let dollar = filter.lastIndex(of: "$") {
            pattern = String(filter[..<dollar])
            options = filter[filter.index(after: dollar)...].split(separator: ",")
        }

        var trigger = ContentRule.Trigger(urlFilter: "")
        var included: [String] = []
        var excluded: [String] = []
        var includesUnsupportedType = false
        var isDocumentException = false

        for option in options {
            let isNegated = option.hasPrefix("~")
            let name = String(isNegated ? option.dropFirst() : option)
            switch name {
            case "third-party", "3p":
                trigger.loadTypes = [isNegated ? "first-party" : "third-party"]
            case "first-party", "1p":
                trigger.loadTypes = [isNegated ? "third-party" : "first-party"]
            case "match-case":
                trigger.isCaseSensitive = true
            case "important":
                continue // Exceptions can't be outranked in WebKit, so it's a plain block.
            case "document" where isException && !isNegated:
                isDocumentException = true
            case _ where name.hasPrefix("domain="):
                guard let scope = DomainScope(String(name.dropFirst("domain=".count)), separator: "|"),
                      !scope.included.isEmpty || !scope.excluded.isEmpty
                else { return nil }
                let scoped = scope.trigger(urlFilter: "")
                trigger.ifDomains = scoped.ifDomains
                trigger.unlessDomains = scoped.unlessDomains
            case _ where resourceTypes[name] != nil:
                if isNegated { excluded.append(resourceTypes[name]!) } else { included.append(resourceTypes[name]!) }
            case _ where unsupportedResourceTypes.contains(name):
                includesUnsupportedType = includesUnsupportedType || !isNegated
            default:
                // Redirects, CSP, header and parameter rewrites, `generichide`…: not expressible.
                return nil
            }
        }

        if isDocumentException {
            // Allowlists a whole site: only the `||example.com^$document` form maps to `if-domain`.
            guard options.count == 1, let domain = anchoredDomain(pattern) else { return nil }
            trigger.urlFilter = ".*"
            trigger.ifDomains = ["*" + domain]
        } else {
            guard let urlFilter = urlFilter(for: pattern) ?? (trigger.ifDomains != nil ? ".*" : nil) else { return nil }
            trigger.urlFilter = urlFilter
            if !included.isEmpty {
                trigger.resourceTypes = Array(Set(included)).sorted()
            } else if includesUnsupportedType {
                return nil
            } else if !excluded.isEmpty {
                trigger.resourceTypes = defaultResourceTypes.filter { !excluded.contains($0) }
            } else if !isException, anchoredDomain(pattern) == nil {
                // Domain filters block everything from the domain; path filters stay off pages.
                trigger.resourceTypes = defaultResourceTypes
            }
        }

        return ContentRule(
            trigger: trigger,
            action: ContentRule.Action(type: isException ? .ignorePreviousRules : .block)
        )
    }

    /// `example.com` for `||example.com^`, the filter that matches a domain and its subdomains.
    private static func anchoredDomain(_ pattern: String) -> String? {
        guard pattern.hasPrefix("||") else { return nil }
        var domain = pattern.dropFirst(2)
        if domain.hasSuffix("^") { domain = domain.dropLast() }
        return DomainScope.isPlainDomain(domain) ? domain.lowercased() : nil
    }

    /// Characters Adblock Plus treats as part of an address; `^` matches anything else.
    private static let separator = "[^a-zA-Z0-9_.%-]"

    /// Translates the pattern to WebKit's regex subset; `nil` for patterns that would match every
    /// address or that WebKit can't express (regex filters, alternation, non-ASCII).
    static func urlFilter(for pattern: String) -> String? {
        guard pattern.allSatisfy(\.isASCII), !(pattern.count > 1 && pattern.hasPrefix("/") && pattern.hasSuffix("/"))
        else { return nil }
        var body = Substring(pattern)
        var prefix = ""
        if body.hasPrefix("||") {
            prefix = "^[^:]+://+([^/]*\\.)?"
            body = body.dropFirst(2)
        } else if body.hasPrefix("|") {
            prefix = "^"
            body = body.dropFirst()
        }
        var suffix = ""
        if body.hasSuffix("|") {
            suffix = "$"
            body = body.dropLast()
        }
        // Wildcards at an unanchored edge add nothing but matching cost.
        if prefix.isEmpty { body = body.drop { $0 == "*" } }
        if suffix.isEmpty { while body.hasSuffix("*") { body = body.dropLast() } }
        guard !body.isEmpty, !body.contains("|") else { return nil }

        var regex = prefix
        for character in body {
            switch character {
            case "*": regex += ".*"
            case "^": regex += separator
            case ".", "+", "?", "(", ")", "[", "]", "{", "}", "\\", "$": regex += "\\" + String(character)
            default: regex.append(character)
            }
        }
        return regex + suffix
    }
}

/// The sites a filter applies to, e.g. `example.com,~shop.example.com`.
private nonisolated struct DomainScope {
    var included: [String] = []
    var excluded: [String] = []

    /// `nil` when a domain can't be expressed in WebKit (wildcard TLDs, regexes, non-ASCII), so
    /// the filter is skipped rather than applied too widely.
    init?(_ list: String, separator: Character) {
        for entry in list.split(separator: separator) {
            let isExcluded = entry.hasPrefix("~")
            let domain = isExcluded ? entry.dropFirst() : entry
            guard Self.isPlainDomain(domain) else { return nil }
            if isExcluded { excluded.append(domain.lowercased()) } else { included.append(domain.lowercased()) }
        }
        // WebKit can't combine `if-domain` and `unless-domain`.
        guard included.isEmpty || excluded.isEmpty else { return nil }
    }

    static func isPlainDomain(_ domain: Substring) -> Bool {
        !domain.isEmpty && domain.contains(".")
            && domain.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    /// `*` makes WebKit match subdomains too, like Adblock Plus does.
    func trigger(urlFilter: String) -> ContentRule.Trigger {
        ContentRule.Trigger(
            urlFilter: urlFilter,
            ifDomains: included.isEmpty ? nil : included.map { "*" + $0 },
            unlessDomains: excluded.isEmpty ? nil : excluded.map { "*" + $0 }
        )
    }
}

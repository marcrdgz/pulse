import Foundation
import Testing
import WebKit
@testable import Pulse

struct FilterListTests {
    private func convert(_ filter: String) -> ContentRule? {
        let rules = FilterList.rules(from: filter)
        return (rules.blocking + rules.exceptions).first
    }

    @Test func domainFiltersBlockEverythingFromTheDomainAndItsSubdomains() throws {
        let rule = try #require(convert("||ads.example.com^"))
        #expect(rule.action.type == .block)
        #expect(rule.trigger.urlFilter == #"^[^:]+://+([^/]*\.)?ads\.example\.com[^a-zA-Z0-9_.%-]"#)
        #expect(rule.trigger.resourceTypes == nil)
    }

    @Test func pathFiltersNeverBlockPages() throws {
        let rule = try #require(convert("/banner/*/ad.js"))
        #expect(rule.trigger.urlFilter == #"/banner/.*/ad\.js"#)
        #expect(rule.trigger.resourceTypes?.contains("document") == false)
    }

    @Test func translatesOptions() throws {
        let rule = try #require(convert("||tracker.net^$script,image,third-party,domain=news.com|blog.org"))
        #expect(rule.trigger.resourceTypes == ["image", "script"])
        #expect(rule.trigger.loadTypes == ["third-party"])
        #expect(rule.trigger.ifDomains == ["*news.com", "*blog.org"])

        let negated = try #require(convert("/ads/banner$~script,domain=~shop.com"))
        #expect(negated.trigger.resourceTypes?.contains("script") == false)
        #expect(negated.trigger.unlessDomains == ["*shop.com"])
    }

    @Test func exceptionsComeAfterBlocksAndCanAllowlistASite() throws {
        let rules = FilterList.rules(from: """
        @@||cdn.example.com/ads.js
        ||example.com/ads.js
        @@||trusted.org^$document
        """)
        #expect(rules.blocking.map(\.action.type) == [.block])
        #expect(rules.exceptions.map(\.action.type) == [.ignorePreviousRules, .ignorePreviousRules])
        #expect(rules.exceptions[1].trigger.ifDomains == ["*trusted.org"])
        #expect(rules.exceptions[1].trigger.urlFilter == ".*")
    }

    @Test func elementHidingHonorsItsExceptions() {
        let rules = FilterList.rules(from: """
        ##.ad-banner
        news.com##.sponsored
        example.com,shop.com#@#.ad-banner
        ##.promo
        #@#.promo
        """)
        #expect(rules.blocking.count == 2)
        #expect(rules.blocking[0].action.selector == ".ad-banner")
        #expect(rules.blocking[0].trigger.unlessDomains == ["*example.com", "*shop.com"])
        #expect(rules.blocking[1].trigger.ifDomains == ["*news.com"])
    }

    @Test func dropsWhatWebKitCantExpress() {
        let unsupported = """
        ! Comment
        [Adblock Plus 2.0]
        /^https?:\\/\\/ads\\./
        ||example.com^$redirect=noop.js
        ||example.com^$csp=script-src 'none'
        ||example.com^$object
        @@||example.com^$generichide
        example.com#?#div:-abp-has(.ad)
        example.com##+js(set-constant, ads, false)
        example.*##.ad
        example.com,~shop.example.com##.ad
        *$image
        ||ex|ample.com
        ||ejemplo.es/anuncio-ñ
        """
        #expect(FilterList.rules(from: unsupported) == FilterList.Rules())
    }

    @Test func splitsLargeListsKeepingEveryException() throws {
        let filters = (0..<5).map { "||ads\($0).com^" } + ["@@||ads0.com/ok"]
        let lists = try FilterList.encodedRuleLists(from: [filters.joined(separator: "\n")], maxRules: 3)
        #expect(lists.count == 3)
        #expect(lists.allSatisfy { $0.contains("ignore-previous-rules") })
    }

    /// WebKit rejects a whole list for one rule it can't parse, so the output must compile.
    @Test func compiledRulesHideElementsInAPage() async throws {
        let list = """
        ||ads.example.com^$third-party
        /banner/*/ad.js|
        ||tracker.net^$script,domain=news.com|blog.org
        @@||trusted.org^$document
        ##.ad-banner
        """
        let encoded = try #require(try FilterList.encodedRuleLists(from: [list]).first)
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try #require(WKContentRuleListStore(url: directory))
        let ruleList = try #require(try await store.compileContentRuleList(forIdentifier: "test", encodedContentRuleList: encoded))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(ruleList)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString("<div class='ad-banner'>Ad</div>", baseURL: URL(string: "https://example.com"))
        var display: String?
        for _ in 0..<100 where display != "none" {
            try await Task.sleep(for: .milliseconds(50))
            display = try? await webView.evaluateJavaScript(
                "getComputedStyle(document.querySelector('.ad-banner')).display"
            ) as? String
        }
        #expect(display == "none")
    }
}

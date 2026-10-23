import AppKit
import WebKit

/// Makes the Chrome Web Store's own "Add to Chrome" button install into Pulse, like Orion does:
/// the store only enables it in Chrome, so its page sees Chrome's user agent and the private
/// `chrome.webstorePrivate` / `chrome.management` APIs it installs through, answered by Pulse.
/// The labels then say Pulse. Google can change any of this; the command bar action still works.
enum ChromeWebStorePage {
    static let host = "chromewebstore.google.com"
    private static let messageName = "pulseWebStore"

    static func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            // The store's own scripts must see the APIs.
            in: .page
        ))
        controller.addScriptMessageHandler(Router.shared, contentWorld: .page, name: messageName)
    }

    /// What the store page asks Pulse, decoded from `[method, argument]`.
    enum Request {
        case installed
        case status(id: String)
        case install(id: String)
        case uninstall(id: String)

        init?(_ body: Any) {
            guard let message = body as? [Any], let method = message.first as? String, message.count == 2 else { return nil }
            if method == "installed" {
                self = .installed
                return
            }
            let argument = message[1]
            // `beginInstallWithManifest3` passes Chrome's install details; the rest pass the ID.
            let id = (argument as? [String: Any])?["id"] as? String ?? argument as? String
            guard let id, ChromeWebStore.isExtensionID(id) else { return nil }
            switch method {
            case "status": self = .status(id: id)
            case "install": self = .install(id: id)
            case "uninstall": self = .uninstall(id: id)
            default: return nil
            }
        }
    }

    /// Answers with the values Chrome's API would return.
    static func respond(to request: Request, with extensions: WebExtensions) async -> Any {
        switch request {
        case .installed:
            return extensions.contexts.map(\.uniqueIdentifier).filter(ChromeWebStore.isExtensionID)
        case .status(let id):
            return extensions.context(identifiedBy: id) == nil ? "installable" : "enabled"
        case .install(let id):
            // `""` is `webstorePrivate.Result`'s success.
            return await extensions.install(.chromeWebStore(id: id)) ? "" : "user_cancelled"
        case .uninstall(let id):
            guard let context = extensions.context(identifiedBy: id), await extensions.confirmRemoval(context) else {
                return "cancelled"
            }
            await extensions.uninstall(context)
            return "removed"
        }
    }

    private final class Router: NSObject, WKScriptMessageHandlerWithReply {
        static let shared = Router()

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) async -> (Any?, String?) {
            // Only the store itself may install, never a page that copies the script's message.
            let origin = message.frameInfo.securityOrigin
            guard message.frameInfo.isMainFrame, origin.protocol == "https", origin.host == ChromeWebStorePage.host,
                  let request = Request(message.body),
                  let tab = (message.webView?.navigationDelegate as? WebViewCoordinator)?.tab,
                  let extensions = tab.browser?.extensions
            else { return (nil, "Not available") }
            return (await ChromeWebStorePage.respond(to: request, with: extensions), nil)
        }
    }

    /// Kept below 142.0.7430: from there the store stops checking the user agent and trusts a
    /// server-side flag instead, which leaves the button disabled outside real Chrome.
    private static let chromeVersion = "140.0.0.0"
    private static let chromeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromeVersion) Safari/537.36"

    /// The store also decides from the request's user agent, before any script runs.
    static func userAgent(forPageAt url: URL) -> String? {
        url.host() == host ? chromeUserAgent : nil
    }

    private static let script = """
    (() => {
        if (location.host !== '\(host)') return;
        const ask = (method, argument) => window.webkit.messageHandlers.\(messageName).postMessage([method, argument]);
        const chromeVersion = '\(chromeVersion)';
        const major = chromeVersion.split('.')[0];

        // The store checks for Chrome before enabling its button.
        const userAgent = '\(chromeUserAgent)';
        const brands = [{ brand: 'Google Chrome', version: major }, { brand: 'Chromium', version: major }, { brand: 'Not=A?Brand', version: '24' }];
        const userAgentData = {
            brands, mobile: false, platform: 'macOS',
            getHighEntropyValues: async () => ({
                brands, mobile: false, platform: 'macOS', platformVersion: '15.0.0', architecture: 'arm',
                fullVersionList: brands.map(({ brand }) => ({ brand, version: chromeVersion })), uaFullVersion: chromeVersion,
            }),
            toJSON() { return { brands, mobile: false, platform: 'macOS' }; },
        };
        for (const [name, value] of [['userAgent', userAgent], ['appVersion', userAgent.replace(/^Mozilla\\//, '')], ['vendor', 'Google Inc.'], ['userAgentData', userAgentData]]) {
            Object.defineProperty(Navigator.prototype, name, { get: () => value, configurable: true });
        }

        // Chrome's extension APIs take a callback or return a promise; these do both.
        const method = (implementation) => (...args) => {
            const callback = typeof args[args.length - 1] === 'function' ? args.pop() : null;
            const result = Promise.resolve().then(() => implementation(...args));
            if (callback) result.then(callback, () => callback());
            return result;
        };
        const constant = (value) => method(() => value);
        const enumeration = (values) => Object.fromEntries(values.map((value) => [value.toUpperCase() || 'EMPTY_STRING', value]));
        const event = () => {
            const listeners = new Set();
            return {
                addListener: (listener) => listeners.add(listener),
                removeListener: (listener) => listeners.delete(listener),
                hasListener: (listener) => listeners.has(listener),
                // After the store's own callbacks, as Chrome fires it once the install finishes.
                dispatch: (value) => setTimeout(() => listeners.forEach((listener) => listener(value))),
            };
        };
        // The store refreshes its button when these fire.
        const onInstalled = event();
        const onUninstalled = event();

        const webstorePrivate = {
            Result: enumeration(['', 'success', 'user_cancelled', 'install_error', 'already_installed', 'invalid_id']),
            ExtensionInstallStatus: enumeration(['installable', 'enabled', 'disabled']),
            beginInstallWithManifest3: method(async (details) => {
                const result = await ask('install', details);
                if (result === '') onInstalled.dispatch({ id: details.id, enabled: true, type: 'extension' });
                return result;
            }),
            completeInstall: constant(undefined),
            getExtensionStatus: method((id) => ask('status', id)),
            // Must read "Chrome/a.b.c.d": the store parses it to check the extension's minimum version.
            getFullChromeVersion: constant({ version_number: `Chrome/${chromeVersion}` }),
            getBrowserLogin: constant({ login: '' }),
            getStoreLogin: constant(''),
            getWebGLStatus: constant('webgl_allowed'),
            getIsLauncherEnabled: constant(false),
            isInIncognitoMode: constant(false),
            isPendingCustodianApproval: constant(false),
            getReferrerChain: constant(''),
            getMV2DeprecationStatus: constant('inactive'),
            shouldShowEnterprisePromotionBanner: constant('PROMOTION_TYPE_UNSPECIFIED'),
        };
        const management = {
            get: method(async (id) => (await ask('status', id)) === 'enabled' ? { id, enabled: true, type: 'extension' } : undefined),
            // How the store tells "Add" from "Remove" (it gives up after 800 ms).
            getAll: method(async () => (await ask('installed', null)).map((id) => ({ id, enabled: true, type: 'extension' }))),
            uninstall: method(async (id) => {
                if ((await ask('uninstall', id)) === 'removed') onUninstalled.dispatch(id);
            }),
            setEnabled: constant(undefined),
            onInstalled, onUninstalled, onEnabled: event(), onDisabled: event(),
        };
        // Anything else the store may call answers like a no-op instead of throwing.
        const lenient = (api) => new Proxy(api, { get: (target, name) => name in target ? target[name] : constant(undefined) });
        window.chrome = Object.assign(window.chrome || {}, {
            webstorePrivate: lenient(webstorePrivate),
            management: lenient(management),
            runtime: window.chrome?.runtime || { lastError: undefined },
        });

        // "Add to Chrome", "Añadir a Chrome", "Remove from Chrome"…: the page is localized, so only
        // a trailing "Chrome" on a button is swapped, leaving the store's other Chrome products alone.
        const relabel = (root) => {
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                if (/Chrome\\s*$/.test(node.nodeValue) && node.parentElement?.closest('button')) {
                    node.nodeValue = node.nodeValue.replace(/Chrome(\\s*)$/, 'Pulse$1');
                }
            }
        };
        new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                if (mutation.type === 'characterData') relabel(mutation.target.parentNode || document);
                for (const node of mutation.addedNodes) relabel(node);
            }
        }).observe(document, { childList: true, subtree: true, characterData: true });
        document.addEventListener('DOMContentLoaded', () => relabel(document.body));
    })();
    """
}

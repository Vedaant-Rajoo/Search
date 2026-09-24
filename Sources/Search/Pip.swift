import WebKit
import ObjectiveC

/// WebKit's own picture-in-picture, one call down from the public framework —
/// the same pattern as `Muter`. Asked for by name first; a WebKit without the
/// selectors leaves Float to carry the video instead of crashing.
///
/// Unlike Float, this does not move the page. The video keeps playing in a
/// system window; the tab's layout is untouched.
enum Pip {
    private static let toggle = NSSelectorFromString("_togglePictureInPicture")
    private static let canToggle = NSSelectorFromString("_canTogglePictureInPicture")
    private static let isActive = NSSelectorFromString("_isPictureInPictureActive")
    private static let allowGet = NSSelectorFromString("_allowsPictureInPictureMediaPlayback")
    private static let allowSet = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")

    /// Every selector this path needs is present on this WebKit.
    static var available: Bool = {
        let probe = WKWebView(frame: .zero)
        return probe.responds(to: toggle)
            && probe.responds(to: canToggle)
            && probe.responds(to: isActive)
    }()

    /// Turn on WebKit's PiP preference for pages built with this configuration.
    static func allow(on preferences: WKPreferences) {
        guard preferences.responds(to: allowSet) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: allowSet), to: Setter.self)(preferences, allowSet, true)
    }

    static func active(on web: WKWebView) -> Bool {
        guard web.responds(to: isActive) else { return false }
        typealias Read = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(web.method(for: isActive), to: Read.self)(web, isActive)
    }

    static func canToggle(on web: WKWebView) -> Bool {
        guard web.responds(to: canToggle) else { return false }
        typealias Read = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(web.method(for: canToggle), to: Read.self)(web, canToggle)
    }

    /// Enter or leave system PiP. Returns false when the selectors are missing
    /// or WebKit says there is nothing to toggle yet.
    @discardableResult
    static func toggle(on web: WKWebView) -> Bool {
        guard available, web.responds(to: toggle) else { return false }
        guard canToggle(on: web) || active(on: web) else { return false }
        typealias Call = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(web.method(for: toggle), to: Call.self)(web, toggle)
        return true
    }

    /// Leave system PiP if it is up. No-op otherwise.
    static func exit(on web: WKWebView) {
        guard active(on: web) else { return }
        toggle(on: web)
    }
}

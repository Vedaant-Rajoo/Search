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

    /// Ask WebKit to enter or leave system PiP. The call is void; callers that
    /// need to know whether it took should check `active(on:)` on the next turn.
    /// `_canTogglePictureInPicture` is often false until a frame has painted,
    /// so it is not used as a hard gate here — only as a hint.
    @discardableResult
    static func toggle(on web: WKWebView) -> Bool {
        guard available, web.responds(to: toggle) else { return false }
        typealias Call = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(web.method(for: toggle), to: Call.self)(web, toggle)
        return true
    }

    /// Leave system PiP if it is up. No-op otherwise.
    static func exit(on web: WKWebView) {
        guard active(on: web) else { return }
        toggle(on: web)
    }

    /// Chrome-initiated enter via the video element's WebKit presentation API.
    /// Used when the private `_togglePictureInPicture` call did not take.
    /// Returns a short status string for the caller.
    static let enterJS = """
    (function () {
      var videos = document.querySelectorAll('video');
      var best = null, area = 0;
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (v.paused || v.ended || v.readyState < 2) continue;
        var box = v.getBoundingClientRect();
        if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
      }
      if (!best) return 'none';
      if (document.pictureInPictureElement === best
          || best.webkitPresentationMode === 'picture-in-picture') return 'already';
      try {
        if (typeof best.webkitSetPresentationMode === 'function') {
          best.webkitSetPresentationMode('picture-in-picture');
          return best.webkitPresentationMode === 'picture-in-picture' ? 'webkit' : 'webkit-called';
        }
      } catch (e) { return 'webkit-throw:' + (e && e.name); }
      try {
        if (best.requestPictureInPicture) {
          best.requestPictureInPicture();
          return 'request-called';
        }
      } catch (e) { return 'request-throw:' + (e && e.name); }
      return 'unsupported';
    })();
    """

    static let exitJS = """
    (function () {
      var v = document.pictureInPictureElement
        || document.querySelector('video[webkitpresentationmode="picture-in-picture"]')
        || document.querySelector('video');
      if (!v) return 'none';
      try {
        if (typeof v.webkitSetPresentationMode === 'function'
            && v.webkitPresentationMode === 'picture-in-picture') {
          v.webkitSetPresentationMode('inline');
          return 'webkit';
        }
      } catch (e) {}
      try {
        if (document.pictureInPictureElement && document.exitPictureInPicture) {
          document.exitPictureInPicture();
          return 'exit';
        }
      } catch (e) {}
      return 'none';
    })();
    """

    static let statusJS = """
    (function () {
      var v = document.querySelector('video');
      var mode = v && v.webkitPresentationMode;
      return !!(document.pictureInPictureElement || mode === 'picture-in-picture');
    })();
    """
}

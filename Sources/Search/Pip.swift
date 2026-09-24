import WebKit
import ObjectiveC

/// System picture-in-picture through the video element's public WebKit API.
/// The page stays in its tab; Float remains the fallback when this cannot enter.
enum Pip {
    private static let allowSet = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")

    /// WebKit refuses `webkitSetPresentationMode('picture-in-picture')` until
    /// this preference is on (measured on macOS 27 without it: enter fell
    /// through to Float). Same defensive ask-by-name pattern as `Muter`.
    static func allow(on preferences: WKPreferences) {
        guard preferences.responds(to: allowSet) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: allowSet), to: Setter.self)(preferences, allowSet, true)
    }

    /// Enter system PiP. Returns only after confirming the mode, or a reason
    /// it could not: `ok`, `none`, `disabled`, `unsupported`, `failed`, `pending`.
    static let enterJS = """
    (function () {
      var videos = document.querySelectorAll('video');
      var best = null, area = 0;
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (v.paused || v.ended || v.readyState < 2) continue;
        if (v.disablePictureInPicture) continue;
        var box = v.getBoundingClientRect();
        if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
      }
      if (!best) {
        for (var j = 0; j < videos.length; j++) {
          var d = videos[j];
          if (!d.paused && !d.ended && d.readyState >= 2 && d.disablePictureInPicture)
            return 'disabled';
        }
        return 'none';
      }
      if (best.webkitPresentationMode === 'picture-in-picture') return 'ok';
      if (typeof best.webkitSetPresentationMode !== 'function') return 'unsupported';
      try { best.webkitSetPresentationMode('picture-in-picture'); }
      catch (e) { return 'failed'; }
      return best.webkitPresentationMode === 'picture-in-picture' ? 'ok' : 'pending';
    })();
    """

    /// Second look after a pending enter — WebKit sometimes flips the mode
    /// on the next turn.
    static let confirmJS = """
    (function () {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        if (videos[i].webkitPresentationMode === 'picture-in-picture') return 'ok';
      }
      return 'failed';
    })();
    """

    static let exitJS = """
    (function () {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (v.webkitPresentationMode === 'picture-in-picture'
            && typeof v.webkitSetPresentationMode === 'function') {
          try { v.webkitSetPresentationMode('inline'); } catch (e) {}
        }
      }
      return 'done';
    })();
    """
}

/// Page events for system PiP, so closing the system window clears Search's
/// bookkeeping (and a "return to tab" can select the origin).
final class PipRelay: NSObject, WKScriptMessageHandler {
    static let name = "officePip"

    weak var tab: Tab?

    static let watch = """
    (function () {
      if (window.__officePip) return;
      window.__officePip = true;
      function tell(mode, returned) {
        try {
          window.webkit.messageHandlers.\(name).postMessage({
            mode: mode || 'inline',
            returned: !!returned
          });
        } catch (e) {}
      }
      document.addEventListener('webkitpresentationmodechanged', function (e) {
        var v = e.target;
        if (!v || !v.webkitPresentationMode) return;
        tell(v.webkitPresentationMode, false);
      }, true);
      document.addEventListener('leavepictureinpicture', function () {
        tell('inline', true);
      }, true);
      document.addEventListener('enterpictureinpicture', function () {
        tell('picture-in-picture', false);
      }, true);
    })();
    """

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        let mode = body["mode"] as? String ?? "inline"
        let returned = body["returned"] as? Bool ?? false
        MainActor.assumeIsolated { [weak self] in
            guard let self, let tab else { return }
            tab.onPipMode?(tab, mode, returned)
        }
    }
}

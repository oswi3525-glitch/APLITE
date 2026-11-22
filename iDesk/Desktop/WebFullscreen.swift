import WebKit

/// Fullscreen for web pages (YouTube, Netflix, embedded videos…).
///
/// WebKit on iPhone has no element Fullscreen API (only iPad has it), so pages say
/// "your browser does not support fullscreen". The script below emulates the API: the element that asks for
/// fullscreen covers the page, and iDesk expands the desktop window to fill the external display.
enum WebFullscreen {
    static let messageName = "ideskFullscreen"

    static let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)

    /// Leaves fullscreen from iDesk's side (Esc, closing the window…).
    static let exitScript = "window.__ideskExitFullscreen && window.__ideskExitFullscreen()"

    private static let source = #"""
    (function () {
      if (window.__ideskFullscreenInstalled) return;
      window.__ideskFullscreenInstalled = true;
      var current = null;

      var css = '[data-idesk-fullscreen]{position:fixed!important;left:0!important;top:0!important;' +
        'right:0!important;bottom:0!important;width:100vw!important;height:100vh!important;' +
        'max-width:none!important;max-height:none!important;min-width:0!important;min-height:0!important;' +
        'margin:0!important;padding:0!important;z-index:2147483647!important;background:#000!important;' +
        'transform:none!important;border:0!important}' +
        'html[data-idesk-fullscreen-root],html[data-idesk-fullscreen-root] body{overflow:hidden!important;background:#000!important}' +
        // Hide everything outside the fullscreen element (text, titles, comments no longer bleed into the video).
        // visibility is inherited: the element's children become visible again, the rest of the page stays hidden.
        'html[data-idesk-fullscreen-root] body{visibility:hidden!important}' +
        '[data-idesk-fullscreen]{visibility:visible!important}' +
        // An ancestor with transform / filter / contain makes "position:fixed" cover only that ancestor and caps
        // z-index inside it. Remove those properties and lift the ancestors to the top.
        '[data-idesk-fs-ancestor]{transform:none!important;filter:none!important;-webkit-filter:none!important;' +
        'backdrop-filter:none!important;-webkit-backdrop-filter:none!important;perspective:none!important;' +
        'contain:none!important;will-change:auto!important;clip-path:none!important;-webkit-mask:none!important;' +
        'z-index:2147483647!important;animation:none!important}' +
        // The page (YouTube) keeps the old video size in its own styles: force the video to fill the element.
        '[data-idesk-fullscreen] video{position:absolute!important;left:0!important;top:0!important;' +
        'width:100%!important;height:100%!important;max-width:none!important;max-height:none!important;' +
        'object-fit:contain!important;transform:none!important}' +
        '[data-idesk-fullscreen] .html5-video-container{position:absolute!important;left:0!important;top:0!important;' +
        'width:100%!important;height:100%!important}' +
        '[data-idesk-fullscreen] .ytp-chrome-bottom{left:12px!important;width:calc(100% - 24px)!important}';
      function addStyle() {
        var s = document.createElement('style');
        s.textContent = css;
        (document.head || document.documentElement).appendChild(s);
      }
      if (document.documentElement) addStyle(); else document.addEventListener('DOMContentLoaded', addStyle);

      function notify(on) {
        try { window.webkit.messageHandlers.ideskFullscreen.postMessage(on); } catch (e) {}
      }
      function fire(target) {
        ['fullscreenchange', 'webkitfullscreenchange'].forEach(function (type) {
          (target && target.isConnected ? target : document).dispatchEvent(new Event(type, { bubbles: true }));
        });
        window.dispatchEvent(new Event('resize'));
      }
      // Some pages (YouTube) request fullscreen for the whole <html> and expect the browser to relayout.
      // In that case expand the video player instead of the whole page.
      var players = '#movie_player, .html5-video-player, .jwplayer, .video-js, .plyr, .vjs-player';
      function area(node) { var r = node.getBoundingClientRect(); return r.width * r.height; }
      function visualTarget(el) {
        if (el !== document.documentElement && el !== document.body) return el;
        var known = Array.prototype.filter.call(document.querySelectorAll(players), function (n) { return area(n) > 0; });
        if (known.length) return known.sort(function (a, b) { return area(b) - area(a); })[0];
        var best = null, bestArea = 0;
        Array.prototype.forEach.call(document.querySelectorAll('video'), function (v) {
          var a = area(v);
          if (a > bestArea) { best = v; bestArea = a; }
        });
        if (!best) return el;
        // Walk up the wrappers around the video while they stay about the video's size (the player box).
        var target = best;
        for (var n = best.parentElement; n && n !== document.body && n !== document.documentElement; n = n.parentElement) {
          if (area(n) > bestArea * 1.5 + 1) break;
          target = n;
        }
        return target;
      }

      var shown = null;   // the element actually expanded (may differ from the one the page asked for)
      function markAncestors(node, on) {
        for (var n = node.parentElement; n && n !== document.documentElement; n = n.parentElement) {
          if (on) n.setAttribute('data-idesk-fs-ancestor', ''); else n.removeAttribute('data-idesk-fs-ancestor');
        }
      }
      function enter(el) {
        if (!el) return Promise.resolve();
        // The page requests fullscreen again for the element already in fullscreen: treat it as a toggle.
        // (YouTube does not always notice it is fullscreen, so its button then only "requests to enter".)
        if (current === el) return exit();
        if (shown) { shown.removeAttribute('data-idesk-fullscreen'); markAncestors(shown, false); }
        current = el;
        shown = visualTarget(el);
        shown.setAttribute('data-idesk-fullscreen', '');
        markAncestors(shown, true);
        document.documentElement.setAttribute('data-idesk-fullscreen-root', '');
        notify(true);
        // Wait for APLite to expand the window before telling the page, so it measures the right size.
        setTimeout(function () { fire(el); }, 120);
        return Promise.resolve();
      }
      function exit() {
        if (!current) return Promise.resolve();
        var el = current;
        current = null;
        if (shown) { shown.removeAttribute('data-idesk-fullscreen'); markAncestors(shown, false); }
        shown = null;
        document.documentElement.removeAttribute('data-idesk-fullscreen-root');
        notify(false);
        setTimeout(function () { fire(el); }, 120);
        return Promise.resolve();
      }
      window.__ideskExitFullscreen = exit;

      var E = Element.prototype, D = Document.prototype;
      E.requestFullscreen = function () { return enter(this); };
      E.webkitRequestFullscreen = E.webkitRequestFullScreen = function () { enter(this); };
      D.exitFullscreen = function () { return exit(); };
      D.webkitExitFullscreen = D.webkitCancelFullScreen = function () { exit(); };
      if (window.HTMLVideoElement) {
        // On iPhone, video.webkitEnterFullscreen() opens the native player on the phone screen: block it.
        var V = HTMLVideoElement.prototype;
        V.webkitEnterFullscreen = V.webkitEnterFullScreen = function () { enter(this); };
        V.webkitExitFullscreen = V.webkitExitFullScreen = function () { exit(); };
        try { Object.defineProperty(V, 'webkitSupportsFullscreen', { configurable: true, get: function () { return true; } }); } catch (e) {}
        try { Object.defineProperty(V, 'webkitDisplayingFullscreen', { configurable: true, get: function () { return current === this; } }); } catch (e) {}
      }
      function getter(name, fn) {
        try { Object.defineProperty(D, name, { configurable: true, get: fn }); } catch (e) {}
      }
      getter('fullscreenElement', function () { return current; });
      getter('webkitFullscreenElement', function () { return current; });
      getter('webkitCurrentFullScreenElement', function () { return current; });
      getter('fullscreenEnabled', function () { return true; });
      getter('webkitFullscreenEnabled', function () { return true; });
      getter('webkitFullScreenKeyboardInputAllowed', function () { return true; });
      getter('fullscreen', function () { return !!current; });
      getter('webkitIsFullScreen', function () { return !!current; });

      window.addEventListener('keydown', function (e) {
        if (current && (e.key === 'Escape' || e.keyCode === 27)) exit();
      }, true);
    })();
    """#
}

/// Receives "enter / leave fullscreen" messages from the page. Holds the window weakly:
/// WKUserContentController retains its handler, so a strong reference would leak the window forever.
final class WebFullscreenBridge: NSObject, WKScriptMessageHandler {
    weak var window: DeskWindow?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // Only the tab shown can take the window fullscreen.
        guard let on = message.body as? Bool, let window, message.webView === window.webView else { return }
        window.fullscreenFrame = on ? message.frameInfo : nil
        window.onFullscreen?(on)
    }
}

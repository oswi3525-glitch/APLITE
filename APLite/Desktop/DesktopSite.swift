import WebKit

/// Makes sites serve their desktop version.
///
/// Asking WebKit for desktop websites only changes the user agent to a Mac's. Many sites still tell a phone apart
/// by what the page itself reports: a touch screen (`maxTouchPoints`, `ontouchstart`, `TouchEvent`), a screen 393
/// points wide, or `(pointer: coarse)`. Then they send their phone layout, which WebKit scales to the window, so the
/// page looks like a zoomed phone page. This script, run before the page's own scripts, reports what the desktop
/// really is: the monitor's size, a mouse, no touch screen. (APLite's clicks and scrolling are not touch events,
/// so nothing depends on them.)
enum DesktopSite {
    static func script(screen: CGSize) -> WKUserScript {
        let w = Int(max(screen.width, 1280)), h = Int(max(screen.height, 720))
        let source = """
        (function () {
          if (window.__ideskDesktop) return;
          window.__ideskDesktop = true;
          function define(target, name, value) {
            try { Object.defineProperty(target, name, { configurable: true, get: function () { return value; } }); } catch (e) {}
          }
          // No touch screen.
          define(Navigator.prototype, 'maxTouchPoints', 0);
          define(Navigator.prototype, 'msMaxTouchPoints', 0);
          [window, Window.prototype, Document.prototype, HTMLElement.prototype, Element.prototype,
           typeof SVGElement !== 'undefined' ? SVGElement.prototype : null].forEach(function (o) {
            if (!o) return;
            ['ontouchstart', 'ontouchmove', 'ontouchend', 'ontouchcancel'].forEach(function (k) {
              try { delete o[k]; } catch (e) {}
            });
          });
          try { delete window.TouchEvent; } catch (e) {}
          try { delete window.Touch; } catch (e) {}
          try { delete window.TouchList; } catch (e) {}
          // The monitor's size, not the iPhone's.
          define(Screen.prototype, 'width', \(w));
          define(Screen.prototype, 'height', \(h));
          define(Screen.prototype, 'availWidth', \(w));
          define(Screen.prototype, 'availHeight', \(h));
          // A mouse: (pointer: fine) and (hover: hover) match, (pointer: coarse) and (hover: none) do not.
          var matchMedia = window.matchMedia;
          if (matchMedia) {
            window.matchMedia = function (query) {
              var list = matchMedia.call(window, query);
              var q = String(query).toLowerCase().replace(/\\s+/g, '');
              var forced = null;
              if (/\\((any-)?pointer:coarse\\)|\\((any-)?hover:none\\)/.test(q)) forced = false;
              else if (/\\((any-)?pointer:fine\\)|\\((any-)?hover:hover\\)/.test(q)) forced = true;
              if (forced === null) return list;
              if (/^not/.test(q)) forced = !forced;
              return {
                matches: forced, media: list.media, onchange: null,
                addListener: function () {}, removeListener: function () {},
                addEventListener: function () {}, removeEventListener: function () {},
                dispatchEvent: function () { return false; }
              };
            };
          }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}

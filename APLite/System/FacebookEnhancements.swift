import Foundation
import WebKit

/// A light "Clean Facebook" treatment for the web app on the desktop. Facebook is a web shortcut
/// (no native IPA): all we can do is inject CSS/JS into its own page, scoped to facebook.com and never
/// to APLite's own pages. It keeps the account and feed intact — it only tidies the layout, rounds the
/// cards, hides the busiest side rails on narrow windows and marks obvious sponsored units.
enum FacebookEnhancements {
    static var enabled: Bool {
        get { APLiteSettings.bool("applications", "facebookEnhancements", default: true) }
        set {
            APLiteSettings.set("applications", "facebookEnhancements", newValue)
            for window in DesktopModel.shared.windows {
                for tab in window.tabs {
                    tab.evaluateJavaScript("window.__apliteFB && window.__apliteFB(\(newValue))")
                }
            }
        }
    }

    /// Added to every tab; the script itself decides whether it applies to the current host.
    static var script: WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private static let source = """
    (() => {
      if (!/(^|\\.)facebook\\.com$/.test(location.hostname)) return;
      let enabled = \(enabled);
      const ID = 'aplite-fb-style';
      const css = `
      html.aplite-fb body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      html.aplite-fb [data-pagelet="FeedUnit"], html.aplite-fb .aplite-fb-card {
        border-radius: 16px !important; overflow: hidden; margin: 14px 0 !important;
        box-shadow: 0 2px 12px rgba(0,0,0,.08) !important;
      }
      html.aplite-fb [role="banner"], html.aplite-fb [data-pagelet="TopBar"] {
        position: sticky !important; top: 0; z-index: 100 !important;
        backdrop-filter: saturate(150%) blur(18px); -webkit-backdrop-filter: saturate(150%) blur(18px);
      }
      html.aplite-fb img[referrerpolicy] { border-radius: 10px; }
      html.aplite-fb [aria-label="Photos"], html.aplite-fb [aria-label="Reels"] { border-radius: 14px; }
      html.aplite-fb .aplite-fb-ad { display: none !important; }
      html.aplite-fb ::-webkit-scrollbar { width: 10px; height: 10px; }
      html.aplite-fb ::-webkit-scrollbar-thumb { background: rgba(128,128,128,.45); border-radius: 8px; }
      @media (max-width: 1180px) {
        html.aplite-fb [data-pagelet="RightRail"], html.aplite-fb [data-pagelet="RightRailTop"],
        html.aplite-fb [data-pagelet="Chat"], html.aplite-fb [aria-label="Contacts"] { display: none !important; }
      }
      @media (max-width: 900px) {
        html.aplite-fb [data-pagelet="LeftRail"] { display: none !important; }
      }
      `;
      function apply() {
        const html = document.documentElement;
        html.classList.toggle('aplite-fb', enabled);
        scanned = 0;   // a new page or a toggle starts a fresh pass over the feed
        let style = document.getElementById(ID);
        if (enabled && !style) {
          style = document.createElement('style');
          style.id = ID;
          style.textContent = css;
          (document.head || html).appendChild(style);
        } else if (!enabled && style) { style.remove(); }
      }
      // Facebook replaces DOM nodes constantly. Re-add the stylesheet if it is dropped.
      const head = document.head || document.documentElement;
      if (window.MutationObserver) {
        new MutationObserver(() => {
          if (enabled) apply();
          markAds();
        }).observe(head, { childList: true, subtree: false });
      }
      let scanned = 0;
      function markAds() {
        if (!enabled) return;
        const cards = document.querySelectorAll('[data-pagelet="FeedUnit"]');
        cards.forEach(c => {
          if (c.dataset.apliteSeen) return;
          if (++scanned > 400) return;   // per pass, not for the whole session
          c.dataset.apliteSeen = '1';
          const text = (c.innerText || '').slice(0, 600).toLowerCase();
          if (/sponsored|được tài trợ|publicidad|sponsorisé/.test(text)) c.classList.add('aplite-fb-ad');
        });
      }
      window.__apliteFB = on => { enabled = !!on; apply(); markAds(); };
      apply();
      setTimeout(markAds, 1200);
      setTimeout(markAds, 4000);
    })();
    """
}

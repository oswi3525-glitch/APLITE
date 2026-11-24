import Foundation
import WebKit

/// YouTube serves ads from its own domain, so the third-party content blocker (which deliberately
/// allow-lists youtube.com to avoid breaking playback) cannot remove them. This small main-frame
/// user script hides the ad containers and clicks YouTube's own skip/close buttons. It is injected
/// into every page but exits immediately unless the host is a YouTube domain.
enum YouTubeAds {
    static let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)

    private static let source = #"""
    (() => {
      if (!/(^|\.)youtube\.com$|(^|\.)youtube-nocookie\.com$/.test(location.hostname)) return;
      if (window.__apliteYouTubeAds) return;
      window.__apliteYouTubeAds = true;

      const css = `
        .video-ads, .ytp-ad-module, .ytp-ad-player-overlay,
        .ytp-ad-overlay-container, .ytp-ad-image-overlay, #player-ads,
        ytd-promoted-sparkles-web-renderer, ytd-display-ad-renderer,
        ytd-companion-slot-renderer, .ytd-ad-slot-renderer {
          display: none !important;
        }`;
      const style = document.createElement('style');
      style.textContent = css;
      (document.head || document.documentElement).appendChild(style);

      const selectors = [
        '.ytp-ad-skip-button', '.ytp-ad-skip-button-modern', '.ytp-ad-skip-button-container',
        '.ytp-ad-overlay-close-button', '.ytp-ad-text-click-area',
        'button[aria-label^="Skip ad"]', 'button[title^="Skip ad"]'
      ];
      function click() {
        for (const selector of selectors) {
          const nodes = document.querySelectorAll(selector);
          for (const node of nodes) {
            if (node.offsetParent !== null) { node.click(); return true; }
          }
        }
        return false;
      }
      const tick = () => { click(); };
      tick();
      setInterval(tick, 350);
      new MutationObserver(tick).observe(document.documentElement || document.body,
        { childList: true, subtree: true });
    })();
    """#
}

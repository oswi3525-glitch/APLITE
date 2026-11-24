import Foundation
import WebKit

/// YouTube serves ads from its own domain, so the third-party content blocker (which deliberately
/// allow-lists youtube.com to avoid breaking playback) cannot remove them. This small main-frame
/// user script hides the ad containers and clicks YouTube's own skip/close buttons, including the
/// ones rendered inside Web Component shadow roots. It is injected into every page but exits
/// immediately unless the host is a YouTube domain.
enum YouTubeAds {
    static let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)

    private static let source = #"""
    (() => {
      if (!/(^|\.)youtube\.com$|(^|\.)youtube-nocookie\.com$|(^|\.)youtu\.be$/.test(location.hostname)) return;
      if (window.__apliteYouTubeAds) return;
      window.__apliteYouTubeAds = true;

      const css = `
        .video-ads, .ytp-ad-module, .ytp-ad-player-overlay,
        .ytp-ad-overlay-container, .ytp-ad-image-overlay, #player-ads,
        ytd-promoted-sparkles-web-renderer, ytd-display-ad-renderer,
        ytd-companion-slot-renderer, .ytd-ad-slot-renderer {
          display: none !important;
        }`;
      const selectors = [
        '.ytp-ad-skip-button', '.ytp-ad-skip-button-modern', '.ytp-ad-skip-button-container',
        '.ytp-ad-overlay-close-button', '.ytp-ad-text-click-area',
        'button[aria-label^="Skip ad"]', 'button[title^="Skip ad"]'
      ];
      const shadowRoots = new Set();

      function installStyles(root) {
        if (root.querySelector && root.querySelector('style[data-aplite-ads]')) return;
        const style = document.createElement('style');
        style.setAttribute('data-aplite-ads', '1');
        style.textContent = css;
        (root.head || root).appendChild(style);
      }
      function scan(root) {
        for (const el of root.querySelectorAll('*')) {
          if (!el.shadowRoot || shadowRoots.has(el.shadowRoot)) continue;
          shadowRoots.add(el.shadowRoot);
          installStyles(el.shadowRoot);
          new MutationObserver(tick).observe(el.shadowRoot, { childList: true, subtree: true });
          scan(el.shadowRoot);
        }
      }
      function click() {
        for (const root of [document, ...shadowRoots]) {
          for (const selector of selectors) {
            for (const node of root.querySelectorAll(selector)) {
              if (node.offsetParent !== null) { node.click(); return true; }
            }
          }
        }
        return false;
      }
      function tick() {
        scan(document);
        click();
      }
      installStyles(document);
      tick();
      setInterval(tick, 350);
      new MutationObserver(tick).observe(document.documentElement || document.body,
        { childList: true, subtree: true });
    })();
    """#
}

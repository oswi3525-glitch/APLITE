import SwiftUI
import WebKit

// MARK: - Floating video

/// Window menu → Floating video: the biggest video on the page fills the window, which shrinks to a small player in
/// the corner and stays on top of the other windows; the same item (or the green button) brings the page back.
enum FloatingVideo {
    /// Marks the biggest video (playing first) and makes it fill the page; returns false when there is none.
    static let enterScript = """
    (() => {
      const vids = Array.from(document.querySelectorAll('video')).filter(v => v.getClientRects().length);
      if (!vids.length) return false;
      vids.sort((a, b) => (b.paused ? 0 : 1) - (a.paused ? 0 : 1) || (b.clientWidth * b.clientHeight) - (a.clientWidth * a.clientHeight));
      const v = vids[0];
      if (!document.getElementById('idesk-float-css')) {
        const st = document.createElement('style'); st.id = 'idesk-float-css';
        st.textContent = 'html.idesk-float, html.idesk-float body{overflow:hidden!important}'
          + 'video.idesk-float-video{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;'
          + 'max-width:none!important;max-height:none!important;z-index:2147483647!important;background:#000!important;object-fit:contain!important;transform:none!important}';
        (document.head || document.documentElement).appendChild(st);
      }
      v.classList.add('idesk-float-video');
      document.documentElement.classList.add('idesk-float');
      if (v.paused) v.play().catch(() => {});
      return true;
    })()
    """
    static let exitScript = """
    document.querySelectorAll('.idesk-float-video').forEach(v => v.classList.remove('idesk-float-video'));
    document.documentElement.classList.remove('idesk-float');
    """
}

extension DesktopModel {
    func toggleFloatingVideo(_ w: DeskWindow) {
        guard let web = w.webView else { return }
        if let r = w.floatingRestore {
            web.evaluateJavaScript(FloatingVideo.exitScript)
            w.floatingRestore = nil
            w.keepOnTop = r.keepOnTop
            w.isMaximized = r.maximized
            w.isSnapped = r.snapped
            w.frame = r.frame
            focus(w)
            return
        }
        web.evaluateJavaScript(FloatingVideo.enterScript) { [weak self, weak w] result, _ in
            guard let self, let w else { return }
            guard result as? Bool == true else { self.showToast(String(localized: "No video on this page")); return }
            if w.isFullscreen { self.setFullscreen(w, false) }
            w.floatingRestore = (w.frame, w.isMaximized, w.isSnapped, w.keepOnTop)
            let width: CGFloat = min(480, self.desktopArea.width * 0.35)
            let size = CGSize(width: width, height: (width * 9 / 16).rounded() + Layout.titleBar)
            w.isMaximized = false
            w.isSnapped = false
            w.frame = CGRect(x: self.desktopArea.maxX - size.width - 16, y: self.desktopArea.maxY - size.height - 16,
                             width: size.width, height: size.height)
            w.keepOnTop = true
            self.focus(w)
        }
    }
}

// MARK: - Presentation mode

/// Window menu → Present: the window goes fullscreen and the iPhone becomes a remote (next, previous, a laser
/// pointer that follows the finger, the time since the start).
struct PresentationState {
    let window: UUID
    let started = Date()
}

extension DesktopModel {
    func startPresentation(_ w: DeskWindow) {
        closePanels()
        if w.floatingRestore != nil { toggleFloatingVideo(w) }
        focus(w)
        setFullscreen(w, true)
        presentation = PresentationState(window: w.id)
    }

    func endPresentation() {
        if let id = presentation?.window, let w = windows.first(where: { $0.id == id }), w.isFullscreen { setFullscreen(w, false) }
        presentation = nil
        laser = nil
    }

    /// Next / previous slide: arrow keys for slides, page keys for a PDF.
    func presentationStep(_ delta: Int) {
        guard let id = presentation?.window, let w = windows.first(where: { $0.id == id }) else { return }
        focus(w)
        let pdf = w.currentURL.pathExtension.lowercased() == "pdf"
        let key = pdf ? (delta > 0 ? "PageDown" : "PageUp") : (delta > 0 ? "ArrowRight" : "ArrowLeft")
        let code = pdf ? (delta > 0 ? 34 : 33) : (delta > 0 ? 39 : 37)
        sendKey(key, code, false)
    }
}

/// The red dot of the laser pointer.
struct LaserDot: View {
    let point: CGPoint
    var body: some View {
        Circle().fill(APLiteColors.red)
            .frame(width: 16, height: 16)
            .shadow(color: APLiteColors.red, radius: 10)
            .shadow(color: APLiteColors.red.opacity(0.6), radius: 22)
            .offset(x: point.x - 8, y: point.y - 8)
            .allowsHitTesting(false)
    }
}

/// On the iPhone while presenting: previous / next, a pad for the laser pointer, the time, and End.
struct PresentationRemote: View {
    @ObservedObject var model: DesktopModel
    let state: PresentationState

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Presenting", systemImage: "play.rectangle.fill").font(.headline)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.elapsed(since: state.started, now: ctx.date)).font(.title3.monospacedDigit())
                }
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(white: 0.13))
                    .overlay(Text("Hold and move your finger here for the laser pointer")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let s = model.screenSize
                            model.laser = CGPoint(x: min(max(0, g.location.x / geo.size.width), 1) * s.width,
                                                  y: min(max(0, g.location.y / geo.size.height), 1) * s.height)
                        }
                        .onEnded { _ in model.laser = nil })
            }
            HStack(spacing: 14) {
                Button { model.presentationStep(-1) } label: {
                    Label("Previous", systemImage: "chevron.left").frame(maxWidth: .infinity, minHeight: 64)
                }
                Button { model.presentationStep(1) } label: {
                    Label("Next", systemImage: "chevron.right").frame(maxWidth: .infinity, minHeight: 64)
                }
            }
            .buttonStyle(.borderedProminent)
            .font(.title3.weight(.semibold))
            Button(role: .destructive) { model.endPresentation() } label: {
                Text("End presentation").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
    }

    static func elapsed(since start: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Web audio activity

/// Tracks whether any open web tab is actually playing media. APLite uses this to release the
/// audio session when the desktop is quiet — a permanently active session keeps the audio hardware
/// powered and is a noticeable source of heat on iPhone/iPad.
final class WebAudioActivity {
    static let shared = WebAudioActivity()

    private final class WeakWebView {
        weak var view: WKWebView?
        init(_ view: WKWebView) { self.view = view }
    }

    private var playing: [WeakWebView] = []
    private let lock = NSLock()

    var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        playing.removeAll { $0.view == nil }
        return !playing.isEmpty
    }

    func set(webView: WKWebView?, active: Bool) {
        lock.lock(); defer { lock.unlock() }
        playing.removeAll { $0.view == nil || (webView != nil && $0.view === webView) }
        if active, let webView { playing.append(WeakWebView(webView)) }
    }
}

final class WebAudioBridge: NSObject, WKScriptMessageHandler {
    static let shared = WebAudioBridge()
    static let messageName = "ideskAudioActivity"

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let info = message.body as? [String: Any],
           let bands = (info["bands"] as? [Any])?.compactMap({ $0 as? NSNumber }) {
            AudioSpectrumProvider.shared.ingest(webBands: bands.map(\.floatValue))
            return
        }
        // Older pages still post a bare Bool; both shapes are accepted.
        let info: [String: Any]?
        let active: Bool
        if let dict = message.body as? [String: Any] {
            info = dict
            active = (dict["playing"] as? Bool) == true
        } else {
            info = nil
            active = (message.body as? Bool) == true
        }
        WebAudioActivity.shared.set(webView: message.webView, active: active)
        NowPlayingService.shared.updateWeb(playing: active, info: info, webView: message.webView)
    }
}

// MARK: - Volume of web videos

/// On iOS a page cannot change a video's volume (HTMLMediaElement.volume stays 1: the iPhone's buttons set it), so
/// a player's volume slider (YouTube's…) does nothing but mute. Here the volume a page sets goes through Web Audio:
/// the video's sound passes a gain set to that volume. Only for videos from the page's own site or a blob (which is
/// how YouTube plays), as Web Audio gets silence from other sites' media.
enum WebVolume {
    static let script = WKUserScript(source: #"""
    (() => {
      const proto = HTMLMediaElement.prototype;
      if (proto.__ideskVolume) return; proto.__ideskVolume = true;
      const volumes = new WeakMap(), routes = new WeakMap();
      let ctx = null;
      function routable(el) {
        const src = el.currentSrc || el.src || '';
        if (!src || src.startsWith('blob:')) return true;
        try { return new URL(src, location.href).origin === location.origin || !!el.crossOrigin; } catch (e) { return false; }
      }
      // The context starts only once sound may play (APLite's clicks are not touches on the page): until then the
      // volume waits, and is put on the video's sound as soon as it runs.
      function context() {
        if (!ctx) {
          try { ctx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return null; }
          ctx.onstatechange = () => { if (ctx.state === 'running') pending.forEach(applyTo); };
        }
        if (ctx.state !== 'running') ctx.resume().catch(() => {});
        return ctx;
      }
      const pending = new Set();
      function applyTo(el) {
        const v = volumes.has(el) ? volumes.get(el) : 1;
        let r = routes.get(el);
        pending.delete(el);   // a restored element must not stay referenced forever
        if (!r) {
          // Only same-origin/blob media may be routed: touching a cross-origin element's sound makes it silent.
          if (!routable(el)) return;
          const c = context();
          if (!c || c.state !== 'running') { pending.add(el); return; }
          try {
            const gain = c.createGain(), meter = c.createAnalyser();
            meter.fftSize = 512; meter.smoothingTimeConstant = 0.7;
            c.createMediaElementSource(el).connect(gain).connect(meter).connect(c.destination);
            r = { gain, meter };
            routes.set(el, r);
          } catch (e) { return; }
        }
        pending.delete(el);
        r.gain.gain.value = v;
      }
      // Sound may play now: a context created here starts, and any volume set before is applied.
      document.addEventListener('play', e => {
        if (e.target instanceof HTMLMediaElement) { context(); applyTo(e.target); }
      }, true);
      Object.defineProperty(proto, 'volume', {
        configurable: true, enumerable: true,
        get() { return volumes.has(this) ? volumes.get(this) : 1; },
        set(v) {
          v = Number(v);
          if (!(v >= 0 && v <= 1)) throw new DOMException('The volume must be between 0 and 1.', 'IndexSizeError');
          if (volumes.get(this) === v) return;
          volumes.set(this, v);
          applyTo(this);
          this.dispatchEvent(new Event('volumechange'));
        }
      });
      // For checking: how loud the page's videos are now after the volume (0…1), and the context's state.
      window.__ideskVolumeLevel = () => {
        let peak = 0;
        document.querySelectorAll('video, audio').forEach(el => {
          const r = routes.get(el); if (!r) return;
          const a = new Float32Array(r.meter.fftSize); r.meter.getFloatTimeDomainData(a);
          for (const x of a) peak = Math.max(peak, Math.abs(x));
        });
        return (ctx ? ctx.state : 'none') + ' ' + peak.toFixed(3);
      };
      // Called from native code after an interruption / route change. A Web Audio context created
      // while the session was inactive stays suspended forever without this nudge.
      window.__ideskVolumeResume = () => {
        context();
        pending.forEach(applyTo);
      };
      // Tell native code whether this tab is really playing and what the Dynamic Island should show.
      function activeMedia() {
        return Array.from(document.querySelectorAll('video, audio'))
          .find(m => !m.paused && !m.ended && m.currentTime > 0) || null;
      }
      function reportActivity() {
        const m = activeMedia();
        if (!m) {
          try { window.webkit.messageHandlers.ideskAudioActivity.postMessage({ playing: false }); } catch (_) {}
          return;
        }
        const meta = document.querySelector('meta[property="og:image"]');
        const info = {
          playing: true,
          title: m.getAttribute('title') || document.title || '',
          subtitle: m.getAttribute('data-artist') || '',
          artwork: m.poster || (meta && meta.content) || '',
          duration: isFinite(m.duration) ? m.duration : 0,
          currentTime: m.currentTime || 0,
          isVideo: m.tagName === 'VIDEO'
        };
        try { window.webkit.messageHandlers.ideskAudioActivity.postMessage(info); } catch (_) {}
      }
      document.addEventListener('play', reportActivity, true);
      document.addEventListener('pause', reportActivity, true);
      document.addEventListener('ended', reportActivity, true);
      document.addEventListener('timeupdate', reportActivity, true);
      setInterval(reportActivity, 4000);
      reportActivity();
      // Web Audio's AnalyserNode already does the FFT. Send 12 log-spaced bands at <= 30 Hz, only while the
      // pill is expanded (native sets this flag); a collapsed pill uses a static wave and costs nothing.
      let lastSpectrum = 0;
      function spectrumFrame(t) {
        if (window.__ideskSpectrumWanted && t - lastSpectrum >= 33) {
          lastSpectrum = t;
          const m = activeMedia(), r = m && routes.get(m);
          if (r) {
            const bins = new Uint8Array(r.meter.frequencyBinCount);
            r.meter.getByteFrequencyData(bins);
            const out = [], n = 12;
            for (let b = 0; b < n; b++) {
              const from = Math.floor(Math.pow(bins.length / 2, b / n));
              const to = Math.max(from + 1, Math.floor(Math.pow(bins.length / 2, (b + 1) / n)));
              let peak = 0;
              for (let i = from; i < to && i < bins.length; i++) peak = Math.max(peak, bins[i]);
              out.push(peak / 255);
            }
            try { window.webkit.messageHandlers.ideskAudioActivity.postMessage({ bands: out }); } catch (_) {}
          }
        }
        requestAnimationFrame(spectrumFrame);
      }
      requestAnimationFrame(spectrumFrame);
    })();
    """#, injectionTime: .atDocumentStart, forMainFrameOnly: false)
}

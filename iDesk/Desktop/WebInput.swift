import WebKit

/// The external display takes no touches, so clicks / scrolling / typing are injected into the page with JavaScript.
enum WebInput {
    private static func run(_ webView: WKWebView, _ body: String, _ args: [String: Any]) {
        webView.callAsyncJavaScript(body, arguments: args, in: nil, in: .page, completionHandler: nil)
    }

    /// A page in "desktop" mode can be wider than the web view, so it is scaled down.
    /// Pointer coordinates are in web view points and must be converted to the page's CSS pixels.
    private static func scaleArgs(_ webView: WKWebView, _ p: CGPoint, _ extra: [String: Any] = [:]) -> [String: Any] {
        let s = webView.bounds.size
        var a: [String: Any] = ["x": Double(p.x), "y": Double(p.y),
                                "vw": Double(max(1, s.width)), "vh": Double(max(1, s.height))]
        a.merge(extra) { _, new in new }
        return a
    }

    /// JS prefix for every command: converts x,y (web view points) → cx,cy (page CSS pixels).
    private static let scaleHead = """
    const sx = (window.innerWidth || document.documentElement.clientWidth || vw) / vw;
    const sy = (window.innerHeight || document.documentElement.clientHeight || vh) / vh;
    const cx = x * sx, cy = y * sy;
    """

    /// A file dropped on the page at a point: put in the file field there, else dropped the way a computer drops a
    /// file (Gmail, Drive, WhatsApp Web… take it as an upload). Calls back false when the page threw.
    static func dropFile(_ webView: WKWebView, at p: CGPoint, name: String, type: String, data: Data,
                         completion: @escaping (Bool) -> Void) {
        webView.callAsyncJavaScript(scaleHead + """
        const bin = atob(b64), bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        const file = new File([bytes], name, { type: type, lastModified: Date.now() });
        const dt = new DataTransfer(); dt.items.add(file);
        const el = document.elementFromPoint(cx, cy) || document.body;
        const input = el.closest('input[type=file]') || (el.tagName === 'LABEL' && el.control && el.control.type === 'file' ? el.control : null);
        if (input) {
          input.files = dt.files;
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
          return 'field';
        }
        // WebKit ignores the dataTransfer given to a made-up DragEvent: it is set on the event afterwards.
        for (const t of ['dragenter', 'dragover', 'drop']) {
          const ev = new DragEvent(t, { bubbles: true, cancelable: true, clientX: cx, clientY: cy });
          Object.defineProperty(ev, 'dataTransfer', { value: dt });
          el.dispatchEvent(ev);
        }
        return 'drop';
        """, arguments: scaleArgs(webView, p, ["b64": data.base64EncodedString(), "name": name, "type": type]),
           in: nil, in: .page) { result in
            if case .failure(let e) = result { NSLog("[iDesk] drop on page failed: %@", "\(e)") }
            if case .failure = result { completion(false) } else { completion(true) }
        }
    }

    static func click(_ webView: WKWebView, at p: CGPoint, count: Int = 1) {
        run(webView, scaleHead + """
        const e = document.elementFromPoint(cx, cy);
        if (!e) return;
        const o = { bubbles: true, cancelable: true, clientX: cx, clientY: cy, view: window, detail: n, button: 0 };
        e.dispatchEvent(new PointerEvent('pointerdown', o));
        e.dispatchEvent(new MouseEvent('mousedown', o));
        if (typeof e.focus === 'function') e.focus();
        e.dispatchEvent(new PointerEvent('pointerup', o));
        e.dispatchEvent(new MouseEvent('mouseup', o));
        e.click();
        if (n === 2) e.dispatchEvent(new MouseEvent('dblclick', o));
        """, scaleArgs(webView, p, ["n": count]))
    }

    /// The file of the Files page row at a point (not on its buttons), for dragging it to the desktop.
    static func fileName(_ webView: WKWebView, at p: CGPoint, completion: @escaping (String?) -> Void) {
        webView.callAsyncJavaScript(scaleHead + """
        const e = document.elementFromPoint(cx, cy);
        if (!e || e.closest('button')) return null;
        if (e.closest('input, .check')) return null;
        const row = e.closest('tr[data-path]');
        return row ? row.dataset.path : null;
        """, arguments: scaleArgs(webView, p, [:]), in: nil, in: .page) { result in
            completion(try? result.get() as? String)
        }
    }

    /// Hover: fires mouseover/mousemove/mouseout and returns the matching pointer style.
    static func hover(_ webView: WKWebView, at p: CGPoint, completion: @escaping (CursorStyle) -> Void) {
        webView.callAsyncJavaScript(scaleHead + """
        const e = document.elementFromPoint(cx, cy);
        const prev = window.__ideskHover;
        const o = { bubbles: true, cancelable: true, clientX: cx, clientY: cy, view: window };
        if (e !== prev) {
          if (prev && prev.isConnected) {
            prev.dispatchEvent(new PointerEvent('pointerout', o));
            prev.dispatchEvent(new MouseEvent('mouseout', { ...o, relatedTarget: e }));
            prev.dispatchEvent(new MouseEvent('mouseleave', { ...o, bubbles: false }));
          }
          if (e) {
            e.dispatchEvent(new PointerEvent('pointerover', o));
            e.dispatchEvent(new MouseEvent('mouseover', { ...o, relatedTarget: prev || null }));
            e.dispatchEvent(new MouseEvent('mouseenter', { ...o, bubbles: false }));
          }
          window.__ideskHover = e;
        }
        if (!e) return 'default';
        e.dispatchEvent(new PointerEvent('pointermove', o));
        e.dispatchEvent(new MouseEvent('mousemove', o));
        const c = getComputedStyle(e).cursor;
        if (c === 'pointer' || e.closest('a[href],button,[role=button],summary,label,select')) return 'pointer';
        if (c === 'text' || e.closest('input,textarea,[contenteditable]:not([contenteditable=false])')) return 'text';
        return 'default';
        """, arguments: scaleArgs(webView, p), in: nil, in: .page) { result in
            var style = CursorStyle.arrow
            if case let .success(v) = result, let s = v as? String {
                style = s == "pointer" ? .pointer : s == "text" ? .text : .arrow
            }
            completion(style)
        }
    }

    /// Right click: sends contextmenu to the page. handled = the page handled it (has its own menu).
    static func contextInfo(_ webView: WKWebView, at p: CGPoint, completion: @escaping (Bool, String?) -> Void) {
        webView.callAsyncJavaScript(scaleHead + """
        const e = document.elementFromPoint(cx, cy);
        if (!e) return { handled: false, href: null };
        const o = { bubbles: true, cancelable: true, clientX: cx, clientY: cy, view: window, button: 2, buttons: 2 };
        e.dispatchEvent(new PointerEvent('pointerdown', o));
        e.dispatchEvent(new MouseEvent('mousedown', o));
        e.dispatchEvent(new PointerEvent('pointerup', o));
        e.dispatchEvent(new MouseEvent('mouseup', o));
        const ok = e.dispatchEvent(new MouseEvent('contextmenu', o));
        const a = e.closest('a[href]');
        return { handled: !ok, href: a ? a.href : null };
        """, arguments: scaleArgs(webView, p), in: nil, in: .page) { result in
            guard case let .success(v) = result, let d = v as? [String: Any] else { completion(false, nil); return }
            completion((d["handled"] as? Bool) ?? false, d["href"] as? String)
        }
    }

    static func scroll(_ webView: WKWebView, at p: CGPoint, dx: CGFloat, dy: CGFloat) {
        run(webView, scaleHead + """
        let e = document.elementFromPoint(cx, cy);
        while (e && e !== document.body && e !== document.documentElement) {
          const s = getComputedStyle(e);
          const canY = /(auto|scroll)/.test(s.overflowY) && e.scrollHeight > e.clientHeight;
          const canX = /(auto|scroll)/.test(s.overflowX) && e.scrollWidth > e.clientWidth;
          if ((dy !== 0 && canY) || (dx !== 0 && canX)) { e.scrollBy(dx, dy); return; }
          e = e.parentElement;
        }
        window.scrollBy(dx, dy);
        """, scaleArgs(webView, p, ["dx": Double(dx), "dy": Double(dy)]))
    }

    static func type(_ webView: WKWebView, text: String) {
        run(webView, """
        const e = document.activeElement;
        if (!e) return;
        if (e.isContentEditable) { document.execCommand('insertText', false, s); return; }
        if ('value' in e) {
          try { e.setRangeText(s, e.selectionStart, e.selectionEnd, 'end'); }
          catch (_) { e.value += s; }
          e.dispatchEvent(new InputEvent('input', { bubbles: true, data: s, inputType: 'insertText' }));
        }
        """, ["s": text])
    }

    static func backspace(_ webView: WKWebView) {
        run(webView, """
        const e = document.activeElement;
        if (!e) return;
        if (!e.dispatchEvent(new KeyboardEvent('keydown', { key: 'Backspace', code: 'Backspace', keyCode: 8, bubbles: true, cancelable: true }))) return;
        if (e.isContentEditable) { document.execCommand('delete'); return; }
        if ('value' in e) {
          try {
            let a = e.selectionStart, b = e.selectionEnd;
            if (a === b && a > 0) a -= 1;
            e.setRangeText('', a, b, 'end');
          } catch (_) { e.value = e.value.slice(0, -1); }
          e.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'deleteContentBackward' }));
        }
        """, [:])
    }

    static func enter(_ webView: WKWebView) {
        run(webView, """
        const e = document.activeElement;
        if (!e) return;
        const o = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
        const ok = e.dispatchEvent(new KeyboardEvent('keydown', o));
        e.dispatchEvent(new KeyboardEvent('keypress', o));
        e.dispatchEvent(new KeyboardEvent('keyup', o));
        if (!ok) return;
        if (e.isContentEditable) { document.execCommand('insertLineBreak'); return; }
        if (e.tagName === 'TEXTAREA') {
          try { e.setRangeText('\\n', e.selectionStart, e.selectionEnd, 'end'); } catch (_) {}
          e.dispatchEvent(new InputEvent('input', { bubbles: true }));
          return;
        }
        if (e.form) { e.form.requestSubmit ? e.form.requestSubmit() : e.form.submit(); }
        """, [:])
    }

    /// Special keys from a hardware keyboard: arrows, Tab, Esc, Page Up/Down, Home/End, Delete.
    static func key(_ webView: WKWebView, key: String, keyCode: Int, shift: Bool) {
        run(webView, """
        const e = document.activeElement || document.body;
        const o = { key: k, code: k, keyCode: kc, which: kc, shiftKey: shift, bubbles: true, cancelable: true };
        const ok = e.dispatchEvent(new KeyboardEvent('keydown', o));
        e.dispatchEvent(new KeyboardEvent('keyup', o));
        if (!ok) return;
        const field = 'value' in e && typeof e.selectionStart === 'number';
        if (k === 'Tab') {
          const list = [...document.querySelectorAll('a[href],button,input,select,textarea,[tabindex]:not([tabindex="-1"]),[contenteditable="true"]')]
            .filter(x => !x.disabled && x.offsetParent !== null);
          if (!list.length) return;
          const i = list.indexOf(e);
          list[(i + (shift ? -1 : 1) + list.length) % list.length].focus();
          return;
        }
        if (k === 'Escape') { if (e.blur) e.blur(); return; }
        if (field && (k === 'ArrowLeft' || k === 'ArrowRight' || k === 'Home' || k === 'End')) {
          try {
            let p = k === 'ArrowLeft' ? e.selectionStart - 1 : k === 'ArrowRight' ? e.selectionEnd + 1 : k === 'Home' ? 0 : e.value.length;
            p = Math.max(0, Math.min(e.value.length, p));
            e.setSelectionRange(p, p);
          } catch (_) {}
          return;
        }
        if (field && k === 'Delete') {
          try {
            let a = e.selectionStart, b = e.selectionEnd;
            if (a === b) b += 1;
            e.setRangeText('', a, b, 'end');
            e.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'deleteContentForward' }));
          } catch (_) {}
          return;
        }
        if (e.isContentEditable) {
          const dir = { ArrowLeft: 'backward', ArrowRight: 'forward', ArrowUp: 'backward', ArrowDown: 'forward' }[k];
          const s = getSelection();
          if (dir && s && s.modify) s.modify('move', dir, (k === 'ArrowUp' || k === 'ArrowDown') ? 'line' : 'character');
          if (k === 'Delete') document.execCommand('forwardDelete');
          return;
        }
        if (field) return;
        const h = innerHeight * 0.9;
        const d = { ArrowUp: [0, -60], ArrowDown: [0, 60], ArrowLeft: [-60, 0], ArrowRight: [60, 0], PageUp: [0, -h], PageDown: [0, h] }[k];
        if (d) window.scrollBy(d[0], d[1]);
        if (k === 'Home') window.scrollTo(0, 0);
        if (k === 'End') window.scrollTo(0, document.documentElement.scrollHeight);
        """, ["k": key, "kc": keyCode, "shift": shift])
    }

    static func selectAll(_ webView: WKWebView) {
        run(webView, """
        const e = document.activeElement;
        if (e && typeof e.select === 'function') e.select(); else document.execCommand('selectAll');
        """, [:])
    }

    /// Gets the selected text (for Cmd/Ctrl+C).
    static func selectedText(_ webView: WKWebView, completion: @escaping (String?) -> Void) {
        webView.callAsyncJavaScript("""
        const e = document.activeElement;
        if (e && 'value' in e && typeof e.selectionStart === 'number') return e.value.substring(e.selectionStart, e.selectionEnd);
        return String(getSelection() || '');
        """, arguments: [:], in: nil, in: .page) { result in
            if case let .success(v) = result, let s = v as? String, !s.isEmpty { completion(s) } else { completion(nil) }
        }
    }
}

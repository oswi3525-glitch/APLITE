import Foundation
import WebKit

/// The text editor: a text file of Files in its own window ("idesk://editor/<path in Files>"), typed into like any
/// page and saved by itself a moment after each change.
enum TextEditor {
    /// Bigger files open as a page instead (a text area this big is slow to type in).
    static let maxSize = 1_000_000

    static func url(for path: String) -> URL {
        var c = URLComponents()
        c.scheme = "idesk"
        c.host = DesktopPage.editor.rawValue
        c.path = "/" + path
        return c.url ?? DesktopPage.editor.url
    }

    /// The path in Files of the file an editor window shows.
    static func path(of url: URL) -> String? {
        guard url.scheme == "idesk", url.host == DesktopPage.editor.rawValue else { return nil }
        let p = String(url.path.dropFirst())
        return p.isEmpty ? nil : p
    }

    /// A text file small enough to edit.
    static func canEdit(_ file: URL) -> Bool {
        guard QuickLook.kind(of: file) == .text else { return false }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size <= maxSize
    }

    static func save(_ text: String, to url: URL) {
        guard let path = path(of: url), let file = FileStore.resolve(path) else { return }
        do {
            try Data(text.utf8).write(to: file, options: .atomic)
        } catch {
            DesktopModel.shared.showToast(String(localized: "Could not save \(file.lastPathComponent)."))
        }
    }

    /// Save as…: a copy under a new name in the same folder; the window then edits the copy.
    static func saveAs(_ text: String, name: String, from url: URL, in webView: WKWebView) {
        let m = DesktopModel.shared
        guard var name = FileStore.cleanName(name) else { return }
        if (name as NSString).pathExtension.isEmpty { name += ".txt" }
        let folder = path(of: url).flatMap(FileStore.resolve)?.deletingLastPathComponent() ?? FileStore.downloads
        let file = folder.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: file.path) else {
            m.showToast(String(localized: "“\(name)” already exists here.")); return
        }
        guard (try? Data(text.utf8).write(to: file, options: .atomic)) != nil, let newPath = FileStore.relativePath(of: file) else {
            m.showToast(String(localized: "Could not save \(name).")); return
        }
        DesktopPage.editor.load(in: webView, address: Self.url(for: newPath))
        m.refreshFilesPages()
        m.showToast(String(localized: "Saved as \(name)."))
    }

    static func html(for url: URL) -> String {
        let file = path(of: url).flatMap(FileStore.resolve)
        let text = file.flatMap { try? Data(contentsOf: $0) }.map { String(decoding: $0, as: UTF8.self) }
        let strings: [String: Any] = [
            "text": text ?? "",
            "missing": text == nil,
            "name": file?.lastPathComponent ?? "",
            "saved": String(localized: "Saved"), "editing": String(localized: "Editing…"),
            "save": String(localized: "Save"), "gone": String(localized: "This file is no longer in Files."),
            "words": String(localized: "words"), "lines": String(localized: "lines"),
            "find": String(localized: "Find"), "replaceWith": String(localized: "Replace with"),
            "replace": String(localized: "Replace"), "replaceAll": String(localized: "Replace all"),
            "notFound": String(localized: "Not found"), "of": String(localized: "of"),
            "saveAs": String(localized: "Save as…"), "newName": String(localized: "New file name"),
            "cancel": String(localized: "Cancel"), "replaced": String(localized: "replaced"),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: strings)) ?? Data("{}".utf8)
        let title = (file?.lastPathComponent ?? "")
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <title>\(title)</title>
        <style>\(css)</style><script>const T = \(String(decoding: data, as: UTF8.self)); const BRIDGE = '\(DesktopPages.messageName)';</script>
        </head><body>
        <div class="bar"><span id="name"></span><span class="grow"></span><span id="count"></span><span id="status"></span>
        <button id="bFind" onclick="ideskFind()"></button><button id="bSaveAs" onclick="openSaveAs()"></button>
        <button id="bSave" class="primary" onclick="save()"></button></div>
        <div class="bar sub" id="findbar" hidden>
          <input id="fq"><input id="fr"><span id="fc"></span>
          <button onclick="ideskFindNext(-1)">↑</button><button onclick="ideskFindNext(1)">↓</button>
          <button id="bRep" onclick="replaceOne()"></button><button id="bRepAll" onclick="replaceAll()"></button>
          <span class="grow"></span><button onclick="closeFind()">×</button></div>
        <div class="bar sub" id="saveas" hidden>
          <input id="sn" style="width:280px"><button id="bSaveAs2" class="primary" onclick="commitSaveAs()"></button>
          <button id="bCancel" onclick="closeSaveAs()"></button></div>
        <div class="wrap"><div id="hl"></div><textarea id="t" spellcheck="false"></textarea></div>
        <script>\(script)</script>
        </body></html>
        """
    }

    private static let css = #"""
    :root { color-scheme: dark; }
    /* No text autosizing: it would enlarge the marks' layer and not the text area, and they must match exactly. */
    html { -webkit-text-size-adjust: 100%; text-size-adjust: 100%; }
    html, body { margin: 0; height: 100%; background: #1b1b1e; color: #eee; font: 14px -apple-system, sans-serif; }
    body { display: flex; flex-direction: column; }
    .bar { display: flex; align-items: center; gap: 10px; padding: 8px 14px; background: #232327; border-bottom: 1px solid #2f2f34; }
    .bar.sub { background: #1f1f23; padding: 6px 14px; flex-wrap: wrap; row-gap: 6px; }
    .bar[hidden] { display: none; }
    .grow { flex: 1; }
    #name { font-weight: 600; }
    #count, #status, #fc { color: #8a8a90; font-size: 12px; }
    #fc { min-width: 70px; }
    button { background: #34343a; color: #eee; border: 0; border-radius: 7px; padding: 6px 11px; font: inherit; font-size: 13px;
             white-space: nowrap; }
    button:hover { background: #45454c; }
    button.primary { background: #0a84ff; color: #fff; }
    input { background: #2c2c30; color: #eee; border: 1px solid #3a3a40; border-radius: 7px; padding: 6px 10px; font: inherit;
            font-size: 13px; width: 150px; outline: none; }
    input:focus { border-color: #0a84ff; }
    .wrap { flex: 1; position: relative; background: #1b1b1e; }
    #hl, textarea { position: absolute; inset: 0; margin: 0; box-sizing: border-box; padding: 16px 18px; overflow: auto;
                    font: 15px/1.55 ui-monospace, Menlo, monospace; tab-size: 4; white-space: pre-wrap; overflow-wrap: break-word;
                    word-break: normal; }
    #hl { color: transparent; pointer-events: none; }
    #hl mark { color: transparent; background: rgba(255, 214, 10, .38); border-radius: 2px; }
    #hl mark.now { background: rgba(255, 159, 10, .85); }
    textarea { width: 100%; height: 100%; resize: none; border: 0; outline: none; background: transparent; color: #eee; }
    """#

    private static let script = #"""
    const $ = id => document.getElementById(id);
    const t = $('t'), hl = $('hl'), status = $('status'), fq = $('fq'), fr = $('fr');
    $('name').textContent = T.name;
    $('bSave').textContent = T.save; $('bSaveAs').textContent = T.saveAs; $('bFind').textContent = T.find;
    $('bRep').textContent = T.replace; $('bRepAll').textContent = T.replaceAll;
    $('bSaveAs2').textContent = T.save; $('bCancel').textContent = T.cancel;
    fq.placeholder = T.find; fr.placeholder = T.replaceWith; $('sn').placeholder = T.newName;
    t.value = T.text;
    if (T.missing) { t.value = ''; t.disabled = true; status.textContent = T.gone; }
    let timer = null, last = t.value;
    function count() {
      const words = (t.value.match(/\S+/g) || []).length, lines = t.value ? t.value.split('\n').length : 0;
      $('count').textContent = `${lines} ${T.lines} · ${words} ${T.words}`;
    }
    function save() {
      clearTimeout(timer); timer = null;
      if (T.missing) return;
      last = t.value;
      window.webkit.messageHandlers[BRIDGE].postMessage({ action: 'save', value: t.value });
      status.textContent = T.saved;
    }
    function changed() {
      count();
      if (!$('findbar').hidden) mark();
      if (t.value === last) return;
      status.textContent = T.editing;
      clearTimeout(timer);
      timer = setTimeout(save, 800);
    }
    t.addEventListener('input', changed);
    t.addEventListener('scroll', () => { hl.scrollTop = t.scrollTop; hl.scrollLeft = t.scrollLeft; });
    // Tab inserts a tab instead of leaving the text.
    t.addEventListener('keydown', e => {
      if (e.key !== 'Tab') return;
      e.preventDefault();
      t.setRangeText('\t', t.selectionStart, t.selectionEnd, 'end');
      t.dispatchEvent(new Event('input'));
    });

    // Find and replace. The matches are drawn on a layer behind the (transparent) text area, since a text area
    // can't mark its own text and its selection only shows while the page has the focus.
    let matches = [], current = -1;
    function esc(s) { return s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c])); }
    function mark() {
      const q = fq.value, text = t.value;
      matches = [];
      if (q) {
        const lower = text.toLowerCase(), lq = q.toLowerCase();
        for (let i = lower.indexOf(lq); i >= 0 && matches.length < 5000; i = lower.indexOf(lq, i + Math.max(1, lq.length))) matches.push(i);
      }
      if (current >= matches.length) current = matches.length - 1;
      if (current < 0 && matches.length) current = 0;
      let h = '', at = 0;
      matches.forEach((m, k) => {
        h += esc(text.slice(at, m)) + `<mark class="${k === current ? 'now' : ''}">${esc(text.slice(m, m + q.length))}</mark>`;
        at = m + q.length;
      });
      hl.innerHTML = h + esc(text.slice(at)) + '\n ';
      hl.scrollTop = t.scrollTop;
      $('fc').textContent = !q ? '' : matches.length ? `${current + 1} ${T.of} ${matches.length}` : T.notFound;
    }
    function show() {
      const m = hl.querySelector('mark.now');
      if (!m) return;
      const top = m.offsetTop - t.clientHeight / 3;
      // Scrolls only: selecting in the text area would move the caret out of the find field being typed in.
      t.scrollTop = Math.max(0, top); hl.scrollTop = t.scrollTop;
    }
    window.ideskFind = () => {
      $('saveas').hidden = true;
      $('findbar').hidden = false;
      const sel = t.value.slice(t.selectionStart, t.selectionEnd);
      if (sel && !sel.includes('\n')) fq.value = sel;
      fq.focus(); fq.select();
      current = -1; mark(); show();
    };
    window.ideskFindNext = d => {
      if ($('findbar').hidden) { ideskFind(); return; }
      if (!matches.length) return;
      current = (current + d + matches.length) % matches.length;
      mark(); show();
    };
    function closeFind() {
      const at = current >= 0 ? matches[current] : -1, n = fq.value.length;
      $('findbar').hidden = true; matches = []; hl.innerHTML = ''; t.focus();
      if (at >= 0) t.setSelectionRange(at, at + n);      // the editor continues from the match
    }
    function replaceOne() {
      if (!matches.length || current < 0) return;
      const at = matches[current];
      t.setRangeText(fr.value, at, at + fq.value.length, 'end');
      changed(); show();
    }
    function replaceAll() {
      if (!matches.length) return;
      const n = matches.length, q = fq.value;
      const re = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
      t.value = t.value.replace(re, () => fr.value);
      current = -1; changed();
      $('fc').textContent = `${n} ${T.replaced}`;
    }
    fq.addEventListener('input', () => { current = -1; mark(); show(); });
    fq.addEventListener('keydown', e => {
      if (e.key === 'Enter') { e.preventDefault(); ideskFindNext(e.shiftKey ? -1 : 1); }
      if (e.key === 'Escape') closeFind();
    });
    fr.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); replaceOne(); } });

    // Save as…: a name, in the same folder.
    function openSaveAs() {
      if (T.missing) return;
      $('findbar').hidden = true; hl.innerHTML = '';
      $('saveas').hidden = false;
      const sn = $('sn'); sn.value = T.name; sn.focus();
      const dot = sn.value.lastIndexOf('.'); sn.setSelectionRange(0, dot > 0 ? dot : sn.value.length);
    }
    function closeSaveAs() { $('saveas').hidden = true; t.focus(); }
    function commitSaveAs() {
      const name = $('sn').value.trim();
      if (!name) return;
      clearTimeout(timer); timer = null;
      if (t.value !== last) save();
      window.webkit.messageHandlers[BRIDGE].postMessage({ action: 'saveAs', value: t.value, name: name });
    }
    $('sn').addEventListener('keydown', e => {
      if (e.key === 'Enter') { e.preventDefault(); commitSaveAs(); }
      if (e.key === 'Escape') closeSaveAs();
    });

    window.addEventListener('pagehide', () => { if (timer) save(); });
    count();
    if (!T.missing) { status.textContent = T.saved; t.focus(); t.setSelectionRange(0, 0); }
    """#
}

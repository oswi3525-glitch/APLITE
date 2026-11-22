import UIKit
import WebKit

/// Downloads and screenshots, kept in Documents/Downloads and listed by the Files page ("idesk://files"),
/// which is an ordinary web window showing a page iDesk writes, so clicking, scrolling and typing work as in any page.
enum FileStore {
    static let filesURL = URL(string: "idesk://files")!
    private static let pageName = ".APLite-files.html"

    /// A file in Files saved with an older path: the app's data folder gets a new name when iDesk is reinstalled or
    /// updated, so a file URL kept with the session points to the same file under the current Downloads folder.
    static func current(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        let path = url.standardizedFileURL.path, marker = "/Documents/Downloads/"
        guard let range = path.range(of: marker), !FileManager.default.fileExists(atPath: path) else { return url }
        return downloads.appendingPathComponent(String(path[range.upperBound...]))
    }

    static var downloads: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// "idesk://files", or the page iDesk writes for it. A file opened from Files (a downloaded web page) is not:
    /// it must not get the Files buttons (delete, share).
    static func isFilesPage(_ url: URL) -> Bool {
        if url.scheme == filesURL.scheme { return url.host == filesURL.host }
        guard url.isFileURL else { return false }
        return url.standardizedFileURL.path == downloads.appendingPathComponent(pageName).standardizedFileURL.path
    }

    /// A name that is not taken yet: "file.pdf", "file 2.pdf", …
    static func uniqueURL(in folder: URL, name: String) -> URL {
        let clean = name.replacingOccurrences(of: "/", with: "-")
        let base = (clean as NSString).deletingPathExtension, ext = (clean as NSString).pathExtension
        var url = folder.appendingPathComponent(clean.isEmpty ? "download" : clean)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    // MARK: Paths

    /// A path inside Files ("Photos/trip.jpg"), as a file URL, if it stays inside Downloads.
    static func resolve(_ relative: String) -> URL? {
        let parts = relative.split(separator: "/").map(String.init)
        guard !parts.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        let url = parts.reduce(downloads) { $0.appendingPathComponent($1) }.standardizedFileURL
        let root = downloads.standardizedFileURL.path
        return url.path == root || url.path.hasPrefix(root + "/") ? url : nil
    }

    /// The path of a file inside Files ("Photos/trip.jpg"), or nil when it is not in Files.
    static func relativePath(of url: URL) -> String? {
        let root = downloads.standardizedFileURL.path, path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        return String(path.dropFirst(root.count + 1))
    }

    static func isFolder(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    struct Item {
        let url: URL
        let size: Int
        let date: Date
        let isFolder: Bool
    }

    /// What is in a folder of Files (not the hidden page file), newest first.
    static func items(in folder: String = "") -> [Item] {
        guard let dir = resolve(folder) else { return [] }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            return Item(url: url, size: v?.fileSize ?? 0, date: v?.contentModificationDate ?? .distantPast,
                        isFolder: v?.isDirectory == true)
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: Changes

    /// Files from the iPhone's Files app, a USB drive or iCloud Drive: picked on the iPhone (iOS only shows its file
    /// picker there), then copied into the folder shown.
    static func importFromPhone(into folder: String = "") {
        let model = DesktopModel.shared
        let target = resolve(folder) ?? downloads
        model.showToast(String(localized: "Choose the files on the iPhone."))
        DocumentPicker.present { urls in
            var count = 0
            for source in urls {
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                let url = uniqueURL(in: target, name: source.lastPathComponent)
                if (try? FileManager.default.moveItem(at: source, to: url)) != nil
                    || (try? FileManager.default.copyItem(at: source, to: url)) != nil { count += 1 }
            }
            model.refreshFilesPages()
            model.showToast(count == urls.count
                            ? String(localized: "Imported \(count) files into Files.")
                            : String(localized: "Imported \(count) of \(urls.count) files; the others could not be read."))
        }
    }

    /// A name a user typed for a file or folder: no slashes, not empty, not hidden.
    static func cleanName(_ name: String) -> String? {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !t.isEmpty, !t.hasPrefix("."), t.count <= 200 else { return nil }
        return t
    }

    /// Paths cut with "Cut", moved by "Paste here".
    static var clipboard: [String] = []

    // MARK: The page

    /// Writes the Files page (the same for every folder: iDesk sends what to show) and returns its address.
    static func writeFilesPage() -> URL {
        let page = downloads.appendingPathComponent(pageName)
        try? html().write(to: page, atomically: true, encoding: .utf8)
        return page
    }

    private static let sizeFormatter = ByteCountFormatter()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// What a Files window shows: its folder's items, what was cut, downloads in progress (JSON for render()).
    static func state(folder: String) -> String {
        let items: [[String: Any]] = items(in: folder).map { item in
            let path = folder.isEmpty ? item.url.lastPathComponent : folder + "/" + item.url.lastPathComponent
            return [
                "name": item.url.lastPathComponent, "path": path, "dir": item.isFolder,
                "bytes": item.size, "date": item.date.timeIntervalSince1970 * 1000,
                "meta": item.isFolder ? dateFormatter.string(from: item.date)
                    : sizeFormatter.string(fromByteCount: Int64(item.size)) + " · " + dateFormatter.string(from: item.date),
                "icon": item.isFolder ? "📁" : symbol(for: item.url.pathExtension),
                "ipa": item.url.pathExtension.lowercased() == "ipa",
                "zip": item.url.pathExtension.lowercased() == "zip",
                "origin": Trash.isInside(folder) ? (Trash.origin(of: item.url.lastPathComponent) ?? "") : "",
            ]
        }
        let state: [String: Any] = [
            "folder": folder, "items": items, "cut": clipboard.count,
            "trash": Trash.isInside(folder), "trashCount": Trash.count,
            "downloads": Downloads.shared.active.map { ["name": $0.name, "percent": $0.percent] },
        ]
        let data = (try? JSONSerialization.data(withJSONObject: state)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// The SF Symbol of a file's desktop shortcut.
    static func iconSymbol(for ext: String) -> String {
        switch QuickLook.kind(of: URL(fileURLWithPath: "f." + ext)) {
        case .image: return "photo.fill"
        case .pdf: return "doc.richtext.fill"
        case .media: return ["mp3", "m4a", "wav", "aac", "aiff", "caf"].contains(ext.lowercased()) ? "music.note" : "film.fill"
        case .text: return "doc.text.fill"
        case .other: return ext.lowercased() == "ipa" ? "shippingbox.fill" : ext.lowercased() == "zip" ? "doc.zipper" : "doc.fill"
        }
    }

    private static func symbol(for ext: String) -> String {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "🖼️"
        case "mp4", "mov", "m4v", "webm": return "🎬"
        case "mp3", "m4a", "wav", "aac", "flac": return "🎵"
        case "pdf": return "📕"
        case "zip", "rar", "7z", "gz": return "🗜️"
        case "ipa": return "📦"
        case "txt", "md", "csv", "json": return "📝"
        default: return "📄"
        }
    }

    private static func html() -> String {
        let strings: [String: String] = [
            "title": String(localized: "Files"),
            "sub": String(localized: "Double-click to open. Select a file and press Space for a quick look, or drag it to the desktop."),
            "import": String(localized: "Import…"), "newFolder": String(localized: "New folder"),
            "newFile": String(localized: "New text file"), "fileName": String(localized: "File name"),
            "untitled": String(localized: "Untitled.txt"), "extract": String(localized: "Extract"),
            "search": String(localized: "Search in this folder"), "up": String(localized: "Up"),
            "sortName": String(localized: "Name"), "sortDate": String(localized: "Date"), "sortSize": String(localized: "Size"),
            "install": String(localized: "Install"), "share": String(localized: "Save to iPhone…"),
            "rename": String(localized: "Rename"), "delete": String(localized: "Delete"),
            "confirm": String(localized: "Click again to delete"),
            "cut": String(localized: "Cut"), "paste": String(localized: "Paste here"),
            "selected": String(localized: "selected"), "selectAll": String(localized: "Select all"),
            "clear": String(localized: "Clear"),
            "empty": String(localized: "Nothing here yet. Files you download and screenshots appear here; Import… adds files from the iPhone."),
            "noMatch": String(localized: "No files match."),
            "folderName": String(localized: "Folder name"), "downloading": String(localized: "Downloading"),
            "trash": String(localized: "Trash"), "emptyTrash": String(localized: "Empty Trash"),
            "restore": String(localized: "Put back"), "deleteForever": String(localized: "Delete for good"),
            "trashEmpty": String(localized: "The Trash is empty."), "from": String(localized: "From"),
            "compress": String(localized: "Compress"), "inContents": String(localized: "Found inside files"),
            "trashSub": String(localized: "Deleted files stay here until you empty the Trash. Put back returns them where they were."),
        ]
        let t = String(decoding: (try? JSONSerialization.data(withJSONObject: strings)) ?? Data("{}".utf8), as: UTF8.self)
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <title>\(escape(strings["title"] ?? ""))</title>
        <style>\(css)</style>
        <script>const T = \(t); const BRIDGE = '\(FilesBridge.messageName)';</script>
        <script>\(script)</script>
        </head><body><div id="root"></div></body></html>
        """
    }

    private static let css = #"""
    :root { color-scheme: dark; }
    * { box-sizing: border-box; }
    body { margin: 0; padding: 24px 30px 40px; background: #161618; color: #eee; font: 15px -apple-system, sans-serif; }
    h1 { font-size: 24px; margin: 0; }
    .sub { color: #999; margin: 4px 0 14px; font-size: 13px; }
    .head { display: flex; align-items: flex-end; gap: 10px; }
    .grow { flex: 1; min-width: 0; }
    .bar { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; flex-wrap: wrap; }
    .crumbs { display: flex; align-items: center; gap: 4px; font-size: 14px; min-width: 0; flex-wrap: wrap; }
    .crumbs a { color: #8ab4ff; cursor: default; text-decoration: none; padding: 3px 5px; border-radius: 5px; }
    .crumbs a:hover { background: #2c2c30; }
    .crumbs span { color: #666; }
    input { background: #26262a; color: #eee; border: 1px solid #3a3a40; border-radius: 7px; padding: 7px 10px; font: inherit; font-size: 13px; }
    input:focus { outline: none; border-color: #0a84ff; }
    #q { width: 220px; }
    button { background: #2c2c30; color: #eee; border: 0; border-radius: 7px; padding: 7px 11px; font: inherit; font-size: 13px; white-space: nowrap; }
    button:hover { background: #3a3a40; }
    button.on { background: #0a84ff; color: #fff; }
    button.primary { background: #0a84ff; color: #fff; } button.primary:hover { background: #3797ff; }
    .danger { color: #ff8a80; }
    .seg { display: inline-flex; gap: 2px; background: #222226; border-radius: 8px; padding: 2px; }
    .seg button { padding: 5px 9px; }
    table { width: 100%; border-collapse: collapse; }
    tr { border-top: 1px solid #2a2a2e; }
    td { padding: 8px 6px; vertical-align: middle; }
    tr.sel td { background: rgba(10, 132, 255, 0.28); }
    tr.sel td:first-child { border-radius: 8px 0 0 8px; } tr.sel td:last-child { border-radius: 0 8px 8px 0; }
    tr.cut { opacity: 0.45; }
    .check { width: 30px; text-align: center; }
    .box { display: inline-block; width: 18px; height: 18px; border: 1.5px solid #666; border-radius: 5px; vertical-align: middle; }
    .box.on { background: #0a84ff; border-color: #0a84ff; position: relative; }
    .box.on::after { content: ''; position: absolute; left: 5px; top: 1px; width: 5px; height: 10px; border: solid #fff; border-width: 0 2px 2px 0; transform: rotate(45deg); }
    .icon { font-size: 24px; width: 40px; text-align: center; }
    .name { color: #8ab4ff; font-weight: 500; word-break: break-all; }
    .name.dir { color: #eee; }
    .meta { color: #888; font-size: 12px; margin-top: 3px; }
    .actions { text-align: right; white-space: nowrap; }
    .actions button { margin-left: 6px; }
    .empty { color: #999; margin-top: 40px; text-align: center; }
    h3.found { font-size: 14px; color: #aaa; margin: 22px 0 6px; font-weight: 600; }
    .selbar { display: flex; align-items: center; gap: 8px; background: #1f2a3a; border-radius: 9px; padding: 7px 10px; margin-bottom: 10px; }
    .dl { background: #222226; border-radius: 9px; padding: 8px 12px; margin-bottom: 10px; font-size: 13px; }
    .dl .track { height: 4px; background: #333; border-radius: 2px; margin-top: 6px; overflow: hidden; }
    .dl .fill { height: 100%; background: #0a84ff; }
    """#

    private static let script = #"""
    let S = { folder: '', items: [], cut: 0, downloads: [] };
    let sort = 'date', query = '', checked = new Set(), selected = null, editing = null, armed = null;
    try { sort = localStorage.getItem('sort') || 'date'; } catch (_) {}
    function post(action, extra) { window.webkit.messageHandlers[BRIDGE].postMessage(Object.assign({ action: action }, extra || {})); }
    function esc(s) { return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
    function render(state) {
      if (state.folder !== S.folder) { checked.clear(); selected = null; query = ''; }
      S = state;
      for (const p of Array.from(checked)) if (!S.items.some(i => i.path === p)) checked.delete(p);
      draw();
    }
    function visible() {
      const q = query.trim().toLowerCase();
      let list = S.items.filter(i => !q || i.name.toLowerCase().includes(q));
      const cmp = { name: (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: 'base' }),
                    date: (a, b) => b.date - a.date, size: (a, b) => b.bytes - a.bytes }[sort];
      list.sort((a, b) => (a.dir !== b.dir) ? (a.dir ? -1 : 1) : cmp(a, b));
      return list;
    }
    function draw() {
      const root = document.getElementById('root');
      const keepQ = document.activeElement && document.activeElement.id === 'q';
      let h = S.trash
        ? `<div class="head"><div class="grow"><h1>🗑️ ${esc(T.trash)}</h1><div class="sub">${esc(T.trashSub)}</div></div>
           <button onclick="go('')">← ${esc(T.title)}</button>
           <button class="danger" onclick="del(this, null)">${esc(T.emptyTrash)}</button></div>`
        : `<div class="head"><div class="grow"><h1>${esc(T.title)}</h1><div class="sub">${esc(T.sub)}</div></div>
        <button onclick="go('.Trash')">🗑️ ${esc(T.trash)}${S.trashCount ? ' (' + S.trashCount + ')' : ''}</button>
        <button onclick="startNew('file')">${esc(T.newFile)}</button>
        <button onclick="startNew('folder')">${esc(T.newFolder)}</button>
        <button class="primary" onclick="post('import')">${esc(T.import)}</button></div>`;
      // Breadcrumbs, search, sort.
      const parts = S.folder && !S.trash ? S.folder.split('/') : [];
      h += `<div class="bar"><div class="crumbs grow">`;
      if (parts.length) h += `<button onclick="go('${jsq(parts.slice(0, -1).join('/'))}')">↑ ${esc(T.up)}</button>`;
      h += `<a onclick="go('')">${esc(T.title)}</a>`;
      parts.forEach((p, i) => { h += `<span>›</span><a onclick="go('${jsq(parts.slice(0, i + 1).join('/'))}')">${esc(p)}</a>`; });
      h += `</div><input id="q" placeholder="${esc(T.search)}" value="${esc(query)}" oninput="query = this.value; drawList(); askContents()">
        <div class="seg">` + ['name', 'date', 'size'].map(k =>
          `<button class="${sort === k ? 'on' : ''}" onclick="setSort('${k}')">${esc(T['sort' + k[0].toUpperCase() + k.slice(1)])}</button>`).join('') +
        `</div></div>`;
      S.downloads.forEach(d => {
        h += `<div class="dl">${esc(T.downloading)} ${esc(d.name)} — ${d.percent}%<div class="track"><div class="fill" style="width:${d.percent}%"></div></div></div>`;
      });
      h += `<div id="selbar"></div><div id="list"></div>`;
      root.innerHTML = h;
      drawList();
      if (keepQ) { const q = document.getElementById('q'); q.focus(); q.setSelectionRange(q.value.length, q.value.length); }
    }
    function drawList() {
      const list = visible();
      let b = '';
      if (checked.size || S.cut) {
        b = `<div class="selbar">`;
        if (checked.size) {
          b += `<span class="grow">${checked.size} ${esc(T.selected)}</span>` + (S.trash
            ? `<button onclick="post('restore', { paths: [...checked] }); checked.clear()">${esc(T.restore)}</button>
               <button class="danger" onclick="del(this, [...checked])">${esc(T.deleteForever)}</button>`
            : `<button onclick="post('cut', { paths: [...checked] }); checked.clear()">${esc(T.cut)}</button>
               <button onclick="post('zip', { paths: [...checked], folder: S.folder }); checked.clear()">${esc(T.compress)}</button>
               <button onclick="post('share', { paths: [...checked] })">${esc(T.share)}</button>
               <button class="danger" onclick="del(this, [...checked])">${esc(T.delete)}</button>`)
            + `<button onclick="checked.clear(); drawList()">${esc(T.clear)}</button>`;
        } else {
          b += `<span class="grow"></span>`;
        }
        if (S.cut) b += `<button class="primary" onclick="post('paste', { folder: S.folder })">${esc(T.paste)} (${S.cut})</button>`;
        b += `</div>`;
      }
      document.getElementById('selbar').innerHTML = b;
      let r = '';
      if (editing && editing.kind === 'new') {
        r += editing.type === 'file'
          ? `<tr><td class="check"></td><td class="icon">📝</td><td colspan="2"><input id="edit" placeholder="${esc(T.fileName)}" value="${esc(T.untitled)}"></td></tr>`
          : `<tr><td class="check"></td><td class="icon">📁</td><td colspan="2"><input id="edit" placeholder="${esc(T.folderName)}"></td></tr>`;
      }
      list.forEach(i => {
        const on = checked.has(i.path), sel = selected === i.path;
        const nameCell = editing && editing.kind === 'rename' && editing.path === i.path
          ? `<input id="edit" value="${esc(i.name)}">`
          : `<div class="name ${i.dir ? 'dir' : ''}">${esc(i.name)}</div><div class="meta">${esc(i.meta)}${i.origin ? ' · ' + esc(T.from) + ' ' + esc(i.origin) : ''}</div>`;
        if (S.trash) {
          r += `<tr data-path="${esc(i.path)}" class="${sel ? 'sel' : ''}">
            <td class="check" onclick="toggle(event, '${jsq(i.path)}')"><span class="box ${on ? 'on' : ''}"></span></td>
            <td class="icon">${i.icon}</td><td>${nameCell}</td><td class="actions">
            <button onclick="post('restore', { paths: ['${jsq(i.path)}'] })">${esc(T.restore)}</button>
            <button class="danger" onclick="del(this, ['${jsq(i.path)}'])">${esc(T.deleteForever)}</button></td></tr>`;
          return;
        }
        r += `<tr data-path="${esc(i.path)}" class="${sel ? 'sel' : ''}">
          <td class="check" onclick="toggle(event, '${jsq(i.path)}')"><span class="box ${on ? 'on' : ''}"></span></td>
          <td class="icon">${i.icon}</td><td>${nameCell}</td><td class="actions">` +
          (i.ipa ? `<button onclick="post('install', { path: '${jsq(i.path)}' })">${esc(T.install)}</button>` : '') +
          (i.zip ? `<button onclick="post('unzip', { path: '${jsq(i.path)}' })">${esc(T.extract)}</button>` : '') +
          `<button onclick="startRename('${jsq(i.path)}')">${esc(T.rename)}</button>` +
          (i.dir ? '' : `<button onclick="post('share', { paths: ['${jsq(i.path)}'] })">${esc(T.share)}</button>`) +
          `<button class="danger" onclick="del(this, ['${jsq(i.path)}'])">${esc(T.delete)}</button></td></tr>`;
      });
      let html = r ? `<table>${r}</table>` : '';
      if (!list.length && !(editing && editing.kind === 'new')) html = `<p class="empty">${esc(S.items.length ? T.noMatch : S.trash ? T.trashEmpty : T.empty)}</p>`;
      if (contents.length && query.trim()) {
        html += `<h3 class="found">${esc(T.inContents)}</h3><table>` + contents.map(c =>
          `<tr data-path="${esc(c.path)}"><td class="check"></td><td class="icon">📝</td><td><div class="name">${esc(c.path)}</div>
           <div class="meta">${esc(c.line)}</div></td><td></td></tr>`).join('') + `</table>`;
      }
      document.getElementById('list').innerHTML = html;
      const edit = document.getElementById('edit');
      if (edit) {
        edit.focus();
        const dot = edit.value.lastIndexOf('.');
        edit.setSelectionRange(0, dot > 0 ? dot : edit.value.length);
      }
    }
    function jsq(s) { return esc(String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'")); }
    function go(folder) { editing = null; contents = []; post('go', { folder: folder }); }
    // Searching also looks inside text files everywhere in Files (asked for a moment after typing stops).
    let contents = [], contentsTimer = null;
    function askContents() {
      clearTimeout(contentsTimer);
      contentsTimer = setTimeout(() => { if (query.trim().length >= 2) post('searchContents', { q: query.trim() }); else { contents = []; drawList(); } }, 350);
    }
    window.ideskContents = (q, found) => { if (q === query.trim()) { contents = found; drawList(); } };
    function setSort(k) { sort = k; try { localStorage.setItem('sort', k); } catch (_) {} draw(); }
    function toggle(e, path) { e.stopPropagation(); checked.has(path) ? checked.delete(path) : checked.add(path); drawList(); }
    function del(button, paths) {
      if (armed !== button) {
        armed = button; const text = button.textContent; button.textContent = T.confirm;
        setTimeout(() => { if (armed === button) { armed = null; button.textContent = text; } }, 3000);
        return;
      }
      armed = null;
      if (paths === null) { post('emptyTrash'); return; }
      paths.forEach(p => checked.delete(p)); post('delete', { paths: paths });
    }
    function startNew(type) { editing = { kind: 'new', type: type }; drawList(); }
    function startRename(path) { editing = { kind: 'rename', path: path }; drawList(); }
    function commitEdit() {
      const edit = document.getElementById('edit'); if (!edit || !editing) return;
      const name = edit.value.trim(), e = editing; editing = null;
      if (name) {
        if (e.kind === 'new') post(e.type === 'file' ? 'newFile' : 'newFolder', { folder: S.folder, name: name });
        else post('rename', { path: e.path, name: name });
      }
      drawList();
    }
    function select(path, tell) {
      selected = path;
      document.querySelectorAll('tr.sel').forEach(r => r.classList.remove('sel'));
      const row = Array.from(document.querySelectorAll('tr[data-path]')).find(r => r.dataset.path === path);
      if (row) { row.classList.add('sel'); row.scrollIntoView({ block: 'nearest' }); }
      if (tell && path) post('select', { path: path });
    }
    window.ideskSelect = p => select(p, false);
    window.ideskStep = d => {
      const files = visible().filter(i => !i.dir);
      if (!files.length) return;
      let i = files.findIndex(f => f.path === selected);
      i = Math.max(0, Math.min(files.length - 1, (i < 0 ? 0 : i + d)));
      select(files[i].path, true);
    };
    document.addEventListener('click', e => {
      if (e.target.closest('button, input, .check, .crumbs')) return;
      const row = e.target.closest('tr[data-path]');
      if (editing && !e.target.closest('#edit')) commitEdit();
      select(row ? row.dataset.path : null, !!row);
    });
    document.addEventListener('dblclick', e => {
      const row = e.target.closest('tr[data-path]');
      if (row && !e.target.closest('button, input, .check')) post('open', { path: row.dataset.path });
    });
    document.addEventListener('keydown', e => {
      if (e.target.id === 'edit') {
        if (e.key === 'Enter') { e.preventDefault(); commitEdit(); }
        if (e.key === 'Escape') { editing = null; drawList(); }
        return;
      }
      if (e.target.tagName === 'INPUT') return;
      if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
      const rows = Array.from(document.querySelectorAll('tr[data-path]'));
      if (!rows.length) return;
      let i = rows.findIndex(r => r.dataset.path === selected);
      i = e.key === 'ArrowDown' ? Math.min(rows.length - 1, i + 1) : Math.max(0, i - 1);
      select(rows[i].dataset.path, true);
      e.preventDefault();
    });
    // While a text field has focus, Space types a space instead of opening Quick Look.
    document.addEventListener('focusin', e => { if (e.target.tagName === 'INPUT') post('editing', { on: true }); });
    document.addEventListener('focusout', e => { if (e.target.tagName === 'INPUT') post('editing', { on: false }); });
    """#
}

/// The Files page's buttons and selection. Only the Files page itself may use it: any other page asking is ignored.
final class FilesBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "ideskFiles"
    weak var window: DeskWindow?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let url = message.webView?.url, url.isFileURL, FileStore.isFilesPage(url), let window,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        let model = DesktopModel.shared
        let paths = (body["paths"] as? [String]) ?? []
        let path = body["path"] as? String
        switch action {
        case "import":
            FileStore.importFromPhone(into: window.filesFolder)
        case "go":
            if let folder = body["folder"] as? String {
                if folder == Trash.folder { _ = Trash.url }          // made on first use
                if let dir = FileStore.resolve(folder), FileStore.isFolder(dir) { window.showFolder(folder) }
            }
        case "editing":
            window.filesEditing = body["on"] as? Bool ?? false
        case "select":
            guard let path, FileStore.resolve(path) != nil else { return }
            window.selectedFile = path
            model.quickLookFollowSelection(in: window)
        case "open":
            guard let path, let file = FileStore.resolve(path) else { return }
            if FileStore.isFolder(file) { window.showFolder(path) } else { model.openFile(path) }
        case "share":
            let files = paths.compactMap(FileStore.resolve).filter { !FileStore.isFolder($0) }
            if !files.isEmpty { model.shareOnPhone(files) }
        case "delete":
            // From Files: to the Trash. From the Trash: gone for good.
            if Trash.isInside(window.filesFolder) {
                Trash.deleteForever(paths)
            } else {
                let n = Trash.move(paths)
                if n > 0 { model.showToast(String(localized: "Moved \(n) items to the Trash.")) }
            }
            model.refreshFilesPages()
        case "restore":
            let n = Trash.restore(paths)
            if n > 0 { model.showToast(String(localized: "Put back \(n) items.")) }
            model.refreshFilesPages()
        case "emptyTrash":
            Trash.empty()
            model.refreshFilesPages()
        case "zip":
            model.showToast(String(localized: "Compressing…"))
            Compressor.zip(paths, in: body["folder"] as? String ?? "") { result in
                switch result {
                case .success(let url): model.showToast(String(localized: "Made \(url.lastPathComponent)."))
                case .failure(let e): model.showToast(String(localized: "Could not compress: \(e.localizedDescription)"))
                }
                model.refreshFilesPages()
            }
        case "searchContents":
            guard let q = body["q"] as? String else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak window] in
                let found = ContentSearch.search(q).map { ["path": $0.path, "line": $0.line] }
                let json = String(decoding: (try? JSONSerialization.data(withJSONObject: ["q": q, "found": found])) ?? Data("{}".utf8), as: UTF8.self)
                DispatchQueue.main.async {
                    message.webView?.evaluateJavaScript("(d => window.ideskContents && ideskContents(d.q, d.found))(\(json))")
                    _ = window
                }
            }
        case "install":
            guard let path, let file = FileStore.resolve(path) else { return }
            model.showToast(String(localized: "Installing \(file.lastPathComponent)…"))
            GuestStore.shared.install(ipas: [file]) { results in model.showToast(GuestStore.summary(of: results)) }
        case "newFolder":
            guard let name = (body["name"] as? String).flatMap(FileStore.cleanName),
                  let parent = FileStore.resolve(body["folder"] as? String ?? "") else { return }
            let dir = FileStore.uniqueURL(in: parent, name: name)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            model.refreshFilesPages()
        case "newFile":
            guard var name = (body["name"] as? String).flatMap(FileStore.cleanName),
                  let parent = FileStore.resolve(body["folder"] as? String ?? "") else { return }
            if (name as NSString).pathExtension.isEmpty { name += ".txt" }
            let file = FileStore.uniqueURL(in: parent, name: name)
            guard FileManager.default.createFile(atPath: file.path, contents: Data()),
                  let path = FileStore.relativePath(of: file) else {
                model.showToast(String(localized: "Could not create \(name).")); return
            }
            model.refreshFilesPages()
            model.openFile(path)          // a text file opens in the text editor
        case "unzip":
            guard let path, let file = FileStore.resolve(path) else { return }
            let parent = file.deletingLastPathComponent()
            // Into a hidden folder first; then, when everything is inside one folder already, that folder moves out
            // (no "Name/Name"), otherwise the hidden folder becomes one named after the archive.
            let temp = parent.appendingPathComponent(".APLite-unzip-\(UUID().uuidString)")
            model.showToast(String(localized: "Extracting \(file.lastPathComponent)…"))
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let result = Result { () -> URL in
                    try Unzip.extract(file, to: temp)
                    let items = try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
                        .filter { !$0.lastPathComponent.hasPrefix(".") }
                    if items.count == 1, FileStore.isFolder(items[0]) {
                        let target = FileStore.uniqueURL(in: parent, name: items[0].lastPathComponent)
                        try fm.moveItem(at: items[0], to: target)
                        try? fm.removeItem(at: temp)
                        return target
                    }
                    let target = FileStore.uniqueURL(in: parent, name: file.deletingPathExtension().lastPathComponent)
                    try fm.moveItem(at: temp, to: target)
                    return target
                }
                DispatchQueue.main.async {
                    switch result {
                    case .success(let target):
                        model.showToast(String(localized: "Extracted to the folder “\(target.lastPathComponent)”."))
                    case .failure(let error):
                        try? fm.removeItem(at: temp)
                        model.showToast(String(localized: "Could not extract \(file.lastPathComponent): \(error.localizedDescription)"))
                    }
                    model.refreshFilesPages()
                }
            }
        case "rename":
            guard let path, let file = FileStore.resolve(path), file != FileStore.downloads.standardizedFileURL,
                  let name = (body["name"] as? String).flatMap(FileStore.cleanName), name != file.lastPathComponent else { return }
            let target = file.deletingLastPathComponent().appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path) else {
                model.showToast(String(localized: "“\(name)” already exists here.")); return
            }
            if (try? FileManager.default.moveItem(at: file, to: target)) != nil {
                model.fileMoved(from: path, to: FileStore.relativePath(of: target) ?? name)
            }
            model.refreshFilesPages()
        case "cut":
            FileStore.clipboard = paths.filter { FileStore.resolve($0) != nil }
            model.refreshFilesPages()
        case "paste":
            guard let folder = FileStore.resolve(body["folder"] as? String ?? "") else { return }
            var moved = 0
            var remaining: [String] = []
            for old in FileStore.clipboard {
                guard let file = FileStore.resolve(old), FileManager.default.fileExists(atPath: file.path),
                      file.deletingLastPathComponent() != folder,
                      !(folder.path + "/").hasPrefix(file.path + "/") else { continue }     // not into itself
                let target = FileStore.uniqueURL(in: folder, name: file.lastPathComponent)
                if (try? FileManager.default.moveItem(at: file, to: target)) != nil {
                    moved += 1
                    model.fileMoved(from: old, to: FileStore.relativePath(of: target) ?? target.lastPathComponent)
                } else {
                    remaining.append(old)   // a failed move must not silently lose the cut items
                }
            }
            FileStore.clipboard = remaining
            if moved > 0 { model.showToast(String(localized: "Moved \(moved) items.")) }
            model.refreshFilesPages()
        default:
            break
        }
    }
}

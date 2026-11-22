import UIKit
import Network
import Combine

/// A laptop (or any computer) as the display: iDesk serves the desktop to a browser on the same Wi-Fi.
/// The browser shows it and sends its mouse and keyboard back. No cable and nothing to install: laptops'
/// HDMI and USB-C ports send video out and do not take it in, so a cable from the iPhone shows nothing.
///
/// http://<iPhone>:8080 is the page; the picture (JPEG frames) and the input (JSON) go over a WebSocket on 8081.
/// The desktop itself runs on the iPhone's screen (LaptopModeController), shaped like the browser window.
final class RemoteDisplay: ObservableObject {
    static let shared = RemoteDisplay()
    static let httpPort: UInt16 = 8080, socketPort: UInt16 = 8081

    @Published private(set) var isOn = false
    @Published private(set) var viewers = 0
    @Published private(set) var failure: String?
    /// The desktop's size: the shape of the laptop's browser window (no black bars), 720 to 900 points high.
    @Published private(set) var desktopSize = CGSize(width: 1280, height: 720)
    /// Pixels per point of the frames: the laptop screen's own (2 on a Retina laptop), so the picture is as sharp
    /// as the screen; at most about 4 million pixels a frame, to keep the frame rate.
    private var frameScale: CGFloat = 1

    private var pageListener: NWListener?
    private var socketListener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var link: CADisplayLink?
    private var cursorWatch: AnyCancellable?
    private let queue = DispatchQueue(label: "iDesk.remote-display")

    /// A browser showing the desktop. It acknowledges every frame it has drawn: a frame is sent only while fewer
    /// than two are on their way, so a slow network gets fewer frames instead of a delay that keeps growing.
    private final class Client {
        let connection: NWConnection
        var sent: [CFTimeInterval] = []        // when the frames still on their way were sent
        var roundTrip: CFTimeInterval = 0.05
        init(_ connection: NWConnection) { self.connection = connection }
    }

    /// The address to type in the laptop's browser.
    var address: String? { Self.wifiAddress().map { "http://\($0):\(Self.httpPort)" } }

    // MARK: Start / stop

    func start() {
        guard !isOn else { return }
        failure = nil
        do {
            let page = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.httpPort)!)
            page.newConnectionHandler = { [weak self] c in self?.servePage(c) }
            page.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
            page.start(queue: queue)

            // No Nagle delay: clicks and keys leave at once instead of waiting to be grouped.
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let params = NWParameters(tls: nil, tcp: tcp)
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            let socket = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.socketPort)!)
            socket.newConnectionHandler = { [weak self] c in self?.accept(c) }
            socket.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
            socket.start(queue: queue)

            pageListener = page
            socketListener = socket
        } catch {
            failure = error.localizedDescription
            return
        }
        isOn = true
        let link = CADisplayLink(target: Tick(self), selector: #selector(Tick.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
        // The browser draws the pointer itself (no delay); it takes the desktop's shape: arrow, hand, I-beam…
        cursorWatch = DesktopModel.shared.cursor.$style.removeDuplicates().sink { [weak self] style in
            self?.broadcast(["t": "cursor", "s": Self.css(style)])
        }
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        link?.invalidate()
        link = nil
        cursorWatch = nil
        DesktopModel.shared.cursor.drawnByViewer = false
        pageListener?.cancel()
        socketListener?.cancel()
        pageListener = nil
        socketListener = nil
        queue.async {
            self.clients.values.forEach { $0.connection.cancel() }
            self.clients.removeAll()
            DispatchQueue.main.async { self.viewers = 0 }
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
        guard case .failed(let error) = state else { return }
        DispatchQueue.main.async {
            self.failure = String(localized: "Could not start: \(error.localizedDescription). Allow APLite to use the local network in the iPhone's Settings → Privacy & Security → Local Network.")
        }
    }

    // MARK: The page

    private func servePage(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
            let body = Data(Self.page.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\n"
                + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
            c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    // MARK: Viewers

    private func accept(_ c: NWConnection) {
        let client = Client(c)
        let id = ObjectIdentifier(client)
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.drop(id)
            default: break
            }
        }
        clients[id] = client
        let n = clients.count
        DispatchQueue.main.async {
            self.viewers = n
            DesktopModel.shared.cursor.drawnByViewer = true
            self.send(["t": "cursor", "s": Self.css(DesktopModel.shared.cursor.style)], to: client)
        }
        c.start(queue: queue)
        receive(from: client, id: id)
    }

    private func drop(_ id: ObjectIdentifier) {
        clients[id] = nil
        let n = clients.count
        DispatchQueue.main.async {
            self.viewers = n
            if n == 0 { DesktopModel.shared.cursor.drawnByViewer = false }
        }
    }

    private func receive(from client: Client, id: ObjectIdentifier) {
        client.connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                switch event["t"] as? String {
                case "ack":
                    if !client.sent.isEmpty {
                        let rt = CACurrentMediaTime() - client.sent.removeFirst()
                        client.roundTrip = client.roundTrip * 0.8 + rt * 0.2
                    }
                case "size":
                    let w = event["w"] as? Double ?? 0, h = event["h"] as? Double ?? 0, r = event["r"] as? Double ?? 1
                    DispatchQueue.main.async { self.fit(width: w, height: h, pixelRatio: r) }
                default:
                    DispatchQueue.main.async { RemoteInput.handle(event) }
                }
            }
            if error == nil { self.receive(from: client, id: id) } else { self.drop(id) }
        }
    }

    /// The browser window's shape (CSS pixels): the desktop takes it, so it fills the window.
    private func fit(width: Double, height: Double, pixelRatio: Double) {
        guard width > 200, height > 200 else { return }
        let h = min(900, max(720, height.rounded()))
        let w = min(1920, max(960, (h * width / height / 2).rounded() * 2))
        let size = CGSize(width: w, height: h)
        if size != desktopSize { desktopSize = size }
        // As many pixels as the laptop shows (its window in device pixels), at most 2× and about 4 million.
        let wanted = min(2, max(1, pixelRatio * height / h))
        frameScale = CGFloat(min(wanted, (4_000_000 / (w * h)).squareRoot()))
    }

    private func send(_ object: [String: Any], to client: Client) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let context = NWConnection.ContentContext(identifier: "text", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        client.connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func broadcast(_ object: [String: Any]) {
        queue.async { self.clients.values.forEach { self.send(object, to: $0) } }
    }

    private static func css(_ style: CursorStyle) -> String {
        switch style {
        case .arrow: return "default"
        case .pointer: return "pointer"
        case .text: return "text"
        case .grab: return "grabbing"
        case .resizeH: return "ew-resize"
        case .resizeV: return "ns-resize"
        case .resizeNWSE: return "nwse-resize"
        case .resizeNESW: return "nesw-resize"
        case .crosshair: return "crosshair"
        }
    }

    // MARK: Frames

    private final class Tick: NSObject {
        weak var owner: RemoteDisplay?
        init(_ owner: RemoteDisplay) { self.owner = owner }
        @objc func fire() { owner?.frame() }
    }

    private var encoding = false

    /// One frame for the viewers that can take one now. The picture is drawn on the main thread; the JPEG is made
    /// on the queue, at a quality that drops when the network is slow.
    private func frame() {
        guard viewers > 0, !encoding, let view = ExternalSceneDelegate.desktopView, view.bounds.width > 0 else { return }
        encoding = true
        let size = view.bounds.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = frameScale
        let image = autoreleasepool {
            UIGraphicsImageRenderer(size: size, format: format).image { _ in
                view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false)
            }
        }
        queue.async {
            let waiting = self.clients.values.filter { $0.sent.count < 2 }
            let slowest = waiting.map(\.roundTrip).max() ?? 0.05
            let quality: CGFloat = slowest > 0.25 ? 0.55 : slowest > 0.12 ? 0.68 : 0.8
            if !waiting.isEmpty, let jpeg = image.jpegData(compressionQuality: quality) {
                let context = NWConnection.ContentContext(identifier: "frame",
                                                          metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)])
                let now = CACurrentMediaTime()
                for client in waiting {
                    client.sent.append(now)
                    client.connection.send(content: jpeg, contentContext: context, isComplete: true, completion: .idempotent)
                }
            }
            DispatchQueue.main.async { self.encoding = false }
        }
    }

    // MARK: Wi-Fi address

    /// The iPhone's IPv4 address on Wi-Fi (en0), or on a hotspot/USB connection when there is no Wi-Fi.
    static func wifiAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: [String: String] = [:]
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                found[name] = String(cString: host)
            }
        }
        return found["en0"] ?? found["bridge100"] ?? found.first { $0.key.hasPrefix("en") }?.value
    }

    // MARK: Page

    private static let page = #"""
    <!doctype html><html><head><meta charset="utf-8"><title>APLite</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
    html,body{margin:0;height:100%;background:#000;overflow:hidden;font:15px -apple-system,Segoe UI,sans-serif;color:#ccc}
    canvas{position:fixed;inset:0;width:100vw;height:100vh;outline:none;cursor:default;image-rendering:auto}
    #msg{position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);text-align:center;line-height:1.6}
    #tip{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:#000c;color:#ddd;padding:8px 14px;border-radius:10px;transition:opacity .6s}
    </style></head><body>
    <canvas id="c" width="1280" height="720"></canvas>
    <div id="msg">Đang kết nối với APLite trên iPhone…</div>
    <div id="tip">Bấm vào màn hình để vào toàn màn hình · Esc để thoát</div>
    <textarea id="kb" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false"
      style="position:fixed;left:-1000px;top:0;width:10px;height:10px;opacity:0"></textarea>
    <script>
    const c = document.getElementById('c'), g = c.getContext('2d'), msg = document.getElementById('msg'),
          kb = document.getElementById('kb'), tip = document.getElementById('tip');
    let ws, last = 0, drawing = false, pending = null;
    const send = o => { if (ws && ws.readyState === 1) ws.send(JSON.stringify(o)); };
    // The desktop takes the window's shape: no black bars.
    const tellSize = () => send({t: 'size', w: innerWidth, h: innerHeight, r: devicePixelRatio || 1});
    addEventListener('resize', () => { clearTimeout(window.__rs); window.__rs = setTimeout(tellSize, 250); });
    async function draw(blob) {
      // Only the newest frame is drawn; each drawn frame is acknowledged so APLite never gets ahead of the network.
      if (drawing) { if (pending) send({t: 'ack'}); pending = blob; return; }   // a skipped frame is acknowledged too
      drawing = true;
      try {
        const bmp = await createImageBitmap(blob);
        if (c.width !== bmp.width || c.height !== bmp.height) { c.width = bmp.width; c.height = bmp.height; }
        g.drawImage(bmp, 0, 0); bmp.close && bmp.close();
      } catch (e) {}
      send({t: 'ack'});
      drawing = false;
      if (pending) { const b = pending; pending = null; draw(b); }
    }
    function connect() {
      ws = new WebSocket('ws://' + location.hostname + ':8081');
      ws.binaryType = 'blob';
      ws.onopen = () => { msg.style.display = 'none'; tellSize(); kb.focus(); setTimeout(() => tip.style.opacity = 0, 5000); };
      ws.onclose = () => { msg.style.display = 'block'; msg.textContent = 'Mất kết nối. Mở APLite trên iPhone, đang thử lại…'; setTimeout(connect, 1500); };
      ws.onmessage = e => {
        if (typeof e.data === 'string') { const m = JSON.parse(e.data); if (m.t === 'cursor') c.style.cursor = m.s; return; }
        draw(e.data);
      };
    }
    connect();
    function pos(e) { const r = c.getBoundingClientRect(); return [(e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height]; }
    c.addEventListener('mousemove', e => { const n = performance.now(); if (n - last < 8) return; last = n; const [x, y] = pos(e); send({t: 'm', x, y}); });
    c.addEventListener('mousedown', e => {
      if (!document.fullscreenElement && document.documentElement.requestFullscreen) document.documentElement.requestFullscreen().catch(() => {});
      const [x, y] = pos(e); send({t: 'd', b: e.button, x, y}); e.preventDefault(); kb.focus();
    });
    addEventListener('mouseup', e => { const [x, y] = pos(e); send({t: 'u', b: e.button, x, y}); });
    c.addEventListener('contextmenu', e => e.preventDefault());
    c.addEventListener('wheel', e => { const k = e.deltaMode === 1 ? 16 : 1; send({t: 'w', dx: e.deltaX * k, dy: e.deltaY * k}); e.preventDefault(); }, {passive: false});
    // Keys go through a hidden text field: shortcuts and special keys from keydown; typed text (and what an input
    // method such as Telex composes) from its input events, so Vietnamese typing on the laptop works.
    const special = ['Enter','Backspace','Tab','Escape','ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Delete','Home','End','PageUp','PageDown'];
    kb.addEventListener('keydown', e => {
      if (e.isComposing || e.keyCode === 229) return;
      const mod = e.metaKey || e.ctrlKey || e.altKey;
      if (mod || special.includes(e.key)) {
        send({t: 'k', key: e.key, code: e.code, meta: e.metaKey, ctrl: e.ctrlKey, alt: e.altKey, shift: e.shiftKey});
        e.preventDefault();
      }
    });
    kb.addEventListener('input', e => { if (e.isComposing) return; if (e.data) send({t: 'text', s: e.data}); kb.value = ''; });
    kb.addEventListener('compositionend', e => { if (e.data) send({t: 'text', s: e.data}); kb.value = ''; });
    document.addEventListener('paste', e => { const s = e.clipboardData.getData('text'); if (s) send({t: 'text', s}); e.preventDefault(); });
    addEventListener('focus', () => kb.focus());
    </script></body></html>
    """#
}

/// The laptop's mouse and keyboard, as the browser reports them.
enum RemoteInput {
    static func handle(_ e: [String: Any]) {
        let model = DesktopModel.shared
        guard model.isExternalConnected else { return }
        let size = model.screenSize
        func moveTo() {
            guard let x = e["x"] as? Double, let y = e["y"] as? Double else { return }
            let p = CGPoint(x: min(max(x, 0), 1) * size.width, y: min(max(y, 0), 1) * size.height)
            let c = model.cursor.position
            model.moveCursor(dx: p.x - c.x, dy: p.y - c.y)
        }
        switch e["t"] as? String {
        case "m": moveTo()
        case "d":
            moveTo()
            switch e["b"] as? Int {
            case 2: model.rightClick()
            case 1: model.middleClick()
            default: model.physicalPress()
            }
        case "u":
            if (e["b"] as? Int ?? 0) == 0, model.cursor.isPressed { model.physicalRelease() }
        case "w":
            let dx = CGFloat(e["dx"] as? Double ?? 0), dy = CGFloat(e["dy"] as? Double ?? 0)
            model.scroll(dx: dx, dy: dy)
        case "text":
            if let s = e["s"] as? String, !s.isEmpty { model.typeText(s) }
        case "k":
            key(e, model)
        default:
            break
        }
    }

    private static func key(_ e: [String: Any], _ model: DesktopModel) {
        let name = e["key"] as? String ?? "", code = e["code"] as? String ?? ""
        let shift = e["shift"] as? Bool ?? false
        var flags: UIKeyModifierFlags = []
        if e["meta"] as? Bool == true { flags.insert(.command) }
        if e["ctrl"] as? Bool == true { flags.insert(.control) }
        if e["alt"] as? Bool == true { flags.insert(.alternate) }
        if shift { flags.insert(.shift) }
        if !flags.subtracting(.shift).isEmpty {
            let chars = code.hasPrefix("Key") ? String(code.dropFirst(3)).lowercased()
                : code.hasPrefix("Digit") ? String(code.dropFirst(5)) : name.lowercased()
            if PhoneWindow.performShortcut(chars: chars, keyCode: usage(code), flags: flags) { return }
        }
        switch name {
        case "Enter": model.pressEnter()
        case "Backspace": model.backspace()
        case "Escape": model.escape()
        case "Tab": model.sendKey("Tab", 9, shift)
        case "ArrowLeft": model.sendKey("ArrowLeft", 37, shift)
        case "ArrowRight": model.sendKey("ArrowRight", 39, shift)
        case "ArrowUp": model.sendKey("ArrowUp", 38, shift)
        case "ArrowDown": model.sendKey("ArrowDown", 40, shift)
        case "Delete": model.sendKey("Delete", 46, shift)
        case "Home": model.sendKey("Home", 36, shift)
        case "End": model.sendKey("End", 35, shift)
        case "PageUp": model.sendKey("PageUp", 33, shift)
        case "PageDown": model.sendKey("PageDown", 34, shift)
        default:
            if name.count == 1, flags.subtracting(.shift).isEmpty { model.typeText(name) }
        }
    }

    /// The browser's key code → the HID usage the shortcuts look at (arrows, Tab, the digits for screenshots).
    private static func usage(_ code: String) -> UIKeyboardHIDUsage {
        switch code {
        case "ArrowLeft": return .keyboardLeftArrow
        case "ArrowRight": return .keyboardRightArrow
        case "ArrowUp": return .keyboardUpArrow
        case "ArrowDown": return .keyboardDownArrow
        case "Tab": return .keyboardTab
        case "Space": return .keyboardSpacebar
        case "Digit3": return .keyboard3
        case "Digit4": return .keyboard4
        case "Digit5": return .keyboard5
        case "KeyS": return .keyboardS
        default: return .keyboardErrorUndefined
        }
    }
}

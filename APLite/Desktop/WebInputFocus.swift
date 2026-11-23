import Foundation
import WebKit

/// Reports text-field focus from any web page to APLite. The external display gets no touches, so
/// there is no UITextField to observe: pages are driven with JavaScript and their focus lives in
/// `document.activeElement`. This bridge is the general version of the Files page's own
/// focusin / focusout hook and is added to every tab.
final class WebInputFocusBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "ideskInputFocus"
    weak var window: DeskWindow?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let web = message.webView else { return }
        let focused = (body["focused"] as? Bool) ?? false
        let model = DesktopModel.shared
        // Tapping into a field is an explicit request for the keyboard: undo a previous "hide".
        if focused, model.virtualKeyboardDismissed { model.virtualKeyboardDismissed = false }
        window?.setEditing(web, focused)
        model.objectWillChange.send()   // redraw the desktop so the keyboard follows the focus
    }

    static var script: WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static let source = """
    (() => {
      const sel = 'input,textarea,select,[contenteditable]:not([contenteditable="false"])';
      const editing = () => !!(document.activeElement && document.activeElement.closest
        && document.activeElement.closest(sel));
      const post = () => {
        try { window.webkit.messageHandlers.ideskInputFocus.postMessage({ focused: editing() }); }
        catch (_) {}
      };
      document.addEventListener('focusin', post, true);
      document.addEventListener('focusout', () => setTimeout(post, 0), true);
      document.addEventListener('mousedown', () => setTimeout(post, 0), true);
    })();
    """
}

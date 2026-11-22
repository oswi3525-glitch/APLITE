import UIKit
import UniformTypeIdentifiers
import PhotosUI

/// The topmost view controller on the iPhone, to present system sheets from anywhere (even from a sheet).
private func topViewController() -> UIViewController? {
    var top = PhoneWindow.current?.rootViewController
    while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
    return top
}

/// Presents the iOS document picker (UIKit).
///
/// SwiftUI's `.fileImporter` is not used: presented from inside a sheet it often drops the result (the user
/// taps "Open" and the app gets nothing). Here the picker is presented from the topmost controller and the
/// delegate is retained until the pick finishes.
final class DocumentPicker: NSObject, UIDocumentPickerDelegate {
    private static var active: DocumentPicker?
    private let completion: ([URL]) -> Void

    private init(completion: @escaping ([URL]) -> Void) {
        self.completion = completion
    }

    /// Allows any file type (filtering by type often greys out .p12 / .mobileprovision).
    /// Files are copied into the app's temporary folder, so no security-scoped access is needed.
    static func present(completion: @escaping ([URL]) -> Void) {
        present(types: [.item], completion: completion)
    }

    /// A picker limited to the given types (for example `.image` for a wallpaper).
    static func present(types: [UTType], completion: @escaping ([URL]) -> Void) {
        guard let host = topViewController() else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        // Several IPAs at once; or the certificate files (.p12, .mobileprovision, pass.txt) together.
        picker.allowsMultipleSelection = true
        let delegate = DocumentPicker(completion: completion)
        picker.delegate = delegate
        active = delegate
        host.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Self.active = nil
        // Wait for the picker to fully dismiss so a result alert can be shown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.completion(urls) }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Self.active = nil
    }
}

/// The iOS share sheet for one file (to open it in a signing app or save it to Files).
enum ShareSheet {
    static func present(_ file: URL) {
        guard let host = topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = host.view
        host.present(sheet, animated: true)
    }
}

/// The iOS photo picker, for a wallpaper chosen from the desktop's Settings (it can only be shown on the iPhone).
final class PhotoPicker: NSObject, PHPickerViewControllerDelegate {
    private static var active: PhotoPicker?
    private let completion: (Data) -> Void

    private init(completion: @escaping (Data) -> Void) {
        self.completion = completion
    }

    static func present(completion: @escaping (Data) -> Void) {
        guard let host = topViewController() else { return }
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        let delegate = PhotoPicker(completion: completion)
        picker.delegate = delegate
        active = delegate
        host.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        Self.active = nil
        guard let provider = results.first?.itemProvider else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [completion] data, _ in
            guard let data else { return }
            DispatchQueue.main.async { completion(data) }
        }
    }
}

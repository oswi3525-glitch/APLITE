import Foundation
import WebKit

/// Bounds the caches APLite actually owns. WebKit's disk/memory cache and the shared URLCache grow
/// without a hard limit in a long desktop session; trimming old entries periodically keeps RAM and
/// storage steady and reduces the thermal load caused by constant cache churn.
final class CacheManager: ObservableObject {
    static let shared = CacheManager()

    @Published private(set) var lastTrim = Date.distantPast

    private var timer: Timer?
    private let dataStore = WKWebsiteDataStore.default()

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.trim() }
        timer?.tolerance = 30
    }

    func stop() { timer?.invalidate(); timer = nil }

    func trim() {
        // Quick wins, synchronous and safe on the main thread.
        URLCache.shared.removeAllCachedResponses()
        QuickLook.clearImageCache()
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        let cutoff = Date().addingTimeInterval(-3 * 24 * 3600)
        dataStore.removeData(ofTypes: types, modifiedSince: cutoff) { [weak self] in
            // Only the completion marks the trim as finished — the old synchronous assignment
            // reported success before WebKit had actually released anything.
            DispatchQueue.main.async { self?.lastTrim = Date() }
        }
    }
}

import Foundation
import WebKit

/// Bounds the caches APLite actually owns. WebKit's disk/memory cache and the shared URLCache grow
/// without a hard limit in a long desktop session; trimming old entries periodically keeps RAM and
/// storage steady and reduces the thermal load caused by constant cache churn.
final class CacheManager: ObservableObject {
    static let shared = CacheManager()

    @Published private(set) var lastTrim = Date.distantPast
    @Published private(set) var lastRemovedRecords = 0

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
        dataStore.fetchDataRecords(ofTypes: types) { [weak self] records in
            guard let self else { return }
            let cutoff = Date().addingTimeInterval(-3 * 24 * 3600)
            let old = records.filter { ($0.modificationDate ?? .distantPast) < cutoff }
            guard !old.isEmpty else { return }
            self.dataStore.removeData(ofTypes: types, for: old) {
                DispatchQueue.main.async {
                    self.lastTrim = Date()
                    self.lastRemovedRecords = old.count
                }
            }
        }
        DispatchQueue.main.async { self.lastTrim = Date() }
    }
}

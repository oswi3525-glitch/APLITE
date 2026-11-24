import SwiftUI

/// Cleanup & Optimize tab. Every delete is scoped to APLite's own sandbox and goes through
/// `CleanupManager`; the UI never promises to clean iOS or another app.
struct CleanupSettingsView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject private var memory = MemoryManager.shared
    @State private var targets: [CleanupTarget] = []
    @State private var hasScanned = false
    @State private var isScanning = false
    @State private var confirmRemoval = false
    @State private var confirmCacheRelease = false

    private var totalBytes: UInt64 { targets.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        List {
            Section {
                Button { scan() } label: {
                    Label("Scan APLite's files", systemImage: "magnifyingglass")
                }
                .disabled(isScanning)
                if hasScanned {
                    LabeledContent("Junk found", value: APLiteFileManager.sizeText(Int64(totalBytes)))
                }
                Text("Scans caches, temporary install files, rotated logs, old reports and unused web app icons — only inside APLite's own sandbox.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if hasScanned {
                Section("Found") {
                    if targets.isEmpty {
                        Text("Nothing to clean. APLite's files are in order.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(targets) { target in
                            LabeledContent(target.title, value: APLiteFileManager.sizeText(Int64(target.bytes)))
                        }
                        Button("Delete \(targets.count) junk item(s)", role: .destructive) {
                            confirmRemoval = true
                        }
                    }
                }
            }

            Section("Quick actions") {
                Button("Release caches now") { confirmCacheRelease = true }
                Button("Save a diagnostics report") {
                    if APLiteFileManager.writeDiagnostics() != nil {
                        model.showToast(String(localized: "Diagnostics saved in APLite's file area."))
                    }
                }
                Button("Open Files") { model.openPage(.files) }
                Text(memory.report()).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Cleanup & Optimize")
        .confirmationDialog("Delete APLite-owned junk?", isPresented: $confirmRemoval) {
            Button("Delete", role: .destructive) { performCleanup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only APLite's caches, stale temporary files and old reports are removed. User files and installed apps stay.")
        }
        .confirmationDialog("Release caches?", isPresented: $confirmCacheRelease) {
            Button("Release", role: .destructive) {
                memory.releaseCaches(reason: "cleanup settings")
                model.showToast(String(localized: "Caches released."))
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { if targets.isEmpty, !isScanning { scan() } }
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        CleanupManager.scan { found in
            targets = found
            hasScanned = true
            isScanning = false
            APLog.info("Cleanup scan found \(found.count) categories", module: "Cleanup")
        }
    }

    private func performCleanup() {
        let chosen = targets
        CleanupManager.remove(chosen) { freed in
            model.showToast(String(localized: "Freed \(APLiteFileManager.sizeText(Int64(freed))) of APLite-owned files."))
            targets = []
        }
    }
}

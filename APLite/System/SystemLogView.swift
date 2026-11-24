import SwiftUI

/// Settings → Privacy & Security → System Log.
///
/// Reads only APLite's own persisted log file. No `OSLogStore`, no private API, no attempt to read
/// another app's log — iOS forbids all of those.
struct SystemLogView: View {
    @State private var entries: [APLogEntry] = []
    @State private var level: APLogLevel?
    @State private var showClearConfirmation = false

    private var visible: [APLogEntry] { APLog.filter(entries, level: level) }

    var body: some View {
        List {
            Section {
                Picker("Level", selection: $level) {
                    Text("All").tag(nil as APLogLevel?)
                    ForEach(APLogLevel.allCases, id: \.self) { value in
                        Text(value.title).tag(value as APLogLevel?)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if visible.isEmpty {
                    ContentUnavailableView(
                        "No log entries",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Events such as slow startup, permission errors and failed installs appear here.")
                    )
                } else {
                    ForEach(visible) { entry in
                        VStack(alignment: .leading, spacing: APLiteDesign.Space.xs) {
                            HStack(spacing: APLiteDesign.Space.sm) {
                                Text(entry.level.title)
                                    .font(APLiteDesign.Typography.caption.weight(.semibold))
                                    .foregroundStyle(entry.level == .fault || entry.level == .error
                                                     ? APLiteColors.red : APLiteColors.accent)
                                Text(entry.module)
                                    .font(APLiteDesign.Typography.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.timestamp, style: .time)
                                    .font(APLiteDesign.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(APLiteDesign.Typography.caption)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, APLiteDesign.Space.xs)
                    }
                }
            } footer: {
                Text("APLite keeps a bounded copy of its own log. Unified Log entries remain in the system and cannot be deleted by an app.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("System log")
        .toolbar {
            Button("Clear") { showClearConfirmation = true }
        }
        .confirmationDialog("Clear APLite's log copy?", isPresented: $showClearConfirmation) {
            Button("Clear log", role: .destructive) {
                APLog.clear()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { reload() }
    }

    private func reload() {
        APLog.entries { loaded in entries = loaded }
    }
}

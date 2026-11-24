import SwiftUI

/// Settings → Privacy & Security → Export beta surveys. Hidden entirely on stable builds.
struct SurveyExportView: View {
    @State private var records: [SurveyRecord] = []
    @State private var showClearConfirmation = false

    var body: some View {
        List {
            Section("Saved surveys") {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No surveys yet",
                        systemImage: "camera.viewfinder",
                        description: Text("Use the four-finger hold, or the button below, to capture an area and describe the problem.")
                    )
                } else {
                    ForEach(records) { record in
                        HStack(spacing: APLiteDesign.Space.md) {
                            if let image = UIImage(data: record.imageData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: APLiteDesign.Radius.sm, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: APLiteDesign.Space.xs) {
                                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(APLiteDesign.Typography.caption)
                                Text(record.note.isEmpty ? String(localized: "No note") : record.note)
                                    .font(APLiteDesign.Typography.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Start a survey") {
                    NotificationCenter.default.post(name: .apliteStartBetaSurvey, object: nil)
                }
                Button("Export all surveys") {
                    if let url = BetaSurvey.exportURL() { ShareSheet.present(url) }
                }
                .disabled(records.isEmpty)
                Button("Delete all surveys", role: .destructive) { showClearConfirmation = true }
                    .disabled(records.isEmpty)
            } footer: {
                Text("Exports one JSON file with screenshots, notes, timestamps and device metadata, ready to save to Files or iCloud Drive and share with the APLite team. Check the captured area first: avoid passwords, cookies and private data. Note text is redacted automatically.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Export beta surveys")
        .onAppear { records = BetaSurvey.records() }
        .confirmationDialog("Delete all saved surveys?", isPresented: $showClearConfirmation) {
            Button("Delete", role: .destructive) {
                BetaSurvey.clear()
                records = []
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

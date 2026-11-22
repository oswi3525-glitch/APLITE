import SwiftUI

/// Read-only preview of the files an App Creator template would write. Nothing is compiled or
/// executed here — it is a source viewer before exporting the project ZIP.
struct ProjectPreviewView: View {
    let files: [String: String]
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String

    init(files: [String: String]) {
        self.files = files
        _selected = State(initialValue: files.keys.sorted().first ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("File", selection: $selected) {
                    ForEach(files.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

                ScrollView {
                    Text(files[selected] ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Project preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

import SwiftUI

/// APLite's About screen on the iPhone. The same attribution is shown in the desktop Settings
/// page and in README.md, as required by the project rules.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.55, blue: 0.62),
                                                          Color(red: 0.08, green: 0.22, blue: 0.42)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 64, height: 64)
                            .overlay(Image(systemName: "display")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: APLite.name).font(.title3.bold())
                            Text(verbatim: APLite.fullName).foregroundStyle(.secondary)
                            Text(verbatim: "\(String(localized: "Version")) \(APLite.version)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Text(verbatim: APLite.attribution)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Attribution")
                }

                Section {
                    Link(destination: APLite.upstreamURL) {
                        Label("Original iDesk project", systemImage: "arrow.up.forward.square")
                    }
                    if let url = URL(string: "https://github.com/\(APLite.repository)") {
                        Link(destination: url) {
                            Label("APLite repository", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                } footer: {
                    Text("APLite is not an official release or endorsement of the original iDesk project.")
                }

                Section("License") {
                    Text("MIT License. The original copyright notice is kept in the LICENSE file.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About APLite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

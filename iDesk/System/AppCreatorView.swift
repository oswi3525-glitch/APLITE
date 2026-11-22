import SwiftUI

private struct TemplatePickerSection: View {
    @Binding var template: AppTemplate

    var body: some View {
        Section("Template") {
            ForEach(AppTemplate.allCases, id: \.self) { item in
                Button { template = item } label: {
                    HStack {
                        Image(systemName: item.symbol).foregroundStyle(.tint)
                        Text(item.title)
                        Spacer()
                        if item == template { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
        }
    }
}

private struct AppDetailsSection: View {
    @Binding var name: String
    @Binding var bundleID: String

    var body: some View {
        Section("App details") {
            TextField("Display name", text: $name)
            TextField("Bundle ID", text: $bundleID)
        }
    }
}

private struct AppResultSection: View {
    let result: URL
    let analyse: () -> Void

    var body: some View {
        Section("Created") {
            Text(result.lastPathComponent).font(.footnote)
            Button("Share project ZIP") { ShareSheet.present(result) }
            Button("Analyse in Build Center", action: analyse)
        }
    }
}

struct AppCreatorView: View {
    @ObservedObject private var center = BuildCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var template: AppTemplate = .basic
    @State private var name = "My App"
    @State private var bundleID = "com.example.myapp"
    @State private var result: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                TemplatePickerSection(template: $template)
                AppDetailsSection(name: $name, bundleID: $bundleID)
                Section {
                    Button("Generate project ZIP", action: generate)
                    Text("Creates real Swift sources and a project.yml in APLite's file area. A macOS worker is still required to compile it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let result { AppResultSection(result: result, analyse: { analyse(result) }) }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("App Creator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func generate() {
        do {
            result = try AppCreator.create(template: template, displayName: name, bundleID: bundleID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func analyse(_ zip: URL) {
        do {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("aplite-generated-\(UUID().uuidString)", isDirectory: true)
            try Unzip.extract(zip, to: destination)
            let files = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            _ = try center.analyze(files)
            error = nil
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

import SwiftUI

/// UI for the Build Center. Every status shown here comes from the GitHub Actions API; this view
/// never reports a local build or a fabricated success.
struct BuildCenterView: View {
    @ObservedObject private var center = BuildCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var owner = ""
    @State private var repo = ""
    @State private var token = ""
    @State private var workflow = "build.yml"
    @State private var ref = "main"
    @State private var error: String?
    @State private var showCreator = false

    var body: some View {
        NavigationStack {
            Form {
                Section("macOS build worker") {
                    Text("iOS cannot run Xcode. APLite analyses the project locally and sends build requests to a GitHub Actions workflow on a macOS runner. Only the runner's own status is shown.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Repository owner", text: $owner).textInputAutocapitalization(.never)
                    TextField("Repository name", text: $repo).textInputAutocapitalization(.never)
                    SecureField("GitHub token (stored in Keychain)", text: $token)
                    Button("Save worker") {
                        do {
                            try center.configure(owner: owner, repo: repo, token: token)
                            token = ""
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(owner.isEmpty || repo.isEmpty || token.isEmpty)
                    .buttonStyle(APLiteGlassButtonStyle())
                    LabeledContent("Configured", value: center.isConfigured ? "yes" : "no")
                }

                Section("Project") {
                    Button("Create a new app project") { showCreator = true }
                        .buttonStyle(APLiteGlassButtonStyle())
                    Button("Import project files from Files") {
                        DocumentPicker.present { urls in
                            do {
                                _ = try center.analyze(urls)
                                error = nil
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    if let analysis = center.analysis {
                        LabeledContent("Summary", value: analysis.summary)
                        LabeledContent("Bundle ID", value: analysis.bundleID ?? String(localized: "not found"))
                        if !analysis.dependencies.isEmpty {
                            Text("Dependencies: \(analysis.dependencies.joined(separator: ", "))")
                                .font(.footnote)
                        }
                        ForEach(analysis.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                        Text(analysis.needsMacOSWorker
                             ? String(localized: "A macOS runner is required to compile this project.")
                             : String(localized: "No build specification was found; add a project file before requesting a build."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Build") {
                    TextField("Workflow file", text: $workflow).textInputAutocapitalization(.never)
                    TextField("Branch or tag", text: $ref).textInputAutocapitalization(.never)
                    Button("Request a build") {
                        Task {
                            do { try await center.requestBuild(workflow: workflow, ref: ref); error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(!center.isConfigured)
                    Button("Refresh run statuses") {
                        Task {
                            do { try await center.refreshBuilds(); error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(!center.isConfigured)
                    LabeledContent("Status", value: center.status)
                    ForEach(center.builds) { build in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("#\(build.id) · \(build.display)").font(.subheadline)
                            Text(build.createdAt).font(.caption2).foregroundStyle(.secondary)
                            if build.conclusion == "success" {
                                Button("Download IPA artifact (zip)") {
                                    Task {
                                        do { _ = try await center.downloadIPA(for: build); error = nil }
                                        catch { self.error = error.localizedDescription }
                                    }
                                }
                            }
                        }
                    }
                }

                if let error { Section { Text(error).foregroundStyle(APLiteColors.red).font(.footnote) } }
            }
            .navigationTitle("Build Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                owner = center.owner
                repo = center.repo
            }
        }
        .sheet(isPresented: $showCreator) { AppCreatorView() }
    }
}

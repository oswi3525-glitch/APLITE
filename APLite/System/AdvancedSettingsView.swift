import SwiftUI
import UniformTypeIdentifiers

/// The rarely used tools, kept out of the main System settings list. Nothing is deleted: Build Center,
/// App Creator, certificate import and Technical Diagnostics remain reachable from this one page.
struct AdvancedSettingsView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject private var certificates = CertificateManager.shared

    @State private var showBuildCenter = false
    @State private var confirmRemoveCertificate = false
    @State private var showCertificatePassword = false
    @State private var certificatePassword = ""
    @State private var pendingCertificate: Data?

    var body: some View {
        List {
            Section {
                Button { showBuildCenter = true } label: {
                    Label("Build Center & App Creator", systemImage: "hammer")
                }
                Text("Analyse projects and send them to a macOS CI worker. No build runs on the iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Developer")
            }

            Section {
                LabeledContent("Certificate", value: certificates.identityName ?? String(localized: "None"))
                if let error = certificates.lastError {
                    Text(error).foregroundStyle(APLiteColors.red).font(.footnote)
                }
                Button("Import .p12 / .pfx from Files") { importCertificate() }
                if certificates.hasIdentity {
                    Button("Remove certificate", role: .destructive) { confirmRemoveCertificate = true }
                }
            } header: {
                Text("Certificates")
            }

            Section {
                NavigationLink { TechnicalDiagnosticsView(model: model) } label: {
                    Label("Technical Diagnostics", systemImage: "stethoscope")
                }
                Button("Save a diagnostics report") {
                    if APLiteFileManager.writeDiagnostics() != nil {
                        model.showToast(String(localized: "Diagnostics saved in APLite's file area."))
                    }
                }
            } header: {
                Text("Diagnostics")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showBuildCenter) { BuildCenterView() }
        .alert("Remove certificate?", isPresented: $confirmRemoveCertificate) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { certificates.remove() }
        } message: {
            Text("The imported signing certificate will be removed from the Keychain.")
        }
        .alert("Certificate password", isPresented: $showCertificatePassword) {
            SecureField("Password", text: $certificatePassword)
            Button("Cancel", role: .cancel) { pendingCertificate = nil }
            Button("Import") {
                guard let data = pendingCertificate else { return }
                do {
                    try certificates.import(p12: data, password: certificatePassword)
                    model.showToast(String(localized: "Certificate imported."))
                } catch {
                    model.showToast(error.localizedDescription)
                }
                pendingCertificate = nil
                certificatePassword = ""
            }
        } message: {
            Text("Enter the password for the .p12 / .pfx file. It is stored in the Keychain and never logged.")
        }
    }

    private func importCertificate() {
        DocumentPicker.present { urls in
            guard let url = urls.first else { return }
            do {
                pendingCertificate = try CertificateManager.shared.readCertificate(from: url)
                certificatePassword = ""
                showCertificatePassword = true
            } catch {
                model.showToast(error.localizedDescription)
            }
        }
    }
}

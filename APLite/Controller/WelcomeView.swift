import SwiftUI

/// The first-run guide on the iPhone: what to plug in, how to point and type, how to add apps.
/// Shown once (and again from Settings → Help).
struct WelcomeView: View {
    static let seenKey = "iDesk.welcomeSeen"

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var showMouseCheck = false

    private struct Page {
        let symbol: String
        let title: String.LocalizationValue
        let lines: [String.LocalizationValue]
        /// Steps to follow in order: numbered instead of ticked.
        var numbered = false
        /// Lines that say what does NOT work (✕) or add a caveat (ⓘ), by index; the others are ticked.
        var cannot: Set<Int> = []
        var caveat: Set<Int> = []
    }

    private let pages: [Page] = [
        Page(symbol: "display", title: "Connect a display", lines: [
            "Plug the iPhone into a monitor or TV with a USB-C → HDMI or DisplayPort cable (or a USB-C hub).",
            "A hub with a power port charges the iPhone while you work.",
            "The desktop appears on the display; the iPhone becomes its trackpad and keyboard.",
            "Keep APLite open on the iPhone while you work: locking it or opening another app pauses the desktop.",
        ]),
        Page(symbol: "checklist", title: "What opens on the desktop", lines: [
            "Websites and web apps, in windows with tabs: YouTube, Gmail, Google Docs, Facebook, Zalo Web…",
            "Files: downloads, photos, PDFs, videos and text files, with a text editor.",
            "Apps installed from the App Store can't appear: iOS doesn't let one app show another app's screen.",
            "iOS apps run only from decrypted IPA files added to APLite (next page). Not every app works inside it.",
        ], cannot: [2], caveat: [3]),
        Page(symbol: "hand.point.up.left", title: "The iPhone is the trackpad", lines: [
            "Move one finger to move the pointer, tap to click, tap with two fingers to right-click.",
            "Drag with two fingers to scroll; hold, then drag to move windows.",
            "Three fingers: up for recent apps, down for the desktop, tap to go back.",
        ]),
        Page(symbol: "keyboard", title: "Keyboard and mouse", lines: [
            "A Bluetooth keyboard works right away: pair it in the iPhone's Settings → Bluetooth.",
            "On iPhone a mouse goes through AssistiveTouch: Settings → Accessibility → Touch → AssistiveTouch, then pair the mouse.",
            "Or type on the iPhone: the field at the bottom (any language), or Live typing for each key.",
        ]),
        Page(symbol: "shippingbox", title: "Adding an iOS app", lines: [
            "Get a decrypted IPA file of the app. Copies from the App Store are encrypted and can't run.",
            "Tap Apps on the trackpad (the box button), then add the IPA file.",
            "Tap “Install new apps into APLite” and pick ESign: it signs APLite again with the apps inside and installs it.",
            "Open APLite again: the apps are in the app menu, and open as windows.",
        ], numbered: true),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    pageView(pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack(spacing: 10) {
                if page == 3 {
                    Button { showMouseCheck = true } label: {
                        Label("Mouse check", systemImage: "computermouse")
                    }
                }
                Button {
                    if page < pages.count - 1 { withAnimation { page += 1 } } else { finish() }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : "Start using APLite")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                if page < pages.count - 1 {
                    Button("Skip", action: finish).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMouseCheck) { MouseCheckView() }
    }

    private func pageView(_ p: Page) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: p.symbol)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            Text(verbatim: Device.words(String(localized: p.title))).font(.title2.bold()).frame(maxWidth: .infinity)
            ForEach(p.lines.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        if p.cannot.contains(i) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                        } else if p.caveat.contains(i) {
                            Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                        } else {
                            Image(systemName: p.numbered ? "\(i + 1).circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.top, 2)
                    Text(verbatim: Device.words(String(localized: p.lines[i]))).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 640)          // readable lines on an iPad
        .font(Device.isPad ? .title3 : .body)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        dismiss()
    }
}

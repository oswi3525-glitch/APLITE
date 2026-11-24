import SwiftUI

/// Beta-only capture tool. Shows a snapshot of the desktop, lets the user drag a rectangle,
/// previews the crop, then saves it with a note. Shown only on builds whose channel contains "beta".
struct BetaSurveyCaptureView: View {
    private enum Stage { case selecting, review }

    private let source: UIImage?
    @State private var stage: Stage = .selecting
    @State private var selection: CGRect?
    @State private var dragStart: CGPoint?
    @State private var cropped: UIImage?
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    init() {
        source = BetaSurvey.captureDesktopImage()
    }

    var body: some View {
        ZStack {
            APLiteDesign.Surface.bootBackground.ignoresSafeArea()

            if stage == .selecting {
                selectingView
            } else {
                reviewView
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Selecting

    private var selectingView: some View {
        VStack(spacing: APLiteDesign.Space.lg) {
            Text("Drag over the area with the problem")
                .font(APLiteDesign.Typography.title)
                .foregroundStyle(APLiteDesign.Surface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geometry in
                let layout = imageLayout(in: geometry.size)
                ZStack(alignment: .topLeading) {
                    if let source {
                        Image(uiImage: source)
                            .resizable()
                            .scaledToFit()
                            .frame(width: layout.drawn.width, height: layout.drawn.height)
                            .position(x: layout.origin.x + layout.drawn.width / 2,
                                      y: layout.origin.y + layout.drawn.height / 2)
                    } else {
                        ContentUnavailableView(
                            "No desktop to capture",
                            systemImage: "camera",
                            description: Text("Connect a display or use preview mode, then try again.")
                        )
                    }

                    if let selection {
                        let rect = viewRect(for: selection, in: layout)
                        Rectangle()
                            .stroke(APLiteColors.accent, lineWidth: 2)
                            .background(APLiteColors.accent.opacity(0.12))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let layout = imageLayout(in: geometry.size)
                            if dragStart == nil { dragStart = clamp(value.startLocation, in: layout) }
                            guard let start = dragStart else { return }
                            let current = clamp(value.location, in: layout)
                            let a = imagePoint(start, in: layout)
                            let b = imagePoint(current, in: layout)
                            selection = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                               width: abs(b.x - a.x), height: abs(b.y - a.y))
                        }
                        .onEnded { _ in dragStart = nil }
                )
            }

            HStack(spacing: APLiteDesign.Space.md) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .frame(minHeight: APLiteDesign.touchTarget)
                Spacer()
                Button("Use this area") { makeCrop() }
                    .buttonStyle(APLiteGlassButtonStyle())
                    .frame(minHeight: APLiteDesign.touchTarget)
                    .disabled(selection == nil)
            }
        }
        .padding(APLiteDesign.Space.xl)
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: APLiteDesign.Space.lg) {
            Text("What went wrong?")
                .font(APLiteDesign.Typography.title)
                .foregroundStyle(APLiteDesign.Surface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let cropped {
                Image(uiImage: cropped)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: APLiteDesign.Radius.md, style: .continuous))
                    .frame(maxHeight: 320)
            }

            SwiftUI.TextEditor(text: $note)
                .frame(minHeight: 100)
                .clipShape(RoundedRectangle(cornerRadius: APLiteDesign.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: APLiteDesign.Radius.sm, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )

            HStack(spacing: APLiteDesign.Space.md) {
                Button("Retake") {
                    stage = .selecting
                    selection = nil
                    cropped = nil
                }
                .frame(minHeight: APLiteDesign.touchTarget)
                Spacer()
                Button("Save report") { save() }
                    .buttonStyle(APLiteGlassButtonStyle())
                    .frame(minHeight: APLiteDesign.touchTarget)
                    .disabled(cropped == nil)
            }
        }
        .padding(APLiteDesign.Space.xl)
    }

    // MARK: - Logic

    private struct Layout {
        let drawn: CGSize
        let origin: CGPoint
        let scale: CGFloat
    }

    private func imageLayout(in size: CGSize) -> Layout {
        guard let source, size.width > 0, size.height > 0 else {
            return Layout(drawn: .zero, origin: .zero, scale: 1)
        }
        let scale = min(size.width / source.size.width, size.height / source.size.height)
        let drawn = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        return Layout(drawn: drawn,
                      origin: CGPoint(x: (size.width - drawn.width) / 2,
                                      y: (size.height - drawn.height) / 2),
                      scale: scale)
    }

    private func clamp(_ point: CGPoint, in layout: Layout) -> CGPoint {
        CGPoint(x: min(max(point.x, layout.origin.x), layout.origin.x + layout.drawn.width),
                y: min(max(point.y, layout.origin.y), layout.origin.y + layout.drawn.height))
    }

    /// Selection is stored in image points so it stays correct at any container size.
    private func imagePoint(_ point: CGPoint, in layout: Layout) -> CGPoint {
        CGPoint(x: (point.x - layout.origin.x) / layout.scale,
                y: (point.y - layout.origin.y) / layout.scale)
    }

    private func viewRect(for rect: CGRect, in layout: Layout) -> CGRect {
        CGRect(x: rect.minX * layout.scale + layout.origin.x,
               y: rect.minY * layout.scale + layout.origin.y,
               width: rect.width * layout.scale,
               height: rect.height * layout.scale)
    }

    private func makeCrop() {
        guard let source, let selection, selection.width > 4, selection.height > 4 else { return }
        let pixelRect = CGRect(x: selection.minX * source.scale,
                               y: selection.minY * source.scale,
                               width: selection.width * source.scale,
                               height: selection.height * source.scale)
        guard let cg = source.cgImage?.cropping(to: pixelRect) else { return }
        cropped = UIImage(cgImage: cg, scale: source.scale, orientation: source.imageOrientation)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        stage = .review
    }

    private func save() {
        guard let cropped else { return }
        BetaSurvey.save(image: cropped, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

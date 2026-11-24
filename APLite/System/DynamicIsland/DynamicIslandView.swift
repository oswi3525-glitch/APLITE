import SwiftUI

enum IslandDisplayRole {
    case phone
    case external
}

struct DynamicIslandView: View {
    @ObservedObject private var now = NowPlayingService.shared
    @ObservedObject private var spectrum = AudioSpectrumProvider.shared
    @ObservedObject private var desktop = DesktopModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var island
    let role: IslandDisplayRole

    private var visible: Bool {
        guard now.item != nil else { return false }
        return role == .external ? desktop.isExternalConnected : !desktop.isExternalConnected
    }

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .allowsHitTesting(false)
                .overlay(alignment: .top) {
                    if visible {
                        VStack(spacing: 0) {
                            islandContent(width: min(340, max(220, geo.size.width - 32)))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, geo.safeAreaInsets.top + 8)
                        .transition(.opacity)
                        .animation(reduceMotion ? .linear(duration: 0.001) : APLiteAnimation.island,
                                   value: visible)
                    }
                }
        }
        .onPreferenceChange(IslandFramePreference.self) { frames in
            for (control, rect) in frames { now.setFrame(rect, for: control) }
        }
    }

    @ViewBuilder
    private func islandContent(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            if now.isExpanded {
                expandedCard(width: width)
                    .matchedGeometryEffect(id: "aplite.island", in: island)
            } else {
                collapsedPill
                    .matchedGeometryEffect(id: "aplite.island", in: island)
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.001) : APLiteAnimation.island, value: now.isExpanded)
        .animation(reduceMotion ? .linear(duration: 0.001) : APLiteAnimation.island, value: now.item?.id)
    }

    private var collapsedPill: some View {
        Button { now.toggleExpanded() } label: {
            HStack(spacing: APLiteDesign.Space.sm) {
                artwork(size: 24)
                if let item = now.item {
                    Text(item.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                SpectrumBars(levels: spectrum.levels.prefix(5).map { $0 }, count: 5, height: 12)
                Image(systemName: now.isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, APLiteDesign.Space.md)
            .frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule()) // taste:allow hand-glass system material required by spec
        }
        .buttonStyle(.plain)
        .allowsHitTesting(true)
        .reportIslandFrame(.pill)
        .onLongPressGesture(minimumDuration: 0.35) {
            now.setExpanded(true)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text("Press and hold to show playback controls"))
        .accessibilityAction(named: Text("Play or pause")) { now.togglePlayPause() }
    }

    private func expandedCard(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: APLiteDesign.Space.md) {
            HStack(spacing: APLiteDesign.Space.sm) {
                artwork(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(now.item?.title ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(now.item?.subtitle ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { now.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: APLiteDesign.touchTarget, height: APLiteDesign.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close media"))
                .reportIslandFrame(.close)
            }

            SpectrumBars(levels: spectrum.levels, count: SpectrumAnalyzer.bandCount, height: 38)

            VStack(spacing: 6) {
                Slider(value: Binding(get: { now.progress }, set: { now.seek(progress: $0) }))
                    .reportIslandFrame(.progress)
                    .accessibilityLabel(Text("Playback position"))
                HStack {
                    Text(islandTime(now.elapsed)).font(.caption2).monospacedDigit()
                    Spacer()
                    Text(islandTime(now.duration)).font(.caption2).monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: APLiteDesign.Space.md) {
                islandButton("gobackward.10", label: "Back 10 seconds") { now.skip(by: -10) }
                    .reportIslandFrame(.backward)
                Spacer()
                islandButton(now.isPlaying ? "pause.fill" : "play.fill",
                             label: now.isPlaying ? "Pause" : "Play") { now.togglePlayPause() }
                    .reportIslandFrame(.playPause)
                Spacer()
                islandButton("goforward.10", label: "Forward 10 seconds") { now.skip(by: 10) }
                    .reportIslandFrame(.forward)
            }
        }
        .padding(APLiteDesign.Space.lg)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: APLiteDesign.Radius.lg, style: .continuous)) // taste:allow hand-glass system material required by spec
        .allowsHitTesting(true)
        .reportIslandFrame(.pill)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let image = now.item?.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        } else {
            Image(systemName: now.item?.isVideo == true ? "film" : "music.note")
                .font(.system(size: size * 0.48))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.28,
                                                               style: .continuous))
        }
    }

    private func islandButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: APLiteDesign.touchTarget, height: APLiteDesign.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var accessibilityLabel: Text {
        Text("\(now.item?.title ?? String(localized: "Now playing")), \(now.isPlaying ? String(localized: "playing") : String(localized: "paused"))")
    }

    private func islandTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct SpectrumBars: View {
    let levels: [Float]
    let count: Int
    let height: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                let level = index < levels.count ? levels[index] : 0
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: 3, height: max(2, height * CGFloat(level)))
                    .animation(APLiteAnimation.island, value: level)
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct IslandFramePreference: PreferenceKey {
    static var defaultValue: [NowPlayingService.Control: CGRect] { [:] }
    static func reduce(value: inout [NowPlayingService.Control: CGRect],
                       nextValue: () -> [NowPlayingService.Control: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ReportIslandFrame: ViewModifier {
    let control: NowPlayingService.Control
    func body(content: Content) -> some View {
        content.overlay(GeometryReader { geo in
            Color.clear.preference(key: IslandFramePreference.self,
                                   value: [control: geo.frame(in: .global)])
        })
    }
}

private extension View {
    func reportIslandFrame(_ control: NowPlayingService.Control) -> some View {
        modifier(ReportIslandFrame(control: control))
    }
}

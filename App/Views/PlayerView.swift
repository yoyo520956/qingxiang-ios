import AVFoundation
import SwiftUI

struct PlayerView: View {
    let item: MediaItem
    @ObservedObject var store: MediaStore
    @StateObject private var engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    @State private var isScrubbing = false
    @State private var dragAnchor: (kind: Int, initial: Double)? = nil
    @State private var hudIcon = ""
    @State private var hudText = ""
    @State private var flashTask: Task<Void, Never>?

    init(item: MediaItem, store: MediaStore) {
        self.item = item
        self.store = store
        _engine = StateObject(wrappedValue: PlayerEngine(item: item, store: store))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                PlayerLayerView(player: engine.player, gravity: engine.gravity)

                HStack(spacing: 0) {
                    band(0, width: geo.size.width, height: geo.size.height)
                    band(1, width: geo.size.width, height: geo.size.height)
                    band(2, width: geo.size.width, height: geo.size.height)
                }

                if !hudText.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: hudIcon)
                        Text(hudText)
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 56)
                }

                if engine.showControls {
                    topBar
                    bottomControls(width: geo.size.width)
                }
            }
            .onAppear {
                if !loaded {
                    loaded = true
                    engine.load(item)
                }
            }
            .onDisappear {
                engine.saveProgress()
            }
            .task(id: engine.isPlaying) {
                if engine.isPlaying, engine.showControls {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    if engine.showControls, engine.isPlaying {
                        engine.showControls = false
                    }
                }
            }
        }
        .statusBarHidden()
    }

    // MARK: - 手势三区块

    private func band(_ zone: Int, width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard Defaults.bool(SettingsKeys.gestureDoubleTap, fallback: true) else { return }
                switch zone {
                case 0:
                    engine.seekBy(-10)
                    flash("« 10s")
                case 2:
                    engine.seekBy(10)
                    flash("» 10s")
                default:
                    engine.togglePlay()
                    flash(engine.isPlaying ? "暂停" : "播放")
                }
            }
            .onTapGesture {
                engine.showControls.toggle()
            }
            .gesture(verticalDrag(height: height))
    }

    private func verticalDrag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { v in
                guard Defaults.bool(SettingsKeys.gestureVertical, fallback: true), height > 120 else { return }
                if dragAnchor == nil {
                    let kind = v.startLocation.y < height / 2 ? 0 : 1
                    let initial = kind == 0 ? engine.currentVolume : UIScreen.main.brightness
                    dragAnchor = (kind, initial)
                }
                guard let a = dragAnchor else { return }
                let delta = Double(-v.translation.height) / Double(height * 0.5)
                let value = min(1, max(0, a.1 + delta))
                if a.0 == 0 {
                    engine.setVolume(value)
                    hudIcon = "speaker.wave.2.fill"
                } else {
                    engine.setBrightness(value)
                    hudIcon = "sun.max.fill"
                }
                hudText = String(format: "%.0f%%", value * 100)
            }
            .onEnded { _ in
                dragAnchor = nil
                hudText = ""
                hudIcon = ""
            }
    }

    private func flash(_ text: String) {
        hudText = text
        hudIcon = "arrow.left.arrow.right"
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !Task.isCancelled {
                hudText = ""
                hudIcon = ""
            }
        }
    }

    // MARK: - 控制层

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title)
                }
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                Spacer()
                Button {
                    engine.gravity = engine.gravity == .resizeAspect ? .resizeAspectFill : .resizeAspect
                } label: {
                    Image(systemName: engine.gravity == .resizeAspect ? "rectangle" : "rectangle.inset.filled")
                        .font(.title3)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxHeight: 80, alignment: .top)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
    }

    private func bottomControls(width: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(isScrubbing ? timeString(engine.currentTime) : "")
                    .font(.caption)
                    .monospacedDigit()
                Spacer()
                if engine.rate != 1.0 {
                    Text(String(format: "%.2f×", engine.rate))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                if engine.duration > 0 {
                    Slider(
                        value: Binding(
                            get: { engine.currentTime },
                            set: { engine.seek(to: $0) }
                        ),
                        in: 0...max(engine.duration, 0.1)
                    ) { editing in
                        isScrubbing = editing
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                Text(timeString(engine.duration))
                    .font(.caption2)
                    .monospacedDigit()
            }
            HStack(spacing: 22) {
                Button { engine.seekBy(-10) } label: {
                    Image(systemName: "gobackward.10")
                }
                Button { engine.togglePlay() } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                Button { engine.seekBy(10) } label: {
                    Image(systemName: "goforward.10")
                }
                Menu {
                    ForEach(PlayerEngine.speeds, id: \.self) { s in
                        Button {
                            engine.setRate(s)
                        } label: {
                            HStack {
                                Text(s == 1.0 ? "正常" : String(format: "%.2f×", s))
                                if s == engine.rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "speedometer")
                }
            }
            .font(.title3)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxHeight: 110, alignment: .bottom)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
    }
}

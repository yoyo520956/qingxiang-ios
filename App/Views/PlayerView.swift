import AVKit
import SwiftUI

struct PlayerView: View {
    let item: MediaItem
    @ObservedObject var store: MediaStore
    @StateObject private var engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    @State private var discAngle: Angle = .zero

    init(item: MediaItem, store: MediaStore) {
        self.item = item
        self.store = store
        _engine = StateObject(wrappedValue: PlayerEngine(item: item, store: store))
    }

    var body: some View {
        Group {
            if item.isAudio {
                audioBody
            } else {
                videoBody
            }
        }
        .statusBarHidden()
    }

    // MARK: - 视频模式（系统控制层，界面正常）

    private var videoBody: some View {
        ZStack(alignment: .top) {
            VideoPlayer(player: engine.player)
                .ignoresSafeArea()

            topBar
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
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(item.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

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
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
    }


    // MARK: - 音频模式

    private var audioBody: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.darkGray), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()

                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 200, height: 200)
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        .rotationEffect(discAngle)
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text(item.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal)
                    Text(item.sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                audioControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
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
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            if engine.isPlaying {
                discAngle += .degrees(24)
            }
        }
    }

    private var audioControls: some View {
        VStack(spacing: 14) {
            HStack {
                Text(timeString(engine.currentTime))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if engine.duration > 0 {
                    Slider(
                        value: Binding(
                            get: { engine.currentTime },
                            set: { engine.seek(to: $0) }
                        ),
                        in: 0...max(engine.duration, 0.1)
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                Text(timeString(engine.duration))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 30) {
                Button { engine.seekBy(-10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }
                Button { engine.togglePlay() } label: {
                    Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                }
                Button { engine.seekBy(10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

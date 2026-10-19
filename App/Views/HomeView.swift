import SwiftUI

struct HomeView: View {
    @ObservedObject var store: MediaStore
    let onPlay: (MediaItem) -> Void
    let onDownload: (_ title: String, _ url: String, _ kind: String) -> Void

    private let content = HomeLibrary.load()

    private var continueItems: [MediaItem] {
        store.items.filter { $0.hasResumePoint && !($0.isAudio) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !continueItems.isEmpty {
                        continueSection
                    }
                    ForEach(Array(content.channels.enumerated()), id: \.element.id) { _, channel in
                        ChannelSection(
                            channel: channel,
                            tint: tint(for: channel.id),
                            onPlay: { item in
                                onPlay(item.asMediaItem)
                            },
                            onDownload: { item in
                                onDownload(title: item.title, url: item.url, kind: item.kind)
                            }
                        )
                    }
                    Label("内容全部来自公有领域 / CC 授权资源，无广告无追踪。片源与版权归属详见「设置」", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                .padding(.top, 8)
            }
            .navigationTitle("轻享影音")
        }
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("继续观看", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(continueItems) { item in
                        Button {
                            onPlay(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: item.isAudio ? "music.note" : "play.rectangle.fill")
                                    Text(item.title)
                                        .lineLimit(1)
                                }
                                ProgressView(value: Double(item.progressPercent), total: 100)
                                    .tint(.orange)
                                Text("已看 \(item.progressPercent)%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(width: 180, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func tint(for id: String) -> Color {
        switch id {
        case "featured": return .orange
        case "short": return .yellow
        case "anime": return .pink
        case "drama": return .blue
        case "comic": return .purple
        case "music": return .green
        default: return .gray
        }
    }
}

struct ChannelSection: View {
    let channel: HomeChannel
    let tint: Color
    let onPlay: (HomeItem) -> Void
    let onDownload: (HomeItem) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: channel.icon)
                    .foregroundStyle(tint)
                Text(channel.name)
                    .font(.headline)
                if let note = channel.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(channel.items) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    colors: [tint.opacity(0.55), tint.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                            Image(systemName: item.isAudio ? "music.note" : "play.circle.fill")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(.white.opacity(0.9))
                            if let n = item.note {
                                Text(n)
                                    .font(.caption2)
                                    .padding(.bottom, 6)
                                    .padding(.trailing, 8)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            }
                        }
                        .frame(height: 96)

                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                onDownload(item)
                            } label: {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(tint)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onPlay(item) }
                }
            }
            .padding(.horizontal)
        }
    }
}

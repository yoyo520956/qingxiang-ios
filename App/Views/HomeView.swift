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
                    SearchSection(onPlay: onPlay, onDownload: onDownload)

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
                                onDownload(item.title, item.url, item.kind)
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

struct SearchSection: View {
    let onPlay: (MediaItem) -> Void
    let onDownload: (_ title: String, _ url: String, _ kind: String) -> Void

    @State private var keyword = ""
    @State private var kind = "video"
    @State private var hits: [SearchHit] = []
    @State private var loading = false
    @State private var err: String?
    @State private var sourceId = "builtin"
    @State private var providers: [VideoProvider] = []

    private func visibleProviders() -> [VideoProvider] {
        ProviderStore.all().filter { $0.enabled && (!$0.adult || AdultGate.on) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜视频 / 音乐 / 短剧", text: $keyword)
                    .autocorrectionDisabled()
                if sourceId == "builtin" {
                    Picker("", selection: $kind) {
                        Text("视频").tag("video")
                        Text("音乐").tag("audio")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                Button {
                    doSearch()
                } label: {
                    loading ? AnyView(ProgressView()) : AnyView(Image(systemName: "arrow.right.circle.fill"))
                }
                .disabled(loading || keyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !providers.isEmpty {
                HStack(spacing: 6) {
                    Text("源")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(providers) { p in
                        Button(p.name) {
                            sourceId = p.id
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(sourceId == p.id ? Color.accentColor : Color(.systemGray5)))
                        .foregroundStyle(sourceId == p.id ? Color.white : Color.primary)
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Menu {
                    Button("内置：开放媒体库") { sourceId = "builtin" }
                    ForEach(providers) { p in
                        Button((p.adult ? "[18+] " : "") + p.name) {
                            sourceId = p.id
                        }
                    }
                } label: {
                    Label("切换搜索源", systemImage: "square.grid.2x2")
                        .font(.caption)
                }
                Spacer()
            }

            if let err {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(hits) { h in
                HStack(spacing: 8) {
                    Image(systemName: h.kind == "audio" ? "music.note" : "film")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text((h.kind == "audio" ? "音乐" : "视频") + (h.sizeMB > 0 ? " · \(h.sizeMB)MB" : ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        onDownload(h.title, h.url, h.kind)
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                    Button {
                        onPlay(toMediaItem(h))
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            }
        }
        .padding(.horizontal)
        .onAppear { providers = visibleProviders() }
    }

    private func toMediaItem(_ h: SearchHit) -> MediaItem {
        MediaItem(
            id: UUID(),
            title: h.title,
            fileURL: nil,
            remoteURL: h.url,
            createdAt: Date(),
            duration: nil,
            lastPosition: 0,
            isFavorite: false,
            sizeBytes: Int64(h.sizeMB) * 1024 * 1024,
            sourceLabel: "搜索 · " + (h.kind == "audio" ? "音乐" : (h.kind == "adult" ? "18+" : "视频"))
        )
    }

    private func doSearch() {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        loading = true
        err = nil
        providers = visibleProviders()
        Task {
            do {
                var r: [SearchHit]
                if sourceId == "builtin" {
                    r = try await MediaSearch.search(kw, type: kind)
                } else {
                    guard let p = providers.first(where: { $0.id == sourceId }) else {
                        err = "源不可用"
                        loading = false
                        return
                    }
                    r = (try? await ProviderKit.search(p, q: kw)) ?? []
                }
                hits = r
                if r.isEmpty {
                    err = "没搜到，换个词或换个源试试"
                }
                loading = false
            } catch {
                err = (error as? MediaSearch.SearchError)?.errorDescription ?? "搜索失败（需联网）"
                loading = false
            }
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

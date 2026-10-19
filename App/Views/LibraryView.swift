import SwiftUI

struct ThumbView: View {
    let path: String?
    @State private var img: UIImage?

    var body: some View {
        ZStack {
            if let img {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: 76, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear(perform: load)
    }

    private func load() {
        guard let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        img = UIImage(data: data)
    }
}

struct MediaRow: View {
    let item: MediaItem
    @ObservedObject var store: MediaStore

    var body: some View {
        HStack(spacing: 10) {
            ThumbView(path: store.thumbCache[item.id])
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.sourceLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let d = item.duration, d > 0 {
                        Text(timeString(d))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !item.isRemote, let s = item.sizeBytes {
                        Text(byteString(s))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if item.progressPercent > 0 {
                        Text("已看 \(item.progressPercent)%")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button {
                var m = item
                m.isFavorite.toggle()
                store.update(m)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct LibraryView: View {
    @ObservedObject var store: MediaStore
    let onPlay: (MediaItem) -> Void

    @State private var favOnly = false

    private var baseItems: [MediaItem] {
        favOnly ? store.items.filter { $0.isFavorite } : store.items
    }

    private var continueItems: [MediaItem] {
        baseItems.filter { $0.hasResumePoint && !$0.isRemote }
    }

    var body: some View {
        NavigationStack {
            List {
                if baseItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: favOnly ? "star" : "film")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(favOnly ? "还没有收藏，点击 ☆ 收藏后这里就会亮" : "片库是空的，去「加片」导入，或在首页直接看内置频道")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                } else {
                    if !favOnly, !continueItems.isEmpty {
                        Section("继续观看") {
                            ForEach(continueItems) { item in
                                rowFor(item)
                            }
                        }
                    }
                    Section("全部 \(baseItems.count)") {
                        ForEach(baseItems) { item in
                            rowFor(item)
                        }
                    }
                }
            }
            .navigationTitle(favOnly ? "收藏" : "片库")
            .toolbar {
                Button {
                    favOnly.toggle()
                } label: {
                    Image(systemName: favOnly ? "star.fill" : "star")
                        .foregroundStyle(favOnly ? .yellow : .secondary)
                }
            }
        }
    }

    private func rowFor(_ item: MediaItem) -> some View {
        MediaRow(item: item, store: store)
            .onTapGesture { onPlay(item) }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    store.remove(item)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
    }
}

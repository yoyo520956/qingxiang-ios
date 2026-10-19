import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AddView: View {
    @ObservedObject var store: MediaStore
    let onPlay: (MediaItem) -> Void

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var showFileImport = false
    @State private var urlString = ""
    @State private var notice: String?
    @State private var showNotice = false

    var body: some View {
        NavigationStack {
            Form {
                albumSection
                fileSection
                onlineSection
            }
            .navigationTitle("加片")
            .onChange(of: photoItems) { newItems in
                importPhotos(newItems)
            }
            .alert("提示", isPresented: $showNotice) {
                Button("好", role: .cancel) {}
            } message: {
                Text(notice ?? "")
            }
        }
    }

    @ViewBuilder
    private var albumSection: some View {
        Section("相册") {
            PhotosPicker(selection: $photoItems, matching: .videos, photoLibrary: .shared()) {
                HStack(spacing: 8) {
                    Image(systemName: "video.on.rectangle")
                    Text("从相册选择视频")
                }
            }
            .disabled(importing)
            if importing {
                HStack {
                    ProgressView()
                    Text("导入中…")
                }
            }
        }
    }

    @ViewBuilder
    private var fileSection: some View {
        Section("文件") {
            Button {
                showFileImport = true
            } label: {
                Label("导入视频文件", systemImage: "folder")
            }
        }
        .fileImporter(
            isPresented: $showFileImport,
            allowedContentTypes: [UTType.movie, .video, .quickTimeMovie, .threeGPPMovie],
            allowsMultipleSelection: true
        ) { result in
            handleFiles(result)
        }
    }

    @ViewBuilder
    private var onlineSection: some View {
        Section("在线链接") {
            TextField("http(s)://…/.mp4 或 .m3u8", text: $urlString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("添加在线片源") { addURL() }
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            Label("支持 MP4 / MOV / HLS(.m3u8) 等在线链接，长缓冲不卡顿", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        importing = true
        Task {
            var count = 0
            for it in items {
                if let data = try? await it.loadTransferable(type: Data.self), data.count > 1024 {
                    let ts = Int(Date().timeIntervalSince1970)
                    let name = "相册视频-\(ts)"
                    if let item = try? store.copyVideo(data: data, suggestedName: name, sourceLabel: "相册") {
                        count += 1
                        ThumbnailGen.generate(for: item) { path in
                            if let path {
                                store.thumbCache[item.id] = path
                            }
                        }
                    }
                }
            }
            photoItems = []
            importing = false
            if count > 0 {
                notice = "已导入 \(count) 个视频"
                showNotice = true
            }
        }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var count = 0
            for u in urls {
                let ok = u.startAccessingSecurityScopedResource()
                defer {
                    if ok { u.stopAccessingSecurityScopedResource() }
                }
                if let data = try? Data(contentsOf: u) {
                    if let item = try? store.copyVideo(data: data, suggestedName: u.lastPathComponent, sourceLabel: "文件") {
                        count += 1
                        ThumbnailGen.generate(for: item) { path in
                            if let path {
                                store.thumbCache[item.id] = path
                            }
                        }
                    }
                }
            }
            if count > 0 {
                notice = "已导入 \(count) 个视频"
                showNotice = true
            }
        case .failure:
            break
        }
    }

    private func addURL() {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.hasPrefix("http://"), !s.hasPrefix("https://") {
            s = "https://" + s
        }
        guard URL(string: s) != nil else {
            notice = "链接格式不对"
            showNotice = true
            return
        }
        let item = MediaItem(
            id: UUID(),
            title: s,
            fileURL: nil,
            remoteURL: s,
            createdAt: Date(),
            duration: nil,
            lastPosition: 0,
            isFavorite: false,
            sizeBytes: nil,
            sourceLabel: "在线"
        )
        store.add(item)
        urlString = ""
        notice = "已添加，去片库播放"
        showNotice = true
    }
}

import Foundation

final class MediaStore: ObservableObject {
    static let shared = MediaStore()

    @Published var items: [MediaItem] = []
    @Published var thumbCache: [UUID: String] = [:]

    let mediaDir: URL
    let libFile: URL

    private init() {
        let base = URL.applicationSupportDirectory
        mediaDir = base.appendingPathComponent("Media", isDirectory: true)
        libFile = mediaDir.appendingPathComponent("library.json")
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: libFile) {
            items = (try? JSONDecoder().decode([MediaItem].self, from: data)) ?? []
            items.sort { $0.createdAt > $1.createdAt }
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: libFile, options: .atomic)
        }
    }

    @discardableResult
    func add(_ item: MediaItem) -> MediaItem {
        items.insert(item, at: 0)
        save()
        return item
    }

    func update(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        save()
    }

    func remove(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        if !item.isRemote, let f = item.fileURL {
            try? FileManager.default.removeItem(at: f)
        }
        try? FileManager.default.removeItem(atPath: thumbPath(item.id))
        save()
    }

    func thumbPath(_ id: UUID) -> String {
        mediaDir.appendingPathComponent("thumb-\(id).jpg").path
    }

    func totalBytes() -> Int64 {
        items.compactMap { $0.sizeBytes }.reduce(0, +)
    }

    @discardableResult
    func copyVideo(data: Data, suggestedName: String, sourceLabel: String) throws -> MediaItem {
        let safe = suggestedName.replacingOccurrences(of: "/", with: "-")
        let fname = "vid-\(UUID().uuidString)-\(safe)"
        let dest = mediaDir.appendingPathComponent(fname)
        try data.write(to: dest, options: .atomic)
        let item = MediaItem(
            id: UUID(),
            title: suggestedName,
            fileURL: dest,
            remoteURL: nil,
            createdAt: Date(),
            duration: nil,
            lastPosition: 0,
            isFavorite: false,
            sizeBytes: Int64(data.count),
            sourceLabel: sourceLabel
        )
        return add(item)
    }

    func clearAll() {
        items.removeAll()
        save()
        try? FileManager.default.removeItem(at: mediaDir)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }
}

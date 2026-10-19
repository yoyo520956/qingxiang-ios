import Foundation

struct HomeItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let url: String
    let kind: String
    var note: String?

    var isAudio: Bool { kind == "audio" }

    var asMediaItem: MediaItem {
        MediaItem(
            id: UUID(),
            title: title,
            fileURL: nil,
            remoteURL: url,
            createdAt: Date(),
            duration: nil,
            lastPosition: 0,
            isFavorite: false,
            sizeBytes: nil,
            sourceLabel: "内置 · " + (isAudio ? "音乐" : "视频")
        )
    }
}

struct HomeChannel: Identifiable, Codable {
    let id: String
    let name: String
    let icon: String
    var note: String?
    let items: [HomeItem]
}

struct HomeContent: Codable {
    let channels: [HomeChannel]
}

enum HomeLibrary {
    static func load() -> HomeContent {
        guard let u = Bundle.main.url(forResource: "HomeContent", withExtension: "json"),
              let d = try? Data(contentsOf: u) else {
            return HomeContent(channels: [])
        }
        return (try? JSONDecoder().decode(HomeContent.self, from: d)) ?? HomeContent(channels: [])
    }
}

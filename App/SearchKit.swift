import Foundation

struct SearchHit: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let kind: String
    let sizeMB: Int
}

enum MediaSearch {
    struct SearchError: Error, LocalizedError {
        let msg: String
        var errorDescription: String? { msg }
    }

    /// 搜索最大开源媒体库 Wikimedia Commons（免费、无 key、公有/CC 授权）
    static func search(_ keyword: String, type: String) async throws -> [SearchHit] {
        let wantVideo = type == "video"

        var c1 = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        c1.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "list", value: "search"),
            .init(name: "srsearch", value: keyword + (wantVideo ? " filetype:video" : " filetype:audio")),
            .init(name: "srnamespace", value: "6"),
            .init(name: "srlimit", value: "15"),
            .init(name: "format", value: "json")
        ]
        guard let u1 = c1.url else { throw SearchError(msg: "链接无效") }
        let (data1, _) = try await URLSession.shared.data(from: u1)
        guard let root1 = try? JSONSerialization.jsonObject(with: data1) as? [String: Any],
              let query1 = root1["query"] as? [String: Any],
              let hits1 = query1["search"] as? [[String: Any]] else {
            return []
        }
        let titles = hits1.compactMap { $0["title"] as? String }.prefix(10)
        if titles.isEmpty {
            throw SearchError(msg: "没搜到，换个词试试")
        }

        var c2 = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        c2.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "titles", value: titles.joined(separator: "|")),
            .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url|size|mime"),
            .init(name: "format", value: "json")
        ]
        guard let u2 = c2.url else { throw SearchError(msg: "链接无效") }
        let (data2, _) = try await URLSession.shared.data(from: u2)
        guard let root2 = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
              let query2 = root2["query"] as? [String: Any],
              let pages = query2["pages"] as? [String: [String: Any]] else {
            return []
        }

        var out: [SearchHit] = []
        for (_, p) in pages {
            guard let ii = p["imageinfo"] as? [[String: Any]], let f = ii.first else { continue }
            let mime = (f["mime"] as? String) ?? ""
            let size = (f["size"] as? Double) ?? 0
            var url = (f["url"] as? String) ?? ""
            guard !url.isEmpty else { continue }
            if let qm = url.range(of: "?") {
                url = String(url[..<qm.lowerBound])
            }
            let isVideo = mime.contains("video") || mime == "application/ogg"
            let isAudio = mime.hasPrefix("audio/")
            if wantVideo && !isVideo { continue }
            if !wantVideo && !isAudio { continue }
            let capBytes: Double = wantVideo ? 500 * 1024 * 1024 : 50 * 1024 * 1024
            if size > 0 && size > capBytes { continue }
            let title = ((p["title"] as? String) ?? "未命名")
                .replacingOccurrences(of: "File:", with: "")
                .trimmingCharacters(in: .whitespaces)
            out.append(SearchHit(
                id: title + url,
                title: title,
                url: url,
                kind: wantVideo ? "video" : "audio",
                sizeMB: Int(size / 1024 / 1024)
            ))
        }
        return out
    }
}

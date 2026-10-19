import Foundation

/// 一个"在线视频源"：用户在设置里填 endpoint，App 负责搜索/播放/下载管线。
struct VideoProvider: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var endpoint: String   // URL 模板，{q} 为关键词占位符
    var key: String?       // 可选鉴权 key
    var adult: Bool        // 是否成人源（需 18+ 锁）
    var enabled: Bool
}

enum ProviderStore {
    static func all() -> [VideoProvider] {
        let url = URL.applicationSupportDirectory.appendingPathComponent("providers.json")
        guard let d = try? Data(contentsOf: url) else { return presets }
        return (try? JSONDecoder().decode([VideoProvider].self, from: d)) ?? presets
    }

    static func save(_ list: [VideoProvider]) {
        let url = URL.applicationSupportDirectory.appendingPathComponent("providers.json")
        if let d = try? JSONEncoder().encode(list) {
            try? d.write(to: url, options: .atomic)
        }
    }

    static var presets: [VideoProvider] {
        [
            VideoProvider(
                id: "commons",
                name: "Wikimedia Commons（内置，免费）",
                endpoint: "https://commons.wikimedia.org/w/api.php?action=query&list=search&srsearch={q}%20filetype:video&srnamespace=6&format=json",
                key: nil,
                adult: false,
                enabled: true
            ),
            VideoProvider(
                id: "archive",
                name: "Internet Archive（最大片库，免 key）",
                endpoint: "archive://movies",
                key: nil,
                adult: false,
                enabled: true
            ),
            VideoProvider(
                id: "iptv-movies",
                name: "IPTV 电影频道（iptv-org）",
                endpoint: "m3u://https://iptv-org.github.io/iptv/categories/movies.m3u",
                key: nil,
                adult: false,
                enabled: true
            ),
            VideoProvider(
                id: "iptv-music",
                name: "IPTV 音乐频道（iptv-org）",
                endpoint: "m3u://https://iptv-org.github.io/iptv/categories/music.m3u",
                key: nil,
                adult: false,
                enabled: true
            ),
            VideoProvider(
                id: "iptv-doc",
                name: "IPTV 纪录片（iptv-org）",
                endpoint: "m3u://https://iptv-org.github.io/iptv/categories/documentary.m3u",
                key: nil,
                adult: false,
                enabled: true
            ),
            VideoProvider(
                id: "iptv-anim",
                name: "IPTV 动画频道（iptv-org）",
                endpoint: "m3u://https://iptv-org.github.io/iptv/categories/animation.m3u",
                key: nil,
                adult: false,
                enabled: true
            )
        ]
    }
}

/// 18+ 锁（设置里手动开）
enum AdultGate {
    private static let k = "adultGate18"
    static var on: Bool {
        get { UserDefaults.standard.bool(forKey: k) }
        set { UserDefaults.standard.set(newValue, forKey: k) }
    }
}

/// 走在线源搜索，归一化成 SearchHit
enum ProviderKit {
    static func search(_ p: VideoProvider, q: String) async throws -> [SearchHit] {
        // 内置 Internet Archive：两步（搜索 → 取可播文件直链）
        if p.endpoint.hasPrefix("archive://") {
            return try await archiveSearch(q)
        }
        // M3U / IPTV 播放列表源
        if p.endpoint.hasPrefix("m3u://") {
            return try await m3uSearch(p, q: q)
        }
        let kw = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        var ep = p.endpoint.replacingOccurrences(of: "{q}", with: kw)
        if let key = p.key, !key.isEmpty {
            ep += (ep.contains("?") ? "&" : "?") + "key=" + key
        }
        guard let url = URL(string: ep) else {
            throw MediaSearch.SearchError(msg: "接口地址无效")
        }
        var req = URLRequest(url: url)
        req.setValue("application/json, text/html;q=0.9", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw MediaSearch.SearchError(msg: "源没有返回可解析的数据")
        }
        return normalize(root, provider: p)
    }

    // MARK: - M3U / IPTV 播放列表源

    private static func m3uSearch(_ p: VideoProvider, q: String) async throws -> [SearchHit] {
        let listURL = String(p.endpoint.dropFirst("m3u://".count))
        let items = try await M3UParser.fetch(listURL)
        let kw = q.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [M3UItem]
        if kw.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { $0.title.lowercased().contains(kw) || ($0.group ?? "").lowercased().contains(kw) }
        }
        if filtered.isEmpty {
            throw MediaSearch.SearchError(msg: "没搜到，换个词试试（列表共 \(items.count) 个频道）")
        }
        return filtered.prefix(60).map { it in
            SearchHit(id: it.id, title: it.title, url: it.url, kind: "video", sizeMB: 0)
        }
    }

    // MARK: - Internet Archive（两步：搜索条目 → 取首个可播文件）

    private static func archiveSearch(_ q: String) async throws -> [SearchHit] {
        let kw = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard let searchURL = URL(string: "https://archive.org/advancedsearch.php?q=\(kw)&mediatype=movies&rows=6&fl%5B%5D=identifier&fl%5B%5D=title&output=json") else {
            throw MediaSearch.SearchError(msg: "链接无效")
        }
        let (data, _) = try await URLSession.shared.data(from: searchURL)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = root["response"] as? [String: Any],
              let docs = resp["docs"] as? [[String: Any]] else {
            throw MediaSearch.SearchError(msg: "Internet Archive 连接失败（请检查网络）")
        }

        var hits: [SearchHit] = []
        for doc in docs.prefix(5) {
            guard let id = doc["identifier"] as? String else { continue }
            let title = (doc["title"] as? String) ?? id
            guard let metaURL = URL(string: "https://archive.org/metadata/\(id)") else { continue }
            guard let (mdata, _) = try? await URLSession.shared.data(from: metaURL),
                  let mroot = try? JSONSerialization.jsonObject(with: mdata) as? [String: Any],
                  let files = mroot["files"] as? [[String: Any]] else { continue }

            // 找第一个可播视频文件（优先 mp4 / ogv / webm）
            for f in files {
                guard let name = f["name"] as? String else { continue }
                let lower = name.lowercased()
                let playable = lower.hasSuffix(".mp4") || lower.hasSuffix(".ogv")
                    || lower.hasSuffix(".webm") || lower.hasSuffix(".m4v")
                    || lower.hasSuffix(".mov")
                guard playable else { continue }
                let sizeBytes = Double((f["size"] as? String).flatMap { Double($0) } ?? (f["size"] as? Double) ?? 0)
                hits.append(SearchHit(
                    id: title + name,
                    title: title,
                    url: "https://archive.org/download/\(id)/\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)",
                    kind: "video",
                    sizeMB: Int(sizeBytes / 1024 / 1024)
                ))
                break
            }
            if hits.count >= 5 { break }
        }
        if hits.isEmpty {
            throw MediaSearch.SearchError(msg: "没搜到可播放的条目")
        }
        return hits
    }

    /// 兼容多种返回结构：根是数组 / {results:[]} / {data:[]} / Commons 的 {query:{search:[]}}
    private static func normalize(_ root: Any, provider: VideoProvider) -> [SearchHit] {
        let kind = provider.adult ? "adult" : "video"
        var array: [[String: Any]]?
        if let a = root as? [[String: Any]] {
            array = a
        } else if let obj = root as? [String: Any] {
            for key in ["results", "data", "items", "videos", "media"] {
                if let a = obj[key] as? [[String: Any]] {
                    array = a
                    break
                }
            }
            // Commons 结构
            if array == nil,
               let query = obj["query"] as? [String: Any],
               let a = query["search"] as? [[String: Any]] {
                array = a
            }
        }
        guard let arr = array else { return [] }

        return arr.prefix(30).compactMap { item in
            // 字段名做多套兜底
            let title = (item["title"] ?? item["name"] ?? item["text"]) as? String ?? "未命名"
            var link = (item["url"] ?? item["src"] ?? item["link"] ?? item["file"] ?? item["source"]) as? String
            if link == nil, let t = item["title"] as? String, let idv = item["identifier"] as? String {
                // Internet Archive 形态
                link = "https://archive.org/download/\(idv)/"
            }
            guard let raw = link, !raw.isEmpty else { return nil }
            var u = URLComponents(string: raw)
            // 跳过明显不是直链的（.html 页面）
            let host = u?.host ?? ""
            _ = host
            let path = u?.path ?? ""
            let looksDirect = path.hasSuffix(".mp4") || path.hasSuffix(".m3u8")
                || path.hasSuffix(".webm") || path.hasSuffix(".ogv")
                || path.hasSuffix(".ogg") || path.hasSuffix(".mp3") || path.hasSuffix(".m4v")
                || path.hasSuffix(".mov")
            // 允许含 /download/ 的 archive.org 直链
            let isArchiveDirect = raw.contains("archive.org/download")
            if !looksDirect && !isArchiveDirect {
                return nil
            }
            let sizeMB = ((item["size"] as? Double) ?? 0) / 1024 / 1024
            return SearchHit(
                id: title + raw,
                title: title,
                url: raw,
                kind: kind,
                sizeMB: Int(sizeMB)
            )
        }
    }
}

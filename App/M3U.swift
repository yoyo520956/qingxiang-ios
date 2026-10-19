import Foundation

struct M3UItem: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let logo: String?
    let group: String?
}

/// M3U / M3U8 播放列表解析器（#EXTM3U / #EXTINF 格式）
enum M3UParser {
    static func parse(_ text: String) -> [M3UItem] {
        var out: [M3UItem] = []
        var pendingTitle = ""
        var pendingLogo: String?
        var pendingGroup: String?

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF:") {
                // #EXTINF:-1 tvg-logo="..." group-title="...",频道名
                let body = String(line.dropFirst("#EXTINF:".count))
                // 属性解析
                var logo: String?
                var group: String?
                for attr in ["tvg-logo", "group-title"] {
                    if let r = body.range(of: "\(attr)=\"", options: .regularExpression) {
                        let rest = body[r.upperBound...]
                        if let end = rest.range(of: "\"") {
                            let val = String(rest[..<end.lowerBound])
                            if attr == "tvg-logo" { logo = val } else { group = val }
                        }
                    }
                }
                // 标题 = 最后一个逗号后的内容
                let titlePart: String
                if let comma = body.range(of: ",", options: .backwards) {
                    titlePart = String(body[comma.upperBound...]).trimmingCharacters(in: .whitespaces)
                } else {
                    titlePart = body.trimmingCharacters(in: .whitespaces)
                }
                pendingTitle = titlePart.isEmpty ? "未命名" : titlePart
                pendingLogo = logo
                pendingGroup = group
            } else if line.hasPrefix("#") {
                // 其他注释行，跳过
                continue
            } else {
                // 这是流 URL
                let url = line
                guard url.hasPrefix("http://") || url.hasPrefix("https://") || url.hasPrefix("rtmp://") else { continue }
                out.append(M3UItem(
                    id: pendingTitle + url,
                    title: pendingTitle,
                    url: url,
                    logo: pendingLogo,
                    group: pendingGroup
                ))
                pendingTitle = ""
                pendingLogo = nil
                pendingGroup = nil
            }
        }
        return out
    }

    static func fetch(_ urlString: String) async throws -> [M3UItem] {
        guard let url = URL(string: urlString) else {
            throw MediaSearch.SearchError(msg: "M3U 地址无效")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw MediaSearch.SearchError(msg: "M3U 内容无法解码")
        }
        let items = parse(text)
        if items.isEmpty {
            throw MediaSearch.SearchError(msg: "M3U 里没有可播的频道")
        }
        return items
    }
}

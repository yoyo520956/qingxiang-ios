import Foundation

struct MediaItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var fileURL: URL?
    var remoteURL: String?
    var createdAt: Date
    var duration: Double?
    var lastPosition: Double
    var isFavorite: Bool
    var sizeBytes: Int64?
    var sourceLabel: String

    var isRemote: Bool { remoteURL != nil }

    var resolvedURL: URL? {
        if let r = remoteURL { return URL(string: r) }
        return fileURL
    }

    var progressPercent: Int {
        guard let d = duration, d > 1, lastPosition > 0 else { return 0 }
        return Int(min(99, (lastPosition / d) * 100))
    }

    var hasResumePoint: Bool { lastPosition > 2 }
}

func timeString(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "00:00" }
    let total = Int(s)
    let h = total / 3600
    let m = (total % 3600) / 60
    let sec = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
    return String(format: "%02d:%02d", m, sec)
}

func byteString(_ n: Int64?) -> String {
    guard let n, n > 0 else { return "" }
    let m = Double(n) / 1_048_576.0
    if m >= 1024 {
        return String(format: "%.1f GB", m / 1024)
    }
    return String(format: "%.1f MB", m)
}

enum SettingsKeys {
    static let defaultRate = "defaultRate"
    static let resumePlayback = "resumePlayback"
    static let gestureDoubleTap = "gestureDoubleTap"
    static let gestureVertical = "gestureVertical"
}

enum Defaults {
    static func defaultRate() -> Float {
        let v = UserDefaults.standard.float(forKey: SettingsKeys.defaultRate)
        return v == 0 ? 1.0 : v
    }
    static func bool(_ key: String, fallback: Bool) -> Bool {
        return UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.bool(forKey: key)
    }
}

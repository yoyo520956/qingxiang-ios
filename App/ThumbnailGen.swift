import AVFoundation
import UIKit

enum ThumbnailGen {
    static func ensureAll(for store: MediaStore) {
        for item in store.items where item.fileURL != nil {
            let p = store.thumbPath(item.id)
            if !FileManager.default.fileExists(atPath: p) {
                generate(for: item) { path in
                    if let path {
                        store.thumbCache[item.id] = path
                    }
                }
            }
        }
    }

    static func generate(for item: MediaItem, completion: @escaping (String?) -> Void) {
        guard let url = item.resolvedURL else {
            completion(nil)
            return
        }
        let asset = AVURLAsset(url: url)
        let path = MediaStore.shared.thumbPath(item.id)
        Task {
            do {
                let dur = try await asset.load(.duration)
                let t = CMTime(seconds: dur.seconds > 2 ? 1.0 : max(0.1, dur.seconds / 2), preferredTimescale: 600)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 640, height: 640)
                let (cg, _) = try await gen.image(at: t)
                let ui = UIImage(cgImage: cg)
                if let data = ui.jpegData(compressionQuality: 0.7) {
                    try data.write(to: URL(fileURLWithPath: path))
                    completion(path)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
    }
}

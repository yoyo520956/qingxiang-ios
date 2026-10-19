import AVFoundation
import Foundation

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    enum Status: String, Codable {
        case queued, downloading, paused, complete, cancelled, failed, interrupted
    }

    struct Entry: Identifiable, Codable {
        let id: String
        var title: String
        var url: String
        var kind: String
        var status: Status
        var progress: Double
        var localPath: String?
        var failMsg: String?
        var libraryItemId: String?
    }

    @Published var entries: [Entry] = []

    private var assetTasks: [String: AVAssetDownloadTask] = [:]
    private var taskForEntry: [ObjectIdentifier: String] = [:]
    private var httpTasks: [String: URLSessionDownloadTask] = [:]
    private var progressObs: [String: NSKeyValueObservation] = [:]
    private let session: URLSession
    private let downloadsDir: URL
    private let tmpDir: URL
    private let metaFile: URL

    private override init() {
        let base = URL.applicationSupportDirectory
        downloadsDir = base.appendingPathComponent("Downloads", isDirectory: true)
        tmpDir = base.appendingPathComponent("DownloadTmp", isDirectory: true)
        metaFile = base.appendingPathComponent("downloads.json")
        super.init()
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        loadMeta()
    }

    // MARK: - 持久化

    private func loadMeta() {
        if let d = try? Data(contentsOf: metaFile) {
            entries = (try? JSONDecoder().decode([Entry].self, from: d)) ?? []
            for i in entries.indices where entries[i].status == .downloading || entries[i].status == .paused || entries[i].status == .queued {
                entries[i].status = .interrupted
            }
        }
    }

    private func saveMeta() {
        if let d = try? JSONEncoder().encode(entries) {
            try? d.write(to: metaFile, options: .atomic)
        }
    }

    // MARK: - 操作

    func start(title: String, url: String, kind: String) {
        let id = UUID().uuidString
        let entry = Entry(id: id, title: title, url: url, kind: kind, status: .queued, progress: 0, localPath: nil, failMsg: nil, libraryItemId: nil)
        entries.insert(entry, at: 0)
        saveMeta()
        run(id)
    }

    func retry(_ id: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].status = .queued
        entries[idx].progress = 0
        entries[idx].failMsg = nil
        saveMeta()
        run(id)
    }

    func pause(_ id: String) {
        assetTasks[id]?.pause()
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].status = .paused
        saveMeta()
    }

    func resume(_ id: String) {
        guard let task = assetTasks[id] else {
            retry(id)
            return
        }
        task.resume()
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].status = .downloading
        saveMeta()
    }

    func cancel(_ id: String) {
        assetTasks[id]?.cancel()
        httpTasks[id]?.cancel()
        progressObs.removeValue(forKey: id)?.invalidate()
        assetTasks.removeValue(forKey: id)
        httpTasks.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: tmpDir.appendingPathComponent(id + ".mp4"))
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].status = .cancelled
        saveMeta()
    }

    func delete(_ id: String) {
        cancel(id)
        if let e = entries.first(where: { $0.id == id }), let p = e.localPath {
            try? FileManager.default.removeItem(atPath: p)
        }
        entries.removeAll { $0.id == id }
        saveMeta()
    }

    func mediaItem(for id: String) -> MediaItem? {
        guard let e = entries.first(where: { $0.id == id }),
              FileManager.default.fileExists(atPath: e.localPath ?? "") else { return nil }
        if let libId = e.libraryItemId, let uuid = UUID(uuidString: libId) {
            return MediaStore.shared.item(withID: uuid)
        }
        // 兜底：老数据没存 id 的补注册一次
        let item = MediaStore.shared.adopt(file: URL(fileURLWithPath: e.localPath!), title: e.title, sourceLabel: "已下载")
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].libraryItemId = item.id.uuidString
            saveMeta()
        }
        return item
    }

    // MARK: - 执行

    private func run(_ id: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        guard let u = URL(string: entries[idx].url) else {
            fail(id, "链接无效")
            return
        }
        entries[idx].status = .downloading
        saveMeta()
        if entries[idx].kind == "audio" {
            startHTTP(id, url: u)
        } else {
            startAsset(id, url: u)
        }
    }

    private func startAsset(_ id: String, url: URL) {
        let asset = AVURLAsset(url: url)
        let dest = tmpDir.appendingPathComponent(id + ".mp4")
        do {
            let task = try asset.downloadTask(for: dest)
            assetTasks[id] = task
            taskForEntry[ObjectIdentifier(task)] = id
            task.delegate = self
            task.start()
            progressObs[id]?.invalidate()
            progressObs[id] = task.observe(\.progress) { [weak self] t, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let i = self.entries.firstIndex(where: { $0.id == id }) {
                        self.entries[i].progress = Double(t.progress)
                    }
                }
            }
        } catch {
            fail(id, "无法启动下载任务")
        }
    }

    private func startHTTP(_ id: String, url: URL) {
        let t = session.downloadTask(with: url)
        t.taskDescription = id
        httpTasks[id] = t
        t.resume()
    }

    private func fail(_ id: String, _ msg: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].status = .failed
        entries[idx].failMsg = msg
        saveMeta()
    }

    private func finish(id: String, fileFrom: URL?, suggestedName: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let ext = suggestedName.pathExtension.isEmpty ? "mp4" : suggestedName.pathExtension
        let finalURL = downloadsDir.appendingPathComponent(entries[idx].id + "." + ext)
        if let src = fileFrom {
            do {
                try? FileManager.default.removeItem(at: finalURL)
                try FileManager.default.moveItem(at: src, to: finalURL)
            } catch {
                fail(id, "文件移动失败")
                return
            }
        }
        progressObs.removeValue(forKey: id)?.invalidate()
        assetTasks.removeValue(forKey: id)
        httpTasks.removeValue(forKey: id)
        entries[idx].status = .complete
        entries[idx].progress = 1
        entries[idx].localPath = finalURL.path
        saveMeta()
        // 注册进片库
        let item = MediaStore.shared.adopt(file: finalURL, title: entries[idx].title, sourceLabel: "已下载")
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].libraryItemId = item.id.uuidString
        }
        saveMeta()
        ThumbnailGen.generate(for: item) { path in
            if let path {
                MediaStore.shared.thumbCache[item.id] = path
            }
        }
    }
}

// MARK: - AVAssetDownloadTaskDelegate

extension DownloadManager: AVAssetDownloadTaskDelegate {
    func assetDownloadTask(_ task: AVAssetDownloadTask, didFinishTo fileURL: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let id = self.taskForEntry[ObjectIdentifier(task)] {
                self.finish(id: id, fileFrom: fileURL, suggestedName: fileURL.deletingPathExtension().appendingPathExtension("mp4").lastPathComponent)
            }
        }
    }

    func assetDownloadTask(_ task: AVAssetDownloadTask, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let id = self.taskForEntry[ObjectIdentifier(task)] {
                self.fail(id, error.localizedDescription)
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWrite bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
            self.entries[i].progress = p
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let ext = location.pathExtension.isEmpty ? "mp3" : location.pathExtension
        DispatchQueue.main.async { [weak self] in
            self?.finish(id: id, fileFrom: location, suggestedName: "audio.\(ext)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error else { return }
        DispatchQueue.main.async { [weak self] in
            self?.fail(id, error.localizedDescription)
        }
    }
}

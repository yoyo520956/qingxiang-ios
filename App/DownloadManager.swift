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
        var resumeData: Data?
    }

    @Published var entries: [Entry] = []

    private var httpTasks: [String: URLSessionDownloadTask] = [:]
    private lazy var session: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
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
        if url.hasSuffix(".m3u8") || url.contains(".m3u8") {
            let id = UUID().uuidString
            let entry = Entry(id: id, title: title, url: url, kind: kind, status: .failed, progress: 0, localPath: nil, failMsg: "HLS 在线源暂不支持下载，仅支持在线播放", libraryItemId: nil, resumeData: nil)
            entries.insert(entry, at: 0)
            saveMeta()
            return
        }
        let id = UUID().uuidString
        let entry = Entry(id: id, title: title, url: url, kind: kind, status: .queued, progress: 0, localPath: nil, failMsg: nil, libraryItemId: nil, resumeData: nil)
        entries.insert(entry, at: 0)
        saveMeta()
        run(id, withResume: false)
    }

    func retry(_ id: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].progress = 0
        entries[idx].failMsg = nil
        saveMeta()
        run(id, withResume: false)
    }

    func pause(_ id: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }),
              let task = httpTasks[id] else { return }
        task.cancel(byProducingResumeData: { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                if let i = self.entries.firstIndex(where: { $0.id == id }) {
                    self.entries[i].status = .paused
                    self.entries[i].resumeData = data
                    self.httpTasks.removeValue(forKey: id)
                    self.saveMeta()
                }
            }
        })
    }

    func resume(_ id: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        run(id, withResume: entries[idx].resumeData != nil)
    }

    func cancel(_ id: String) {
        if let task = httpTasks[id] {
            task.cancel()
        }
        httpTasks.removeValue(forKey: id)
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].status = .cancelled
        entries[idx].resumeData = nil
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
              let p = e.localPath,
              FileManager.default.fileExists(atPath: p) else { return nil }
        if let libId = e.libraryItemId, let uuid = UUID(uuidString: libId) {
            return MediaStore.shared.item(withID: uuid)
        }
        let item = MediaStore.shared.adopt(file: URL(fileURLWithPath: p), title: e.title, sourceLabel: "已下载")
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].libraryItemId = item.id.uuidString
            saveMeta()
        }
        return item
    }

    // MARK: - 执行

    private func run(_ id: String, withResume: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        guard let u = URL(string: entries[idx].url) else {
            fail(id, "链接无效")
            return
        }
        let task: URLSessionDownloadTask
        if withResume, let rd = entries[idx].resumeData {
            task = session.downloadTask(withResumeData: rd)
        } else {
            task = session.downloadTask(with: u)
        }
        task.taskDescription = id
        httpTasks[id] = task
        entries[idx].status = .downloading
        if withResume {
            entries[idx].progress = 0
        }
        saveMeta()
        task.resume()
    }

    private func fail(_ id: String, _ msg: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].status = .failed
        entries[idx].failMsg = msg
        httpTasks.removeValue(forKey: id)
        saveMeta()
    }

    private func finish(id: String, fileFrom: URL) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let ext = URL(string: entries[idx].url)?.pathExtension ?? ""
        let finalExt = ext.isEmpty ? (entries[idx].kind == "audio" ? "mp3" : "mp4") : ext
        let finalURL = downloadsDir.appendingPathComponent(entries[idx].id + "." + finalExt)
        do {
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: fileFrom, to: finalURL)
        } catch {
            fail(id, "文件移动失败")
            return
        }
        httpTasks.removeValue(forKey: id)
        entries[idx].status = .complete
        entries[idx].progress = 1
        entries[idx].localPath = finalURL.path
        entries[idx].resumeData = nil
        saveMeta()
        let item = MediaStore.shared.adopt(file: finalURL, title: entries[idx].title, sourceLabel: "已下载")
        entries[idx].libraryItemId = item.id.uuidString
        saveMeta()
        if entries[idx].kind != "audio" {
            ThumbnailGen.generate(for: item) { path in
                if let path {
                    MediaStore.shared.thumbCache[item.id] = path
                }
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWrite bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        if totalBytesExpectedToWrite > 0 {
            let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async { [weak self] in
                guard let self, let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
                self.entries[i].progress = min(1.0, p)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        DispatchQueue.main.async { [weak self] in
            self?.finish(id: id, fileFrom: location)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error else { return }
        if (error as NSError).code == NSURLErrorCancelled {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.fail(id, error.localizedDescription)
        }
    }
}

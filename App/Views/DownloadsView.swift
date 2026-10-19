import SwiftUI

struct DownloadsView: View {
    @ObservedObject var store: MediaStore
    @StateObject private var dm = DownloadManager.shared
    let onPlay: (MediaItem) -> Void

    private var active: [DownloadManager.Entry] {
        dm.entries.filter { $0.status == .downloading || $0.status == .paused || $0.status == .queued }
    }
    private var done: [DownloadManager.Entry] {
        dm.entries.filter { $0.status == .complete }
    }
    private var bad: [DownloadManager.Entry] {
        dm.entries.filter { $0.status == .failed || $0.status == .interrupted || $0.status == .cancelled }
    }

    var body: some View {
        NavigationStack {
            Group {
                if dm.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        if !active.isEmpty {
                            Section("进行中") {
                                ForEach(active) { row($0, section: .active) }
                            }
                        }
                        if !done.isEmpty {
                            Section("已完成") {
                                ForEach(done) { row($0, section: .done) }
                            }
                        }
                        if !bad.isEmpty {
                            Section("未成功") {
                                ForEach(bad) { row($0, section: .bad) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("下载")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有下载\n在首页点卡片右下角的 ↓ 即可下载片源离线看")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum SectionKind { case active, done, bad }

    @ViewBuilder
    private func row(_ e: DownloadManager.Entry, section: SectionKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: e.kind == "audio" ? "music.note" : "film")
                    .foregroundStyle(.secondary)
                Text(e.title)
                    .lineLimit(1)
                Spacer()
                if e.status == .complete, let m = dm.mediaItem(for: e.id) {
                    Button {
                        onPlay(m)
                    } label: {
                        Image(systemName: "play.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            if section == .active {
                HStack(spacing: 10) {
                    ProgressView(value: e.progress)
                    Text(percentText(e.progress))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    if e.status == .downloading {
                        Button("暂停") { dm.pause(e.id) }
                    }
                    if e.status == .paused {
                        Button("继续") { dm.resume(e.id) }
                    }
                    Button("取消") { dm.cancel(e.id) }
                }
                .font(.caption)
            }
            if let msg = e.failMsg, section == .bad {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            if section == .done {
                Text(e.localPath ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .swipeActions(edge: .trailing) {
            if section == .done {
                Button(role: .destructive) {
                    dm.delete(e.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            if section == .bad {
                Button {
                    dm.retry(e.id)
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .tint(.orange)
            }
        }
    }

    private func percentText(_ p: Double) -> String {
        String(format: "%.0f%%", p * 100)
    }
}

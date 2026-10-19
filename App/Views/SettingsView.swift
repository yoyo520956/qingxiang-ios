import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MediaStore

    @State private var defaultRate: Float
    @State private var resume = true
    @State private var doubleTap = true
    @State private var vertical = true
    @State private var showClearAlert = false

    init(store: MediaStore) {
        self.store = store
        _defaultRate = State(initialValue: Defaults.defaultRate())
        _resume = State(initialValue: Defaults.bool(SettingsKeys.resumePlayback, fallback: true))
        _doubleTap = State(initialValue: Defaults.bool(SettingsKeys.gestureDoubleTap, fallback: true))
        _vertical = State(initialValue: Defaults.bool(SettingsKeys.gestureVertical, fallback: true))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("播放") {
                    Menu {
                        ForEach(PlayerEngine.speeds, id: \.self) { s in
                            Button {
                                setRate(s)
                            } label: {
                                HStack {
                                    Text(s == 1.0 ? "正常" : String(format: "%.2f×", s))
                                    if s == defaultRate {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        LabeledContent("默认倍速", value: defaultRate == 1.0 ? "正常" : String(format: "%.2f×", defaultRate))
                    }
                    Toggle("续播进度（从上次看到的地方继续）", isOn: $resume)
                        .onChange(of: resume) { v in
                            UserDefaults.standard.set(v, forKey: SettingsKeys.resumePlayback)
                        }
                    Toggle("双击快进 / 快退 10 秒", isOn: $doubleTap)
                        .onChange(of: doubleTap) { v in
                            UserDefaults.standard.set(v, forKey: SettingsKeys.gestureDoubleTap)
                        }
                    Toggle("竖滑调亮度 / 音量", isOn: $vertical)
                        .onChange(of: vertical) { v in
                            UserDefaults.standard.set(v, forKey: SettingsKeys.gestureVertical)
                        }
                }
                Section("数据") {
                    LabeledContent("片库占用", value: store.totalBytes() > 0 ? byteString(store.totalBytes()) : "0 MB")
                    LabeledContent("媒体数量", value: "\(store.items.count)")
                    Button("清除全部片库", role: .destructive) {
                        showClearAlert = true
                    }
                }
                Section("内容来源") {
                    LabeledContent("内置片源", value: "test-videos.co.uk · CC 公有领域")
                    LabeledContent("内置音乐", value: "Wikimedia Commons · 公有领域")
                    Label("内置频道免导入即看；想要别的片源去「加片」贴在线链接，或用下载中心存到本地", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("关于") {
                    LabeledContent("版本", value: "2.0.0 (20261020.02)")
                    LabeledContent("免费说明", value: "完全免费 · 无广告 · 无追踪")
                    Label("本地视频免流播放；在线链接走 60 秒长缓冲，播放不卡顿", systemImage: "bolt.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .alert("确认清除全部片库？", isPresented: $showClearAlert) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    store.clearAll()
                }
            } message: {
                Text("将删除全部本地视频与观看记录，此操作不可恢复")
            }
        }
    }

    private func setRate(_ s: Float) {
        defaultRate = s
        UserDefaults.standard.set(s, forKey: SettingsKeys.defaultRate)
    }
}

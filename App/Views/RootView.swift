import SwiftUI

struct RootView: View {
    @StateObject private var store = MediaStore.shared
    @State private var playing: MediaItem?
    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView(
                store: store,
                onPlay: { playing = $0 },
                onDownload: { title, url, kind in
                    DownloadManager.shared.start(title: title, url: url, kind: kind)
                }
            )
            .tabItem { Label("首页", systemImage: "house.fill") }
            .tag(0)

            LibraryView(store: store, onPlay: { playing = $0 })
                .tabItem { Label("片库", systemImage: "play.rectangle.on.rectangle") }
                .tag(1)

            AddView(store: store, onPlay: { playing = $0 })
                .tabItem { Label("加片", systemImage: "plus.circle") }
                .tag(2)

            DownloadsView(store: store, onPlay: { playing = $0 })
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }
                .tag(3)

            SettingsView(store: store)
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(4)
        }
        .fullScreenCover(item: $playing) { item in
            PlayerView(item: item, store: store)
        }
        .task {
            ThumbnailGen.ensureAll(for: store)
        }
    }
}

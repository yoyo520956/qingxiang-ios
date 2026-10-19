import SwiftUI

struct RootView: View {
    @StateObject private var store = MediaStore.shared
    @State private var playing: MediaItem?

    var body: some View {
        TabView {
            LibraryView(store: store, showFavorites: false, onPlay: { playing = $0 })
                .tabItem { Label("片库", systemImage: "play.rectangle.on.rectangle") }

            AddView(store: store, onPlay: { playing = $0 })
                .tabItem { Label("加片", systemImage: "plus.circle") }

            LibraryView(store: store, showFavorites: true, onPlay: { playing = $0 })
                .tabItem { Label("收藏", systemImage: "star") }

            SettingsView(store: store)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .fullScreenCover(item: $playing) { item in
            PlayerView(item: item, store: store)
        }
        .task {
            ThumbnailGen.ensureAll(for: store)
        }
    }
}

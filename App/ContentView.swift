import SwiftUI

struct ContentView: View {
  @Environment(LibraryStore.self) private var library

  var body: some View {
    TabView {
      Tab("Photos", systemImage: "photo.on.rectangle.angled") {
        PhotosView()
      }
      Tab("Playlists", systemImage: "rectangle.stack") {
        PlaylistsView()
      }
      Tab("Frames", systemImage: "photo.artframe") {
        FramesView()
      }
      Tab("Settings", systemImage: "gearshape") {
        SettingsView()
      }
    }
    .alert(
      "Something Went Wrong",
      isPresented: Binding(
        get: { library.errorMessage != nil },
        set: { if !$0 { library.errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(library.errorMessage ?? "")
    }
  }
}

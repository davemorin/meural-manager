import SwiftUI

struct ContentView: View {
  @Environment(MeuralSession.self) private var session
  @Environment(LibraryStore.self) private var library

  var body: some View {
    Group {
      if session.isSignedIn {
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
          Tab("Account", systemImage: "person.crop.circle") {
            AccountView()
          }
        }
      } else {
        SignInView()
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

import SwiftUI

@main
struct MeuralManagerApp: App {
  @State private var library = LibraryStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(library)
    }
  }
}

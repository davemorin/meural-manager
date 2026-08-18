import SwiftUI

@main
struct GalleristApp: App {
  @State private var session: MeuralSession
  @State private var library: LibraryStore

  init() {
    let session = MeuralSession()
    _session = State(initialValue: session)
    _library = State(initialValue: LibraryStore(session: session))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(session)
        .environment(library)
    }
  }
}

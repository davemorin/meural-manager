import SwiftUI

struct SettingsView: View {
  @Environment(LibraryStore.self) private var library
  @State private var serverAddress = ""
  @State private var isTesting = false
  @State private var testMessage: String?
  @State private var testSucceeded = false

  private var trimmedAddress: String {
    serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("http://192.168.1.10:3333", text: $serverAddress)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(save)
          Button("Save", action: save)
            .disabled(trimmedAddress.isEmpty || trimmedAddress == library.serverURLString)
          Button {
            Task {
              await testConnection()
            }
          } label: {
            HStack {
              Text("Test Connection")
              Spacer()
              if isTesting {
                ProgressView()
              }
            }
          }
          .disabled(trimmedAddress.isEmpty || isTesting)
        } header: {
          Text("Server")
        } footer: {
          Text("The address of your Meural Manager server. In the simulator, http://localhost:3333 works when the server runs on this Mac. On a device, use your Mac's network address instead.")
        }

        if let testMessage {
          Section {
            Label(testMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
              .foregroundStyle(testSucceeded ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
          }
        }

        Section("About") {
          LabeledContent("App", value: "Meural Manager")
          Text("A companion app for your self-hosted Meural Manager server — browse your library, manage playlists, and control your frames.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Settings")
      .onAppear {
        serverAddress = library.serverURLString
      }
    }
  }

  private func save() {
    guard !trimmedAddress.isEmpty else { return }
    library.serverURLString = trimmedAddress
    testMessage = nil
  }

  private func testConnection() async {
    guard let url = URL(string: trimmedAddress) else {
      testSucceeded = false
      testMessage = "That doesn't look like a valid address."
      return
    }
    isTesting = true
    defer { isTesting = false }
    do {
      let frames = try await MeuralClient(baseURL: url).fetchFrames()
      testSucceeded = true
      testMessage = frames.count == 1 ? "Connected — found 1 frame." : "Connected — found \(frames.count) frames."
    } catch {
      testSucceeded = false
      testMessage = "Couldn't connect: \(error.localizedDescription)"
    }
  }
}

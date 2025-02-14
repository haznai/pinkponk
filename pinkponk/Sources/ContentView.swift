import SwiftUI

struct ContentView: View {
  // todo: refactor/make it more genral
  @State private var readwiseState: [Readwise] = []
  @State private var apiKey: String = ""
  var body: some View {
    VStack {
      SecureField("Readwise API Key", text: $apiKey)
      Button("let's get this bread") {
        Task {
          // todo: make anki card that
          // task without `do` `catch` silently swallows errors
          do {
            let state = try await ReadwiseRepository(apiKey: apiKey).fetchData()
            await MainActor.run {
              self.readwiseState = state
            }
          } catch {
            print("Error: \(error)")
            //todo: better error handling
          }
        }
      }

      List(readwiseState) { item in
        Text(item.title ?? "No title")
      }
    }
  }
}

#Preview {
  ContentView()
}

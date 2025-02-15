import SwiftUI

// MARK - ContentView
struct ContentView: View {
  // todo: refactor/make it more genral
  @State private var apiKey: String = ""
  // todo: refactor out
  // todo: make singleton
  @State private var readwiseActor: ReadwiseRepository

  init(readwiseActor: ReadwiseRepository) {
    self.readwiseActor = readwiseActor
  }

  var body: some View {
    VStack {
      ArticleListView(ArticleList: readwiseActor.state)
    }
    VStack {
      SecureField("Readwise API Key", text: $apiKey)
      Button("let's get this bread") {
        Task {
          // todo: make anki card that
          // task without `do` `catch` silently swallows errors
          do {
            try await readwiseActor.updateState(self.apiKey)
          } catch {
            print("Error: \(error)")
            //todo: better error handling
          }
        }
      }
    }.padding(10)
  }
}

// MARK: - Pure List View
struct ArticleListView: View {
  let ArticleList: [ReadwiseRepository.Row]
  var body: some View {
    VStack {
      List(ArticleList) { item in
        Text(item.title ?? "No title")
      }

    }
  }
}

#Preview {
  ArticleListView(ArticleList: [
    ReadwiseRepository.Row(id: "test-id", url: "test-url", title: "test-title")
  ])
}

import SwiftUI

// MARK - ContentView
struct ContentView: View {
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
      Button("let's get this bread") {
        Task {
          // todo: create an ui element that collets logs
          do {
            try await readwiseActor.updateState()
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
    ReadwiseRepository.Row(id: "test-id", url: "test-url", title: "test-title", createdAt: nil)
  ])
}

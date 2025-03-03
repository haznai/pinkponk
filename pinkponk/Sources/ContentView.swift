import SwiftUI

// MARK - ContentView
struct ContentView: View {

  @State var governor: Governor

  var body: some View {
    VStack {
      ArticleListView(ArticleList: governor.loadedState)
    }
    VStack {
      Button("let's get this bread") {
        Task {
          // todo: create an ui element that collets logs
          await governor.updateState()
        }
      }
    }.padding(10)
  }
}

// MARK: - Pure List View
struct ArticleListView: View {
  let ArticleList: [GovernorRow]
  var body: some View {
    VStack {
      List(ArticleList) { item in
        Text(item.title ?? "No title")
      }

    }
  }
}

#Preview {
  // todo: preview
}

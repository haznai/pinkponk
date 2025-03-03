import SwiftUI

@main
struct PinkPonkApp: App {
  var body: some Scene {
    WindowGroup {
      // todo: environmental actors here? -> see anki notes or swift docu on thos
      // https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
      ContentView(governor: Governor())
    }
  }
}

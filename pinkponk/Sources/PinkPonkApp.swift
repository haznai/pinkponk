import SwiftUI

@main
struct PinkPonkApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView(readwiseActor: ReadwiseRepository())
    }
  }
}

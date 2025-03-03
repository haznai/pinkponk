import SwiftUI

/// We have many tables in the database, and many different Schemas
/// For Rendering purposes, we need to agree on a set of columns that are relevant for
/// the user. This `GovernorRow` describes the agreed upon relevant columns.
/// Each displayed `Row` will be reduced to a `GoverNow` for rendering.
struct GovernorRow: Identifiable {
  let id: String
  let title: String
}

@Observable
@MainActor
final class Governor {

  var loadedState: [GovernorRow] = []

  let subscribedRepos = [
    ReadwiseRepository(),
    ReadwiseRepository(),
    ReadwiseRepository(),
    ReadwiseRepository(),
    ReadwiseRepository(),
  ]

  func updateState() async {
    for await stateUpdate in loadRows() {
      self.loadedState.append(stateUpdate)
    }
  }

  func loadRows() -> AsyncStream<GovernorRow> {
    AsyncStream { continuation in
      for repo in subscribedRepos {
        Task {
          do {
            try await repo.updateState { state in
              continuation.yield(state)
            }
          } catch {
            // todo: probably want logging here
          }
        }
      }
    }
    // todo: implement continuation.finish somewhere
  }

}

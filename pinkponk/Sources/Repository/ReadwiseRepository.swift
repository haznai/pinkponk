import AsyncHTTPClient
import Foundation
import Lighter

// MARK: - Protocol definition
// todo: refactor this entire file
// todo: make Repository's a module
protocol ActorRepository {
  // associated table has to be exit in `schema.sqlschema`
  associatedtype Row: SQLKeyedTableRecord
  // todo: cleaner api design without optional api key
  func updateState(_ apiKey: String?) async throws
}

// MARK: - Readwise Actor definition
// todo: refactor into a module and make only state public
@Observable
@MainActor
class ReadwiseRepository: ActorRepository {
  typealias Row = Readwise
  private let db: Data
  private(set) var state: [Row] = []

  init() {
    // todo: check if data is actually saved
    // todo: check if there's a connetionhandler problem, or a better way or something
    self.db = Data.init(url: Bundle.module.url(forResource: "data", withExtension: "db")!)
  }

  // todo: add cursor/pagination
  // todo: typed throws, or no throws at all?
  // todo: refactor this into a general method in a protoco/abstract class/whatever
  /// The dataflow us there
  ///
  /// Dataflow is like
  ///  .───────────────.
  /// (                 )
  /// │`───────────────'│
  /// │                 │ ┌──────────────────────────────┐
  /// │    persisted    │ │ 1: sync state with database  │
  /// │      data       │ └──────────────────────────────┘
  /// (                 )                 │
  ///  `───────────────'                  │
  ///                                     │
  ///                                     │
  ///  ┌──────────────┐                   ▼
  ///  │              │   ┌──────────────────────────────┐
  ///  │ api response │   │  2: fetch data from server   │
  ///  │              │   └──────────────────────────────┘
  ///  └──────────────┘                   │
  ///          ║                          │
  ///          ◈                          │
  ///  .───────────────.                  │
  /// (                 )                 ▼
  /// │`───────────────'│ ┌──────────────────────────────┐
  /// │                 │ │3: upsert response to database│
  /// │    persisted    │ └──────────────────────────────┘
  /// │      data       │                 │
  /// (                 )                 │
  ///  `───────────────'                  │
  ///                                     │
  ///                                     ▼
  ///                     ┌──────────────────────────────┐
  ///                     │ 4: sync state with database  │
  ///                     └──────────────────────────────┘
  func updateState(_ apiKey: String?) async throws {
    // todo: more elegant error handling
    guard let apiKey else {
      throw NSError()
    }
    guard apiKey.isEmpty == false else {
      throw NSError()
    }

    if self.state.isEmpty {
      self.state = try await self.db.readwises.fetch()
    }

    let request = self.getRequest(with: apiKey)
    // todo: tradeoff analysis of using a shared or own client
    let response = try await HTTPClient.shared.execute(request, timeout: .seconds(5))

    guard response.status == .ok else {
      throw URLError(.badServerResponse)
    }

    // todo: make definition of response also part of the protocol definition
    struct ReadwiseResponse: Codable {
      let results: [Row]
      let nextPageCursor: String?
    }

    let body = try await response.body.collect(upTo: 10240 * 1024)  // 10 Mb

    let decodedResponse = try JSONDecoder().decode(ReadwiseResponse.self, from: body)

    let persistedRowIds = Set(self.state.map(\.id))
    let recordsToUpdate = decodedResponse.results.filter { persistedRowIds.contains($0.id) }
    let recordsToInsert = decodedResponse.results.filter { !persistedRowIds.contains($0.id) }

    // todo: check that the updates work as expected
    try await self.db.transaction { tx in
      try tx.update(recordsToUpdate)
      try tx.insert(recordsToInsert)
    }

    // todo: check that we have no data loss
    // todo: make this more general, check above for the same call
    self.state = try await self.db.readwises.fetch()
  }

  func getRequest(with apikey: String) -> HTTPClientRequest {
    assert(!apikey.isEmpty)
    var request = HTTPClientRequest(url: "https://readwise.io/api/v3/list/")
    request.headers.add(name: "Authorization", value: "Token \(apikey)")
    request.method = .GET

    return request
  }
}

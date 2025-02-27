import Lighter
import Foundation
import AsyncHTTPClient

// MARK: - Protocol definition
protocol Repository {
  // associated type is the table for this repository in `ApplicationDatabase`
  associatedtype Row: SQLKeyedTableRecord
  static var tableName: String { get }
  var db: ApplicationDatabase { get }
  // not all repositories need an api key
  var apiKey: String? { get }
  func updateState(continuation: @escaping (GovernorRow) -> Void) async throws
}

// todo: Document assumptions here
extension Repository {
  var apiKey: String? {
    if let fetchedApiKey = try? self.db.apiKeys.find(Self.tableName)?.keyValue {
      return fetchedApiKey
    } else {
      return nil
    }
  }
  var db: ApplicationDatabase { DatabaseConnection.shared }
}

struct repo: Repository {
  
  typealias Row = Readwise
  static let tableName: String = "readwise"

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
  func updateState(continuation: @escaping (GovernorRow) -> Void) async throws {
    
    
    let request = self.getRequest()
    // todo: tradeoff analysis of using a shared or own client
    let response = try await HTTPClient.shared.execute(request, timeout: .seconds(5))

    guard response.status == .ok else {
      throw URLError(.badServerResponse)
    }

    // todo: make definition of response also part of the protocol definition
    // todo: or adopt an adapter pattern, just keep the code simple
    struct ReadwiseResponse: Codable {
      let results: [Row]
      let nextPageCursor: String?
    }

    let body = try await response.body.collect(upTo: 10240 * 1024)  // 10 Mb

    let decodedResponse = try JSONDecoder().decode(ReadwiseResponse.self, from: body)

    // todo: check that we have no data loss
    // todo: make this more general, check above for the same call
    try await self.updateDatabase(with: decodedResponse.results)
    

    // pagination logic
    // todo: has to be refactored and made more general aswell
    // i basically just copy pasted the above code heere
    // todo: add a wait so we don't hit rate limits on api
    var currentCursor = decodedResponse.nextPageCursor
    while let cursor = currentCursor {
      let request = self.getRequest(lastPaginationCursor: cursor)
      let response = try await HTTPClient.shared.execute(request, timeout: .seconds(5))
      guard response.status == .ok else {
        throw URLError(.badServerResponse)
      }
      let body = try await response.body.collect(upTo: 10240 * 1024)  // 10 Mb
      let decodedResponse = try JSONDecoder().decode(ReadwiseResponse.self, from: body)
      try await self.updateDatabase(with: decodedResponse.results)
      self.state = try await self.db.readwises.fetch()
      currentCursor = decodedResponse.nextPageCursor
    }

  }

  func getRequest(lastPaginationCursor cursor: String? = nil) -> HTTPClientRequest {
    precondition(self.apiKey != nil)
    var request = HTTPClientRequest(url: "https://readwise.io/api/v3/list/")
    request.headers.add(name: "Authorization", value: "Token \(self.apiKey!)")
    request.method = .GET

    if let cursor = cursor {
      assert(!cursor.isEmpty)
      // todo: isn't there a better way?
      request.url.append("?pageCursor=\(cursor)")
    }

    return request
  }

  func updateDatabase(with newItems: [Row]) async throws {
    let persistedRowIds = Set(self.state.map(\.id))
    let recordsToUpdate = newItems.filter { persistedRowIds.contains($0.id) }
    let recordsToInsert = newItems.filter { !persistedRowIds.contains($0.id) }

    // todo: check that the updates work as expected
    try await self.db.transaction(mode: .immediate) { tx in
      try tx.update(recordsToUpdate)
      try tx.insert(recordsToInsert)
    }
  }
}

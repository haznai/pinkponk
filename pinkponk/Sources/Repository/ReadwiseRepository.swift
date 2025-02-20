import AsyncHTTPClient
import Foundation
import Lighter
import SQLite3

// MARK: - Protocol definition
// todo: refactor this entire file
// todo: make Repository's a module
protocol ActorRepository: AnyObject {
  // associated table has to be exit in `schema.sqlschema`
  associatedtype Row: SQLKeyedTableRecord
  func updateState() async throws
}

// MARK: - Readwise Actor definition
// todo: refactor into a module and make only state public
@Observable
@MainActor
final class ReadwiseRepository: ActorRepository {
  typealias Row = Readwise
  private let db: ApplicationDatabase
  private let apiKey: String
  private(set) var state: [Row]

  // todo: make database a singleton, and a single acces through global actor?
  //       idea: a globa actor that is also the pool manager, and calls the below logic for
  //       creating a database if it doesn't exist. mainly manages poool access
  //       maybe overkill? a single connection is probably fine, no?
  //       use the `simplePool` implementaton
  // todo: figure what to do with the `db` connection
  // todo: ensure database always has schema loaded
  init() {
    let url = URL.documentsDirectory.appending(path: "db.sqlite")
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
      let cpath = url.path(percentEncoded: false).cString(using: .utf8)
      var db: OpaquePointer!
      let rc = sqlite3_create_applicationdatabase(
        cpath, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, &db)
      guard rc == SQLITE_OK else { fatalError("Failed to create database connection") }
    }
    self.db = ApplicationDatabase(url: url)
    let fetchedApiKey = try? db.apiKeys.find("readwise")?.keyValue
    guard let fetchedApiKey else {
      fatalError("no readwise api key in database")
    }
    self.apiKey = fetchedApiKey
    self.state = []
  }

  // todo: add cursor/pagination
  // todo: typed throws, or no throws at all?
  // todo: refactor this into a general method in a protoco/abstract class/whatever
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
  func updateState() async throws {
    if self.state.isEmpty {
      self.state = try await self.db.readwises.fetch()
    }

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
    self.state = try await self.db.readwises.fetch()

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
    var request = HTTPClientRequest(url: "https://readwise.io/api/v3/list/")
    request.headers.add(name: "Authorization", value: "Token \(self.apiKey)")
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

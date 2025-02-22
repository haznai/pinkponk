import AsyncHTTPClient
import Foundation
import Lighter
import SQLite3

// MARK: - Singleton Access for the database
/// Singleton Access to the datbase
/// Lighter comes with a simple connectionpool handler, let the library and database do the async work
final class DatabaseConnection {
  private static let applicationSupportPath = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent(Bundle.main.bundleIdentifier ?? "pinkponk", isDirectory: true)
  static let shared: ApplicationDatabase = {
    let databaseURL = applicationSupportPath.appendingPathComponent("pinkponkdb.db")
    do {
      try ensureDatabaseIsInitialized(on: databaseURL)
    } catch {
      preconditionFailure("Failed to initialize database: \(error)")
    }

    return ApplicationDatabase(url: databaseURL)
  }()

  /// Ensures the database file exists and is accessible.
  /// Throws an error if the database cannot be created or opened.
  private static func ensureDatabaseIsInitialized(on pathURL: URL) throws {
    assert(pathURL.isFileURL)
    assert(
      pathURL.deletingLastPathComponent().deletingLastPathComponent().path
        == URL.applicationSupportDirectory.path)
    defer { assert(try! pathURL.checkResourceIsReachable()) }

    // Ensure the Application Support directory exists
    try FileManager.default.createDirectory(
      at: pathURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    // Ensure Database exists
    if !FileManager.default.fileExists(atPath: pathURL.path) {
      FileManager.default.createFile(atPath: pathURL.path, contents: nil)
      // Get a C-style string from the file path.
      let cpath = pathURL.path(percentEncoded: false).cString(using: .utf8)

      // Pointer for the SQLite database connection (will be discarded).
      var db: OpaquePointer!
      let rc = sqlite3_create_applicationdatabase(
        cpath, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, &db)
      // Close the connection immediately.
      sqlite3_close_v2(db)
      guard rc == SQLITE_OK else {
        throw SQLError(rc)
      }
    }
  }
}

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

  // todo: figure what to do with the `db` connection
  // todo: ensure database always has schema loaded
  init(db: ApplicationDatabase? = nil) {
    self.db = db ?? DatabaseConnection.shared
    let fetchedApiKey = try? self.db.apiKeys.find("readwise")?.keyValue
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

// MARK: - Apple notes repo
@Observable
@MainActor
final class AppleNotesRepository: ActorRepository {
  typealias Row = AppleNotes
  func updateState() async throws {
  }
}

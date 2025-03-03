import AsyncHTTPClient
import Foundation
import Lighter

// MARK: - Protocol definition
protocol Repository {
  // associated type is the table for this repository in `ApplicationDatabase`
  associatedtype Row: SQLKeyedTableRecord
  static var tableName: String { get }
  var db: ApplicationDatabase { get }
  // not all repositories need an api key
  var apiKey: String? { get }
  func updateState(continuation: @escaping @Sendable (GovernorRow) -> Void) async throws
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

struct ReadwiseRepository: Repository {
  typealias Row = Readwise
  static let tableName: String = "readwise"

  // todo: make this actual logic, and not placeholder logic
  func updateState(continuation: @escaping @Sendable (GovernorRow) -> Void) async throws {
    var tempId = 0
    while tempId < 10 {
      try? await Task.sleep(for: .seconds(.random(in: 0 ... 2)))
      continuation(GovernorRow(id: String(tempId), title: "test \(tempId)"))
      tempId += 1
    }
  }
}

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
    self.db = Data.module
  }

  // todo: add cursor/pagination
  // todo: typed throws
  func updateState(_ apiKey: String?) async throws {
    // todo: more elegant error handling
    guard let apiKey else {
      throw NSError()
    }
    guard apiKey.isEmpty == false else {
      throw NSError()
    }

    if self.state.isEmpty {
      self.state = try! await self.db.readwises.fetch()
    }

    let request = self.getRequest(with: apiKey)
    // todo: tradeoff analysis of using a shared or own client
    let response = try await HTTPClient.shared.execute(request, timeout: .seconds(5))

    guard response.status == .ok else {
      throw URLError(.badServerResponse)
    }

    // todo: make definition of response also part of the protocol definition
    struct ReadwiseResponse: Codable {
      let results: [Readwise]
      let nextPageCursor: String?
    }

    let body = try await response.body.collect(upTo: 10240 * 1024)  // 10 Mb

    let readwiseResponse = try JSONDecoder().decode(ReadwiseResponse.self, from: body)

    self.state = readwiseResponse.results
  }

  func getRequest(with apikey: String) -> HTTPClientRequest {
    assert(!apikey.isEmpty)
    var request = HTTPClientRequest(url: "https://readwise.io/api/v3/list/")
    request.headers.add(name: "Authorization", value: "Token \(apikey)")
    request.method = .GET

    return request
  }
}

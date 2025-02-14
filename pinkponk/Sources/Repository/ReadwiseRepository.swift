import AsyncHTTPClient
import Foundation
import Lighter

// MARK: - Protocol definition
// todo: refactor this entire file
// todo: make Repository's a module
protocol Repository {
  /// associated table has to be exit in `schema.sqlschema`
  associatedtype Table where Table: SQLKeyedTableRecord
  func fetchData() async throws -> [Table]
}

// MARK: - Readwise Struct definition
struct ReadwiseRepository: Repository {
  let apiKey: String
  // todo: add cursor/pagination
  // todo: typed throws
  public func fetchData() async throws -> [Readwise] {
    let request = self.getRequest()
    // todo: tradeoff analysis of using a shared or own client
    let response = try await HTTPClient.shared.execute(request, timeout: .seconds(5))

    // todo: smoother error handling
    guard response.status == .ok else {
      fatalError("didn't work")
    }

    // todo: make definition of response also part of the protocol definition
    struct ReadwiseResponse: Codable {
      let results: [Readwise]
      let nextPageCursor: String?
    }

    let body = try await response.body.collect(upTo: 10240 * 1024)  // 10 Mb

    let readwiseResponse = try JSONDecoder().decode(ReadwiseResponse.self, from: body)

    return readwiseResponse.results
  }

  func getRequest() -> HTTPClientRequest {
    var request = HTTPClientRequest(url: "https://readwise.io/api/v3/list/")
    request.headers.add(name: "Authorization", value: "Token \(self.apiKey)")
    request.method = .GET

    return request
  }
}

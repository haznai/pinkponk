import AsyncHTTPClient
import Foundation
import Lighter


// todo: refactor this entire file
protocol Repository {
    /// associated table has to be exit in `schema.sqlschema`
    associatedtype Table where Table: SQLKeyedTableRecord
    func fetchData() async throws -> [Table]
}


struct ReadwiseRepository: Repository {
    let apiKey: String
    // todo: add cursor/pagination
    // todo: typed throws
    func fetchData() async throws -> [Readwise] {
        var request = HTTPClientRequest(url: "https://readwise.io/api/v3/list/")
        request.headers.add(name: "Authorization", value: "Token \(self.apiKey)")
        request.method = .GET
        
        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(5))
        
        // todo: smoother error handling
        guard response.status == .ok else {
            fatalError("didn't work")
        }
        
        struct ReadwiseResponse: Codable {
            let results: [Readwise]
            let nextPageCursor: String?
        }
        
        let body = try await response.body.collect(upTo: 10240 * 1024) // 10 Mb
        
        let readwiseResponse = try JSONDecoder().decode(ReadwiseResponse.self, from: body)
        
        return readwiseResponse.results
    }
}

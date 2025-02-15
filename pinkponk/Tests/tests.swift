import AsyncHTTPClient
import InlineSnapshotTesting
import Testing

@testable import pinkponk

struct AsyncHTTPClientTests {
  @MainActor @Test func readwiseRepo() throws {
    let repo = ReadwiseRepository()
    // api key passed
    assertInlineSnapshot(of: repo.getRequest(with: "test-api-key"), as: .description) {
      """
      HTTPClientRequest(url: "https://readwise.io/api/v3/list/", method: NIOHTTP1.HTTPMethod.GET, headers: Authorization: Token test-api-key, body: nil, tlsConfiguration: nil)
      """
    }
  }
}

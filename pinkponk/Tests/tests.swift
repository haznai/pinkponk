import AsyncHTTPClient
import InlineSnapshotTesting
import Testing

@testable import pinkponk

struct AsyncHTTPClientTests {
  @Test func readwiseRepo() throws {
    let repo = ReadwiseRepository(apiKey: "test-api-key")
    assertInlineSnapshot(of: repo.getRequest(), as: .description) {
      """
      HTTPClientRequest(url: "https://readwise.io/api/v3/list/", method: NIOHTTP1.HTTPMethod.GET, headers: Authorization: Token test-api-key, body: nil, tlsConfiguration: nil)
      """
    }
  }
}

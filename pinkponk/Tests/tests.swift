import AsyncHTTPClient
import InlineSnapshotTesting
import Testing

@testable import pinkponk

struct AsyncHTTPClientTests {
  @MainActor @Test func readwiseRepo() throws {
    let repo = ReadwiseRepository()
    let request = repo.getRequest()
    #expect(request.url == "https://readwise.io/api/v3/list/")
    #expect(request.method == .GET)
    #expect(request.headers.contains(name: "Authorization"))

    let requestWithPaginationCursor = repo.getRequest(lastPaginationCursor: "test")
    #expect(requestWithPaginationCursor.url == "https://readwise.io/api/v3/list/?pageCursor=test")
  }
}

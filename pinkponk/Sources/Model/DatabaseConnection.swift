import Foundation
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

// todo: remove this header comment

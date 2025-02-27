import Foundation
import Lighter
import SQLite3

/// Create a SQLite3 database
///
/// The database is created using the SQL `create` statements in the
/// Schema structures.
///
/// If the operation is successful, the open database handle will be
/// returned in the `db` `inout` parameter.
/// If the open succeeds, but the SQL execution fails, an incomplete
/// database can be left behind. I.e. if an error happens, the path
/// should be tested and deleted if appropriate.
///
/// Example:
/// ```swift
/// var db : OpaquePointer!
/// let rc = sqlite3_create_applicationdatabase(path, &db)
/// ```
///
/// - Parameters:
///   - path: Path of the database.
///   - flags: Custom open flags.
///   - db: A SQLite3 database handle, if successful.
/// - Returns: The SQLite3 error code (`SQLITE_OK` on success).
@inlinable
public func sqlite3_create_applicationdatabase(
  _ path: UnsafePointer<CChar>!,
  _ flags: Int32 = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
  _ db: inout OpaquePointer?
) -> Int32 {
  let openrc = sqlite3_open_v2(path, &db, flags, nil)
  if openrc != SQLITE_OK {
    return openrc
  }
  let execrc = sqlite3_exec(db, ApplicationDatabase.creationSQL, nil, nil, nil)
  if execrc != SQLITE_OK {
    sqlite3_close(db)
    db = nil
    return execrc
  }
  return SQLITE_OK
}

/// Insert a ``Readwise`` record in the SQLite database.
///
/// This operates on a raw SQLite database handle (as returned by
/// `sqlite3_open`).
///
/// Example:
/// ```swift
/// let rc = sqlite3_readwise_insert(db, record)
/// assert(rc == SQLITE_OK)
/// ```
///
/// - Parameters:
///   - db: SQLite3 database handle.
///   - record: The record to insert. Updated with the actual table values (e.g. assigned primary key).
/// - Returns: The SQLite error code (of `sqlite3_prepare/step`), e.g. `SQLITE_OK`.
@inlinable
@discardableResult
public func sqlite3_readwise_insert(_ db: OpaquePointer!, _ record: inout Readwise)
  -> Int32
{
  let sql =
    ApplicationDatabase.useInsertReturning
    ? Readwise.Schema.insertReturning : Readwise.Schema.insert
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return sqlite3_errcode(db) }
  defer { sqlite3_finalize(statement) }
  return record.bind(to: statement, indices: Readwise.Schema.insertParameterIndices) {
    let rc = sqlite3_step(statement)
    if rc == SQLITE_DONE {
      var sql = Readwise.Schema.select
      sql.append(#" WHERE ROWID = last_insert_rowid()"#)
      var handle: OpaquePointer? = nil
      guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
        let statement = handle
      else { return sqlite3_errcode(db) }
      defer { sqlite3_finalize(statement) }
      let rc = sqlite3_step(statement)
      if rc == SQLITE_DONE {
        return SQLITE_OK
      } else if rc != SQLITE_ROW {
        return sqlite3_errcode(db)
      }
      record = Readwise(statement, indices: Readwise.Schema.selectColumnIndices)
      return SQLITE_OK
    } else if rc != SQLITE_ROW {
      return sqlite3_errcode(db)
    }
    record = Readwise(statement, indices: Readwise.Schema.selectColumnIndices)
    return SQLITE_OK
  }
}

/// Update a ``Readwise`` record in the SQLite database.
///
/// This operates on a raw SQLite database handle (as returned by
/// `sqlite3_open`).
///
/// Example:
/// ```swift
/// let rc = sqlite3_readwise_update(db, record)
/// assert(rc == SQLITE_OK)
/// ```
///
/// - Parameters:
///   - db: SQLite3 database handle.
///   - record: The ``Readwise`` record to update.
/// - Returns: The SQLite error code (of `sqlite3_prepare/step`), e.g. `SQLITE_OK`.
@inlinable
@discardableResult
public func sqlite3_readwise_update(_ db: OpaquePointer!, _ record: Readwise)
  -> Int32
{
  let sql = Readwise.Schema.update
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return sqlite3_errcode(db) }
  defer { sqlite3_finalize(statement) }
  return record.bind(to: statement, indices: Readwise.Schema.updateParameterIndices) {
    let rc = sqlite3_step(statement)
    return rc != SQLITE_DONE && rc != SQLITE_ROW ? sqlite3_errcode(db) : SQLITE_OK
  }
}

/// Delete a ``Readwise`` record in the SQLite database.
///
/// This operates on a raw SQLite database handle (as returned by
/// `sqlite3_open`).
///
/// Example:
/// ```swift
/// let rc = sqlite3_readwise_delete(db, record)
/// assert(rc == SQLITE_OK)
/// ```
///
/// - Parameters:
///   - db: SQLite3 database handle.
///   - record: The ``Readwise`` record to delete.
/// - Returns: The SQLite error code (of `sqlite3_prepare/step`), e.g. `SQLITE_OK`.
@inlinable
@discardableResult
public func sqlite3_readwise_delete(_ db: OpaquePointer!, _ record: Readwise)
  -> Int32
{
  let sql = Readwise.Schema.delete
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return sqlite3_errcode(db) }
  defer { sqlite3_finalize(statement) }
  return record.bind(to: statement, indices: Readwise.Schema.deleteParameterIndices) {
    let rc = sqlite3_step(statement)
    return rc != SQLITE_DONE && rc != SQLITE_ROW ? sqlite3_errcode(db) : SQLITE_OK
  }
}

/// Fetch ``Readwise`` records, filtering using a Swift closure.
///
/// This is fetching full ``Readwise`` records from the passed in SQLite database
/// handle. The filtering is done within SQLite, but using a Swift closure
/// that can be passed in.
///
/// Within that closure other SQL queries can be done on separate connections,
/// but *not* within the same database handle that is being passed in (because
/// the closure is executed in the context of the query).
///
/// Sorting can be done using raw SQL (by passing in a `orderBy` parameter,
/// e.g. `orderBy: "name DESC"`),
/// or just in Swift (e.g. `fetch(in: db).sorted { $0.name > $1.name }`).
/// Since the matching is done in Swift anyways, the primary advantage of
/// doing it in SQL is that a `LIMIT` can be applied efficiently (i.e. w/o
/// walking and loading all rows).
///
/// If the function returns `nil`, the error can be found using the usual
/// `sqlite3_errcode` and companions.
///
/// Example:
/// ```swift
/// let records = sqlite3_readwises_fetch(db) { record in
///   record.name != "Duck"
/// }
///
/// let records = sqlite3_readwises_fetch(db, orderBy: "name", limit: 5) {
///   $0.firstname != nil
/// }
/// ```
///
/// - Parameters:
///   - db: The SQLite database handle (as returned by `sqlite3_open`)
///   - sql: Optional custom SQL yielding ``Readwise`` records.
///   - orderBySQL: If set, some SQL that is added as an `ORDER BY` clause (e.g. `name DESC`).
///   - limit: An optional fetch limit.
///   - filter: A Swift closure used for filtering, taking the``Readwise`` record to be matched.
/// - Returns: The records matching the query, or `nil` if there was an error.
@inlinable
public func sqlite3_readwises_fetch(
  _ db: OpaquePointer!,
  sql customSQL: String? = nil,
  orderBy orderBySQL: String? = nil,
  limit: Int? = nil,
  filter: @escaping (Readwise) -> Bool
) -> [Readwise]? {
  withUnsafePointer(to: filter) { (closurePtr) in
    guard
      Readwise.Schema.registerSwiftMatcher(
        in: db,
        flags: SQLITE_UTF8,
        matcher: closurePtr
      ) == SQLITE_OK
    else {
      return nil
    }
    defer {
      Readwise.Schema.unregisterSwiftMatcher(in: db, flags: SQLITE_UTF8)
    }
    var sql = customSQL ?? Readwise.Schema.matchSelect
    if let orderBySQL = orderBySQL {
      sql.append(" ORDER BY \(orderBySQL)")
    }
    if let limit = limit {
      sql.append(" LIMIT \(limit)")
    }
    var handle: OpaquePointer? = nil
    guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
      let statement = handle
    else { return nil }
    defer { sqlite3_finalize(statement) }
    let indices =
      customSQL != nil
      ? Readwise.Schema.lookupColumnIndices(in: statement) : Readwise.Schema.selectColumnIndices
    var records = [Readwise]()
    while true {
      let rc = sqlite3_step(statement)
      if rc == SQLITE_DONE {
        break
      } else if rc != SQLITE_ROW {
        return nil
      }
      records.append(Readwise(statement, indices: indices))
    }
    return records
  }
}

/// Fetch ``Readwise`` records using the base SQLite API.
///
/// If the function returns `nil`, the error can be found using the usual
/// `sqlite3_errcode` and companions.
///
/// Example:
/// ```swift
/// let records = sqlite3_readwises_fetch(
///   db, sql: #"SELECT * FROM readwise"#
/// }
///
/// let records = sqlite3_readwises_fetch(
///   db, sql: #"SELECT * FROM readwise"#,
///   orderBy: "name", limit: 5
/// )
/// ```
///
/// - Parameters:
///   - db: The SQLite database handle (as returned by `sqlite3_open`)
///   - sql: Custom SQL yielding ``Readwise`` records.
///   - orderBySQL: If set, some SQL that is added as an `ORDER BY` clause (e.g. `name DESC`).
///   - limit: An optional fetch limit.
/// - Returns: The records matching the query, or `nil` if there was an error.
@inlinable
public func sqlite3_readwises_fetch(
  _ db: OpaquePointer!,
  sql customSQL: String? = nil,
  orderBy orderBySQL: String? = nil,
  limit: Int? = nil
) -> [Readwise]? {
  var sql = customSQL ?? Readwise.Schema.select
  if let orderBySQL = orderBySQL {
    sql.append(" ORDER BY \(orderBySQL)")
  }
  if let limit = limit {
    sql.append(" LIMIT \(limit)")
  }
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return nil }
  defer { sqlite3_finalize(statement) }
  let indices =
    customSQL != nil
    ? Readwise.Schema.lookupColumnIndices(in: statement) : Readwise.Schema.selectColumnIndices
  var records = [Readwise]()
  while true {
    let rc = sqlite3_step(statement)
    if rc == SQLITE_DONE {
      break
    } else if rc != SQLITE_ROW {
      return nil
    }
    records.append(Readwise(statement, indices: indices))
  }
  return records
}

/// Insert a ``ApiKeys`` record in the SQLite database.
///
/// This operates on a raw SQLite database handle (as returned by
/// `sqlite3_open`).
///
/// Example:
/// ```swift
/// let rc = sqlite3_api_keys_insert(db, record)
/// assert(rc == SQLITE_OK)
/// ```
///
/// - Parameters:
///   - db: SQLite3 database handle.
///   - record: The record to insert. Updated with the actual table values (e.g. assigned primary key).
/// - Returns: The SQLite error code (of `sqlite3_prepare/step`), e.g. `SQLITE_OK`.
@inlinable
@discardableResult
public func sqlite3_api_keys_insert(_ db: OpaquePointer!, _ record: inout ApiKeys)
  -> Int32
{
  let sql =
    ApplicationDatabase.useInsertReturning ? ApiKeys.Schema.insertReturning : ApiKeys.Schema.insert
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return sqlite3_errcode(db) }
  defer { sqlite3_finalize(statement) }
  return record.bind(to: statement, indices: ApiKeys.Schema.insertParameterIndices) {
    let rc = sqlite3_step(statement)
    if rc == SQLITE_DONE {
      var sql = ApiKeys.Schema.select
      sql.append(#" WHERE ROWID = last_insert_rowid()"#)
      var handle: OpaquePointer? = nil
      guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
        let statement = handle
      else { return sqlite3_errcode(db) }
      defer { sqlite3_finalize(statement) }
      let rc = sqlite3_step(statement)
      if rc == SQLITE_DONE {
        return SQLITE_OK
      } else if rc != SQLITE_ROW {
        return sqlite3_errcode(db)
      }
      record = ApiKeys(statement, indices: ApiKeys.Schema.selectColumnIndices)
      return SQLITE_OK
    } else if rc != SQLITE_ROW {
      return sqlite3_errcode(db)
    }
    record = ApiKeys(statement, indices: ApiKeys.Schema.selectColumnIndices)
    return SQLITE_OK
  }
}

/// Update a ``ApiKeys`` record in the SQLite database.
///
/// This operates on a raw SQLite database handle (as returned by
/// `sqlite3_open`).
///
/// Example:
/// ```swift
/// let rc = sqlite3_api_keys_update(db, record)
/// assert(rc == SQLITE_OK)
/// ```
///
/// - Parameters:
///   - db: SQLite3 database handle.
///   - record: The ``ApiKeys`` record to update.
/// - Returns: The SQLite error code (of `sqlite3_prepare/step`), e.g. `SQLITE_OK`.
@inlinable
@discardableResult
public func sqlite3_api_keys_update(_ db: OpaquePointer!, _ record: ApiKeys)
  -> Int32
{
  let sql = ApiKeys.Schema.update
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return sqlite3_errcode(db) }
  defer { sqlite3_finalize(statement) }
  return record.bind(to: statement, indices: ApiKeys.Schema.updateParameterIndices) {
    let rc = sqlite3_step(statement)
    return rc != SQLITE_DONE && rc != SQLITE_ROW ? sqlite3_errcode(db) : SQLITE_OK
  }
}

/// Delete a ``ApiKeys`` record in the SQLite database.
///
/// This operates on a raw SQLite database handle (as returned by
/// `sqlite3_open`).
///
/// Example:
/// ```swift
/// let rc = sqlite3_api_keys_delete(db, record)
/// assert(rc == SQLITE_OK)
/// ```
///
/// - Parameters:
///   - db: SQLite3 database handle.
///   - record: The ``ApiKeys`` record to delete.
/// - Returns: The SQLite error code (of `sqlite3_prepare/step`), e.g. `SQLITE_OK`.
@inlinable
@discardableResult
public func sqlite3_api_keys_delete(_ db: OpaquePointer!, _ record: ApiKeys)
  -> Int32
{
  let sql = ApiKeys.Schema.delete
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return sqlite3_errcode(db) }
  defer { sqlite3_finalize(statement) }
  return record.bind(to: statement, indices: ApiKeys.Schema.deleteParameterIndices) {
    let rc = sqlite3_step(statement)
    return rc != SQLITE_DONE && rc != SQLITE_ROW ? sqlite3_errcode(db) : SQLITE_OK
  }
}

/// Fetch ``ApiKeys`` records, filtering using a Swift closure.
///
/// This is fetching full ``ApiKeys`` records from the passed in SQLite database
/// handle. The filtering is done within SQLite, but using a Swift closure
/// that can be passed in.
///
/// Within that closure other SQL queries can be done on separate connections,
/// but *not* within the same database handle that is being passed in (because
/// the closure is executed in the context of the query).
///
/// Sorting can be done using raw SQL (by passing in a `orderBy` parameter,
/// e.g. `orderBy: "name DESC"`),
/// or just in Swift (e.g. `fetch(in: db).sorted { $0.name > $1.name }`).
/// Since the matching is done in Swift anyways, the primary advantage of
/// doing it in SQL is that a `LIMIT` can be applied efficiently (i.e. w/o
/// walking and loading all rows).
///
/// If the function returns `nil`, the error can be found using the usual
/// `sqlite3_errcode` and companions.
///
/// Example:
/// ```swift
/// let records = sqlite3_api_keys_fetch(db) { record in
///   record.name != "Duck"
/// }
///
/// let records = sqlite3_api_keys_fetch(db, orderBy: "name", limit: 5) {
///   $0.firstname != nil
/// }
/// ```
///
/// - Parameters:
///   - db: The SQLite database handle (as returned by `sqlite3_open`)
///   - sql: Optional custom SQL yielding ``ApiKeys`` records.
///   - orderBySQL: If set, some SQL that is added as an `ORDER BY` clause (e.g. `name DESC`).
///   - limit: An optional fetch limit.
///   - filter: A Swift closure used for filtering, taking the``ApiKeys`` record to be matched.
/// - Returns: The records matching the query, or `nil` if there was an error.
@inlinable
public func sqlite3_api_keys_fetch(
  _ db: OpaquePointer!,
  sql customSQL: String? = nil,
  orderBy orderBySQL: String? = nil,
  limit: Int? = nil,
  filter: @escaping (ApiKeys) -> Bool
) -> [ApiKeys]? {
  withUnsafePointer(to: filter) { (closurePtr) in
    guard
      ApiKeys.Schema.registerSwiftMatcher(in: db, flags: SQLITE_UTF8, matcher: closurePtr)
        == SQLITE_OK
    else {
      return nil
    }
    defer {
      ApiKeys.Schema.unregisterSwiftMatcher(in: db, flags: SQLITE_UTF8)
    }
    var sql = customSQL ?? ApiKeys.Schema.matchSelect
    if let orderBySQL = orderBySQL {
      sql.append(" ORDER BY \(orderBySQL)")
    }
    if let limit = limit {
      sql.append(" LIMIT \(limit)")
    }
    var handle: OpaquePointer? = nil
    guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
      let statement = handle
    else { return nil }
    defer { sqlite3_finalize(statement) }
    let indices =
      customSQL != nil
      ? ApiKeys.Schema.lookupColumnIndices(in: statement) : ApiKeys.Schema.selectColumnIndices
    var records = [ApiKeys]()
    while true {
      let rc = sqlite3_step(statement)
      if rc == SQLITE_DONE {
        break
      } else if rc != SQLITE_ROW {
        return nil
      }
      records.append(ApiKeys(statement, indices: indices))
    }
    return records
  }
}

/// Fetch ``ApiKeys`` records using the base SQLite API.
///
/// If the function returns `nil`, the error can be found using the usual
/// `sqlite3_errcode` and companions.
///
/// Example:
/// ```swift
/// let records = sqlite3_api_keys_fetch(
///   db, sql: #"SELECT * FROM api_keys"#
/// }
///
/// let records = sqlite3_api_keys_fetch(
///   db, sql: #"SELECT * FROM api_keys"#,
///   orderBy: "name", limit: 5
/// )
/// ```
///
/// - Parameters:
///   - db: The SQLite database handle (as returned by `sqlite3_open`)
///   - sql: Custom SQL yielding ``ApiKeys`` records.
///   - orderBySQL: If set, some SQL that is added as an `ORDER BY` clause (e.g. `name DESC`).
///   - limit: An optional fetch limit.
/// - Returns: The records matching the query, or `nil` if there was an error.
@inlinable
public func sqlite3_api_keys_fetch(
  _ db: OpaquePointer!,
  sql customSQL: String? = nil,
  orderBy orderBySQL: String? = nil,
  limit: Int? = nil
) -> [ApiKeys]? {
  var sql = customSQL ?? ApiKeys.Schema.select
  if let orderBySQL = orderBySQL {
    sql.append(" ORDER BY \(orderBySQL)")
  }
  if let limit = limit {
    sql.append(" LIMIT \(limit)")
  }
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return nil }
  defer { sqlite3_finalize(statement) }
  let indices =
    customSQL != nil
    ? ApiKeys.Schema.lookupColumnIndices(in: statement) : ApiKeys.Schema.selectColumnIndices
  var records = [ApiKeys]()
  while true {
    let rc = sqlite3_step(statement)
    if rc == SQLITE_DONE {
      break
    } else if rc != SQLITE_ROW {
      return nil
    }
    records.append(ApiKeys(statement, indices: indices))
  }
  return records
}

/// Insert a ``AppleNotes`` record in the SQLite database.
///
/// This operates on a raw SQLite database handle (as returned by
/// `sqlite3_open`).
///
/// Example:
/// ```swift
/// let rc = sqlite3_apple_notes_insert(db, record)
/// assert(rc == SQLITE_OK)
/// ```
///
/// - Parameters:
///   - db: SQLite3 database handle.
///   - record: The record to insert. Updated with the actual table values (e.g. assigned primary key).
/// - Returns: The SQLite error code (of `sqlite3_prepare/step`), e.g. `SQLITE_OK`.
@inlinable
@discardableResult
public func sqlite3_apple_notes_insert(
  _ db: OpaquePointer!,
  _ record: inout AppleNotes
) -> Int32 {
  let sql =
    ApplicationDatabase.useInsertReturning
    ? AppleNotes.Schema.insertReturning : AppleNotes.Schema.insert
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return sqlite3_errcode(db) }
  defer { sqlite3_finalize(statement) }
  return record.bind(to: statement, indices: AppleNotes.Schema.insertParameterIndices) {
    let rc = sqlite3_step(statement)
    if rc == SQLITE_DONE {
      var sql = AppleNotes.Schema.select
      sql.append(#" WHERE ROWID = last_insert_rowid()"#)
      var handle: OpaquePointer? = nil
      guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
        let statement = handle
      else { return sqlite3_errcode(db) }
      defer { sqlite3_finalize(statement) }
      let rc = sqlite3_step(statement)
      if rc == SQLITE_DONE {
        return SQLITE_OK
      } else if rc != SQLITE_ROW {
        return sqlite3_errcode(db)
      }
      record = AppleNotes(statement, indices: AppleNotes.Schema.selectColumnIndices)
      return SQLITE_OK
    } else if rc != SQLITE_ROW {
      return sqlite3_errcode(db)
    }
    record = AppleNotes(statement, indices: AppleNotes.Schema.selectColumnIndices)
    return SQLITE_OK
  }
}

/// Update a ``AppleNotes`` record in the SQLite database.
///
/// This operates on a raw SQLite database handle (as returned by
/// `sqlite3_open`).
///
/// Example:
/// ```swift
/// let rc = sqlite3_apple_notes_update(db, record)
/// assert(rc == SQLITE_OK)
/// ```
///
/// - Parameters:
///   - db: SQLite3 database handle.
///   - record: The ``AppleNotes`` record to update.
/// - Returns: The SQLite error code (of `sqlite3_prepare/step`), e.g. `SQLITE_OK`.
@inlinable
@discardableResult
public func sqlite3_apple_notes_update(_ db: OpaquePointer!, _ record: AppleNotes)
  -> Int32
{
  let sql = AppleNotes.Schema.update
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return sqlite3_errcode(db) }
  defer { sqlite3_finalize(statement) }
  return record.bind(to: statement, indices: AppleNotes.Schema.updateParameterIndices) {
    let rc = sqlite3_step(statement)
    return rc != SQLITE_DONE && rc != SQLITE_ROW ? sqlite3_errcode(db) : SQLITE_OK
  }
}

/// Delete a ``AppleNotes`` record in the SQLite database.
///
/// This operates on a raw SQLite database handle (as returned by
/// `sqlite3_open`).
///
/// Example:
/// ```swift
/// let rc = sqlite3_apple_notes_delete(db, record)
/// assert(rc == SQLITE_OK)
/// ```
///
/// - Parameters:
///   - db: SQLite3 database handle.
///   - record: The ``AppleNotes`` record to delete.
/// - Returns: The SQLite error code (of `sqlite3_prepare/step`), e.g. `SQLITE_OK`.
@inlinable
@discardableResult
public func sqlite3_apple_notes_delete(_ db: OpaquePointer!, _ record: AppleNotes)
  -> Int32
{
  let sql = AppleNotes.Schema.delete
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return sqlite3_errcode(db) }
  defer { sqlite3_finalize(statement) }
  return record.bind(to: statement, indices: AppleNotes.Schema.deleteParameterIndices) {
    let rc = sqlite3_step(statement)
    return rc != SQLITE_DONE && rc != SQLITE_ROW ? sqlite3_errcode(db) : SQLITE_OK
  }
}

/// Fetch ``AppleNotes`` records, filtering using a Swift closure.
///
/// This is fetching full ``AppleNotes`` records from the passed in SQLite database
/// handle. The filtering is done within SQLite, but using a Swift closure
/// that can be passed in.
///
/// Within that closure other SQL queries can be done on separate connections,
/// but *not* within the same database handle that is being passed in (because
/// the closure is executed in the context of the query).
///
/// Sorting can be done using raw SQL (by passing in a `orderBy` parameter,
/// e.g. `orderBy: "name DESC"`),
/// or just in Swift (e.g. `fetch(in: db).sorted { $0.name > $1.name }`).
/// Since the matching is done in Swift anyways, the primary advantage of
/// doing it in SQL is that a `LIMIT` can be applied efficiently (i.e. w/o
/// walking and loading all rows).
///
/// If the function returns `nil`, the error can be found using the usual
/// `sqlite3_errcode` and companions.
///
/// Example:
/// ```swift
/// let records = sqlite3_apple_notes_fetch(db) { record in
///   record.name != "Duck"
/// }
///
/// let records = sqlite3_apple_notes_fetch(db, orderBy: "name", limit: 5) {
///   $0.firstname != nil
/// }
/// ```
///
/// - Parameters:
///   - db: The SQLite database handle (as returned by `sqlite3_open`)
///   - sql: Optional custom SQL yielding ``AppleNotes`` records.
///   - orderBySQL: If set, some SQL that is added as an `ORDER BY` clause (e.g. `name DESC`).
///   - limit: An optional fetch limit.
///   - filter: A Swift closure used for filtering, taking the``AppleNotes`` record to be matched.
/// - Returns: The records matching the query, or `nil` if there was an error.
@inlinable
public func sqlite3_apple_notes_fetch(
  _ db: OpaquePointer!,
  sql customSQL: String? = nil,
  orderBy orderBySQL: String? = nil,
  limit: Int? = nil,
  filter: @escaping (AppleNotes) -> Bool
) -> [AppleNotes]? {
  withUnsafePointer(to: filter) { (closurePtr) in
    guard
      AppleNotes.Schema.registerSwiftMatcher(
        in: db,
        flags: SQLITE_UTF8,
        matcher: closurePtr
      ) == SQLITE_OK
    else {
      return nil
    }
    defer {
      AppleNotes.Schema.unregisterSwiftMatcher(in: db, flags: SQLITE_UTF8)
    }
    var sql = customSQL ?? AppleNotes.Schema.matchSelect
    if let orderBySQL = orderBySQL {
      sql.append(" ORDER BY \(orderBySQL)")
    }
    if let limit = limit {
      sql.append(" LIMIT \(limit)")
    }
    var handle: OpaquePointer? = nil
    guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
      let statement = handle
    else { return nil }
    defer { sqlite3_finalize(statement) }
    let indices =
      customSQL != nil
      ? AppleNotes.Schema.lookupColumnIndices(in: statement) : AppleNotes.Schema.selectColumnIndices
    var records = [AppleNotes]()
    while true {
      let rc = sqlite3_step(statement)
      if rc == SQLITE_DONE {
        break
      } else if rc != SQLITE_ROW {
        return nil
      }
      records.append(AppleNotes(statement, indices: indices))
    }
    return records
  }
}

/// Fetch ``AppleNotes`` records using the base SQLite API.
///
/// If the function returns `nil`, the error can be found using the usual
/// `sqlite3_errcode` and companions.
///
/// Example:
/// ```swift
/// let records = sqlite3_apple_notes_fetch(
///   db, sql: #"SELECT * FROM apple_notes"#
/// }
///
/// let records = sqlite3_apple_notes_fetch(
///   db, sql: #"SELECT * FROM apple_notes"#,
///   orderBy: "name", limit: 5
/// )
/// ```
///
/// - Parameters:
///   - db: The SQLite database handle (as returned by `sqlite3_open`)
///   - sql: Custom SQL yielding ``AppleNotes`` records.
///   - orderBySQL: If set, some SQL that is added as an `ORDER BY` clause (e.g. `name DESC`).
///   - limit: An optional fetch limit.
/// - Returns: The records matching the query, or `nil` if there was an error.
@inlinable
public func sqlite3_apple_notes_fetch(
  _ db: OpaquePointer!,
  sql customSQL: String? = nil,
  orderBy orderBySQL: String? = nil,
  limit: Int? = nil
) -> [AppleNotes]? {
  var sql = customSQL ?? AppleNotes.Schema.select
  if let orderBySQL = orderBySQL {
    sql.append(" ORDER BY \(orderBySQL)")
  }
  if let limit = limit {
    sql.append(" LIMIT \(limit)")
  }
  var handle: OpaquePointer? = nil
  guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK,
    let statement = handle
  else { return nil }
  defer { sqlite3_finalize(statement) }
  let indices =
    customSQL != nil
    ? AppleNotes.Schema.lookupColumnIndices(in: statement) : AppleNotes.Schema.selectColumnIndices
  var records = [AppleNotes]()
  while true {
    let rc = sqlite3_step(statement)
    if rc == SQLITE_DONE {
      break
    } else if rc != SQLITE_ROW {
      return nil
    }
    records.append(AppleNotes(statement, indices: indices))
  }
  return records
}

/// A structure representing a SQLite database.
///
/// ### Database Schema
///
/// The schema captures the SQLite table/view catalog as safe Swift types.
///
/// #### Tables
///
/// - ``Readwise``   (SQL: `readwise`)
/// - ``ApiKeys``    (SQL: `api_keys`)
/// - ``AppleNotes`` (SQL: `apple_notes`)
///
/// > Hint: Use [SQL Views](https://www.sqlite.org/lang_createview.html)
/// >       to create Swift types that represent common queries.
/// >       (E.g. joins between tables or fragments of table data.)
///
/// ### Examples
///
/// Perform record operations on ``Readwise`` records:
/// ```swift
/// let records = try await db.readwises.filter(orderBy: \.id) {
///   $0.id != nil
/// }
///
/// try await db.transaction { tx in
///   var record = try tx.readwises.find(2) // find by primaryKey
///
///   record.id = "Hunt"
///   try tx.update(record)
///
///   let newRecord = try tx.insert(record)
///   try tx.delete(newRecord)
/// }
/// ```
///
/// Perform column selects on the `readwise` table:
/// ```swift
/// let values = try await db.select(from: \.readwises, \.id) {
///   $0.in([ 2, 3 ])
/// }
/// ```
///
/// Perform low level operations on ``Readwise`` records:
/// ```swift
/// var db : OpaquePointer?
/// sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil)
///
/// var records = sqlite3_readwises_fetch(db, orderBy: "id", limit: 5) {
///   $0.id != nil
/// }!
/// records[1].id = "Hunt"
/// sqlite3_readwises_update(db, records[1])
///
/// sqlite3_readwises_delete(db, records[0])
/// sqlite3_readwises_insert(db, records[0]) // re-add
/// ```
@dynamicMemberLookup
public struct ApplicationDatabase: SQLDatabase, SQLDatabaseAsyncChangeOperations,
  SQLCreationStatementsHolder
{

  /**
   * Mappings of table/view Swift types to their "reference name".
   *
   * The `RecordTypes` structure contains a variable for the Swift type
   * associated each table/view of the database. It maps the tables
   * "reference names" (e.g. ``readwises``) to the
   * "record type" of the table (e.g. ``Readwise``.self).
   */
  public struct RecordTypes: Swift.Sendable {

    /// Returns the Readwise type information (SQL: `readwise`).
    public let readwises = Readwise.self

    /// Returns the ApiKeys type information (SQL: `api_keys`).
    public let apiKeys = ApiKeys.self

    /// Returns the AppleNotes type information (SQL: `apple_notes`).
    public let appleNotes = AppleNotes.self
  }

  /// Property based access to the ``RecordTypes-swift.struct``.
  public static let recordTypes = RecordTypes()

  #if swift(>=5.7)
    /// All RecordTypes defined in the database.
    public static let _allRecordTypes: [any SQLRecord.Type] = [
      Readwise.self, ApiKeys.self, AppleNotes.self,
    ]
  #endif  // swift(>=5.7)

  /// User version of the database (`PRAGMA user_version`).
  public static let userVersion = 0

  /// Whether `INSERT … RETURNING` should be used (requires SQLite 3.35.0+).
  public static let useInsertReturning = sqlite3_libversion_number() >= 3_035_000

  #if swift(>=5.10)
    /// The `DateFormatter` used for parsing string date values.
    nonisolated(unsafe) static var _dateFormatter: DateFormatter?
  #else
    /// The `DateFormatter` used for parsing string date values.
    static var _dateFormatter: DateFormatter?
  #endif

  /// The `DateFormatter` used for parsing string date values.
  public static var dateFormatter: DateFormatter? {
    set {
      _dateFormatter = newValue
    }
    get {
      _dateFormatter ?? Date.defaultSQLiteDateFormatter
    }
  }

  /// SQL that can be used to recreate the database structure.
  @inlinable
  public static var creationSQL: String {
    var sql = ""
    sql.append(Readwise.Schema.create)
    sql.append(ApiKeys.Schema.create)
    sql.append(AppleNotes.Schema.create)
    return sql
  }

  public static func withOptCString<R>(
    _ s: String?,
    _ body: (UnsafePointer<CChar>?) throws -> R
  ) rethrows -> R {
    if let s = s { return try s.withCString(body) } else { return try body(nil) }
  }

  /// The `connectionHandler` is used to open SQLite database connections.
  public var connectionHandler: SQLConnectionHandler

  /**
   * Initialize ``ApplicationDatabase`` with a `URL`.
   *
   * Configures the database with a simple connection pool opening the
   * specified `URL`.
   * And optional `readOnly` flag can be set (defaults to `false`).
   *
   * Example:
   * ```swift
   * let db = ApplicationDatabase(url: ...)
   *
   * // Write operations will raise an error.
   * let readOnly = ApplicationDatabase(
   *   url: Bundle.module.url(forResource: "samples", withExtension: "db"),
   *   readOnly: true
   * )
   * ```
   *
   * - Parameters:
   *   - url: A `URL` pointing to the database to be used.
   *   - readOnly: Whether the database should be opened readonly (default: `false`).
   */
  @inlinable
  public init(url: URL, readOnly: Bool = false) {
    self.connectionHandler = .simplePool(url: url, readOnly: readOnly)
  }

  /**
   * Initialize ``ApplicationDatabase`` w/ a `SQLConnectionHandler`.
   *
   * `SQLConnectionHandler`'s are used to open SQLite database connections when
   * queries are run using the `Lighter` APIs.
   * The `SQLConnectionHandler` is a protocol and custom handlers
   * can be provided.
   *
   * Example:
   * ```swift
   * let db = ApplicationDatabase(connectionHandler: .simplePool(
   *   url: Bundle.module.url(forResource: "samples", withExtension: "db"),
   *   readOnly: true,
   *   maxAge: 10,
   *   maximumPoolSizePerConfiguration: 4
   * ))
   * ```
   *
   * - Parameters:
   *   - connectionHandler: The `SQLConnectionHandler` to use w/ the database.
   */
  @inlinable
  public init(connectionHandler: SQLConnectionHandler) {
    self.connectionHandler = connectionHandler
  }
}

/// Record representing the `readwise` SQL table.
///
/// Record types represent rows within tables&views in a SQLite database.
/// They are returned by the functions or queries/filters generated by
/// Enlighter.
///
/// ### Examples
///
/// Perform record operations on ``Readwise`` records:
/// ```swift
/// let records = try await db.readwises.filter(orderBy: \.id) {
///   $0.id != nil
/// }
///
/// try await db.transaction { tx in
///   var record = try tx.readwises.find(2) // find by primaryKey
///
///   record.id = "Hunt"
///   try tx.update(record)
///
///   let newRecord = try tx.insert(record)
///   try tx.delete(newRecord)
/// }
/// ```
///
/// Perform column selects on the `readwise` table:
/// ```swift
/// let values = try await db.select(from: \.readwises, \.id) {
///   $0.in([ 2, 3 ])
/// }
/// ```
///
/// Perform low level operations on ``Readwise`` records:
/// ```swift
/// var db : OpaquePointer?
/// sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil)
///
/// var records = sqlite3_readwises_fetch(db, orderBy: "id", limit: 5) {
///   $0.id != nil
/// }!
/// records[1].id = "Hunt"
/// sqlite3_readwises_update(db, records[1])
///
/// sqlite3_readwises_delete(db, records[0])
/// sqlite3_readwises_insert(db, records[0]) // re-add
/// ```
///
/// ### SQL
///
/// The SQL used to create the table associated with the record:
/// ```sql
/// CREATE TABLE readwise(
///     id TEXT PRIMARY KEY NOT NULL,
///     url TEXT NOT NULL,
///     title TEXT,
///     created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
/// )
/// ```
public struct Readwise: Identifiable, SQLKeyedTableRecord, Codable, Sendable {

  /// Static SQL type information for the ``Readwise`` record.
  public static let schema = Schema()

  /// Primary key `id` (`TEXT`), required.
  public var id: String

  /// Column `url` (`TEXT`), required.
  public var url: String

  /// Column `title` (`TEXT`), optional (default: `nil`).
  public var title: String?

  /// Column `created_at` (`DATETIME`), optional.
  public var createdAt: Date?

  /**
   * Initialize a new ``Readwise`` record.
   *
   * - Parameters:
   *   - id: Primary key `id` (`TEXT`), required.
   *   - url: Column `url` (`TEXT`), required.
   *   - title: Column `title` (`TEXT`), optional (default: `nil`).
   *   - createdAt: Column `created_at` (`DATETIME`), optional.
   */
  @inlinable
  public init(id: String, url: String, title: String? = nil, createdAt: Date?) {
    self.id = id
    self.url = url
    self.title = title
    self.createdAt = createdAt
  }
}

/// Record representing the `api_keys` SQL table.
///
/// Record types represent rows within tables&views in a SQLite database.
/// They are returned by the functions or queries/filters generated by
/// Enlighter.
///
/// ### Examples
///
/// Perform record operations on ``ApiKeys`` records:
/// ```swift
/// let records = try await db.apiKeys.filter(orderBy: \.id) {
///   $0.id != nil
/// }
///
/// try await db.transaction { tx in
///   var record = try tx.apiKeys.find(2) // find by primaryKey
///
///   record.id = "Hunt"
///   try tx.update(record)
///
///   let newRecord = try tx.insert(record)
///   try tx.delete(newRecord)
/// }
/// ```
///
/// Perform column selects on the `api_keys` table:
/// ```swift
/// let values = try await db.select(from: \.apiKeys, \.id) {
///   $0.in([ 2, 3 ])
/// }
/// ```
///
/// Perform low level operations on ``ApiKeys`` records:
/// ```swift
/// var db : OpaquePointer?
/// sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil)
///
/// var records = sqlite3_api_keys_fetch(db, orderBy: "id", limit: 5) {
///   $0.id != nil
/// }!
/// records[1].id = "Hunt"
/// sqlite3_api_keys_update(db, records[1])
///
/// sqlite3_api_keys_delete(db, records[0])
/// sqlite3_api_keys_insert(db, records[0]) // re-add
/// ```
///
/// ### SQL
///
/// The SQL used to create the table associated with the record:
/// ```sql
/// CREATE TABLE api_keys(
///     id TEXT PRIMARY KEY NOT NULL,
///     key_value TEXT NOT NULL,
///     created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
/// )
/// ```
public struct ApiKeys: Identifiable, SQLKeyedTableRecord, Codable, Sendable {

  /// Static SQL type information for the ``ApiKeys`` record.
  public static let schema = Schema()

  /// Primary key `id` (`TEXT`), required.
  public var id: String

  /// Column `key_value` (`TEXT`), required.
  public var keyValue: String

  /// Column `created_at` (`DATETIME`), optional.
  public var createdAt: Date?

  /**
   * Initialize a new ``ApiKeys`` record.
   *
   * - Parameters:
   *   - id: Primary key `id` (`TEXT`), required.
   *   - keyValue: Column `key_value` (`TEXT`), required.
   *   - createdAt: Column `created_at` (`DATETIME`), optional.
   */
  @inlinable
  public init(id: String, keyValue: String, createdAt: Date?) {
    self.id = id
    self.keyValue = keyValue
    self.createdAt = createdAt
  }
}

/// Record representing the `apple_notes` SQL table.
///
/// Record types represent rows within tables&views in a SQLite database.
/// They are returned by the functions or queries/filters generated by
/// Enlighter.
///
/// ### Examples
///
/// Perform record operations on ``AppleNotes`` records:
/// ```swift
/// let records = try await db.appleNotes.filter(orderBy: \.id) {
///   $0.id != nil
/// }
///
/// try await db.transaction { tx in
///   var record = try tx.appleNotes.find(2) // find by primaryKey
///
///   record.id = "Hunt"
///   try tx.update(record)
///
///   let newRecord = try tx.insert(record)
///   try tx.delete(newRecord)
/// }
/// ```
///
/// Perform column selects on the `apple_notes` table:
/// ```swift
/// let values = try await db.select(from: \.appleNotes, \.id) {
///   $0.in([ 2, 3 ])
/// }
/// ```
///
/// Perform low level operations on ``AppleNotes`` records:
/// ```swift
/// var db : OpaquePointer?
/// sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil)
///
/// var records = sqlite3_apple_notes_fetch(db, orderBy: "id", limit: 5) {
///   $0.id != nil
/// }!
/// records[1].id = "Hunt"
/// sqlite3_apple_notes_update(db, records[1])
///
/// sqlite3_apple_notes_delete(db, records[0])
/// sqlite3_apple_notes_insert(db, records[0]) // re-add
/// ```
///
/// ### SQL
///
/// The SQL used to create the table associated with the record:
/// ```sql
/// CREATE TABLE apple_notes(
///     id TEXT PRIMARY KEY NOT NULL,
///     title TEXT,
///     created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
/// )
/// ```
public struct AppleNotes: Identifiable, SQLKeyedTableRecord, Codable, Sendable {

  /// Static SQL type information for the ``AppleNotes`` record.
  public static let schema = Schema()

  /// Primary key `id` (`TEXT`), required.
  public var id: String

  /// Column `title` (`TEXT`), optional (default: `nil`).
  public var title: String?

  /// Column `created_at` (`DATETIME`), optional.
  public var createdAt: Date?

  /**
   * Initialize a new ``AppleNotes`` record.
   *
   * - Parameters:
   *   - id: Primary key `id` (`TEXT`), required.
   *   - title: Column `title` (`TEXT`), optional (default: `nil`).
   *   - createdAt: Column `created_at` (`DATETIME`), optional.
   */
  @inlinable
  public init(id: String, title: String? = nil, createdAt: Date?) {
    self.id = id
    self.title = title
    self.createdAt = createdAt
  }
}

extension Readwise {

  /**
   * Static type information for the ``Readwise`` record (`readwise` SQL table).
   *
   * This structure captures the static SQL information associated with the
   * record.
   * It is used for static type lookups and more.
   */
  public struct Schema: SQLKeyedTableSchema, SQLSwiftMatchableSchema, SQLCreatableSchema {

    public typealias PropertyIndices = (
      idx_id: Int32, idx_url: Int32, idx_title: Int32, idx_createdAt: Int32
    )
    public typealias RecordType = Readwise
    public typealias MatchClosureType = (Readwise) -> Bool

    /// The SQL table name associated with the ``Readwise`` record.
    public static let externalName = "readwise"

    /// The number of columns the `readwise` table has.
    public static let columnCount: Int32 = 4

    /// Information on the records primary key (``Readwise/id``).
    public static let primaryKeyColumn = MappedColumn<Readwise, String>(
      externalName: "id",
      defaultValue: "",
      keyPath: \Readwise.id
    )

    /// The SQL used to create the `readwise` table.
    public static let create =
      #"""
      CREATE TABLE readwise(
          id TEXT PRIMARY KEY NOT NULL,
          url TEXT NOT NULL,
          title TEXT,
          created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
      );
      """#

    /// SQL to `SELECT` all columns of the `readwise` table.
    public static let select = #"SELECT "id", "url", "title", "created_at" FROM "readwise""#

    /// SQL fragment representing all columns.
    public static let selectColumns = #""id", "url", "title", "created_at""#

    /// Index positions of the properties in ``selectColumns``.
    public static let selectColumnIndices: PropertyIndices = (0, 1, 2, 3)

    /// SQL to `SELECT` all columns of the `readwise` table using a Swift filter.
    public static let matchSelect =
      #"SELECT "id", "url", "title", "created_at" FROM "readwise" WHERE readwises_swift_match("id", "url", "title", "created_at") != 0"#

    /// SQL to `UPDATE` all columns of the `readwise` table.
    public static let update =
      #"UPDATE "readwise" SET "url" = ?, "title" = ?, "created_at" = ? WHERE "id" = ?"#

    /// Property parameter indicies in the ``update`` SQL
    public static let updateParameterIndices: PropertyIndices = (4, 1, 2, 3)

    /// SQL to `INSERT` a record into the `readwise` table.
    public static let insert =
      #"INSERT INTO "readwise" ( "id", "url", "title", "created_at" ) VALUES ( ?, ?, ?, ? )"#

    /// SQL to `INSERT` a record into the `readwise` table.
    public static let insertReturning =
      #"INSERT INTO "readwise" ( "id", "url", "title", "created_at" ) VALUES ( ?, ?, ?, ? ) RETURNING "id", "url", "title", "created_at""#

    /// Property parameter indicies in the ``insert`` SQL
    public static let insertParameterIndices: PropertyIndices = (1, 2, 3, 4)

    /// SQL to `DELETE` a record from the `readwise` table.
    public static let delete = #"DELETE FROM "readwise" WHERE "id" = ?"#

    /// Property parameter indicies in the ``delete`` SQL
    public static let deleteParameterIndices: PropertyIndices = (1, -1, -1, -1)

    /**
     * Lookup property indices by column name in a statement handle.
     *
     * Properties are ordered in the schema and have a specific index
     * assigned.
     * E.g. if the record has two properties, `id` and `name`,
     * and the query was `SELECT age, readwise_id FROM readwise`,
     * this would return `( idx_id: 1, idx_name: -1 )`.
     * Because the `readwise_id` is in the second position and `name`
     * isn't provided at all.
     *
     * - Parameters:
     *   - statement: A raw SQLite3 prepared statement handle.
     * - Returns: The positions of the properties in the prepared statement.
     */
    @inlinable
    public static func lookupColumnIndices(`in` statement: OpaquePointer!)
      -> PropertyIndices
    {
      var indices: PropertyIndices = (-1, -1, -1, -1)
      for i in 0..<sqlite3_column_count(statement) {
        let col = sqlite3_column_name(statement, i)
        if strcmp(col!, "id") == 0 {
          indices.idx_id = i
        } else if strcmp(col!, "url") == 0 {
          indices.idx_url = i
        } else if strcmp(col!, "title") == 0 {
          indices.idx_title = i
        } else if strcmp(col!, "created_at") == 0 {
          indices.idx_createdAt = i
        }
      }
      return indices
    }

    /**
     * Register the Swift matcher function for the ``Readwise`` record.
     *
     * SQLite Swift matcher functions are used to process `filter` queries
     * and low-level matching w/o the Lighter library.
     *
     * - Parameters:
     *   - unsafeDatabaseHandle: SQLite3 database handle.
     *   - flags: SQLite3 function registration flags, default: `SQLITE_UTF8`
     *   - matcher: A pointer to the Swift closure used to filter the records.
     * - Returns: The result code of `sqlite3_create_function`, e.g. `SQLITE_OK`.
     */
    @inlinable
    @discardableResult
    public static func registerSwiftMatcher(
      `in` unsafeDatabaseHandle: OpaquePointer!,
      flags: Int32 = SQLITE_UTF8,
      matcher: UnsafeRawPointer
    ) -> Int32 {
      func dispatch(
        _ context: OpaquePointer?,
        argc: Int32,
        argv: UnsafeMutablePointer<OpaquePointer?>!
      ) {
        if let closureRawPtr = sqlite3_user_data(context) {
          let closurePtr = closureRawPtr.bindMemory(to: MatchClosureType.self, capacity: 1)
          let indices = Readwise.Schema.selectColumnIndices
          let record = Readwise(
            id: ((indices.idx_id >= 0) && (indices.idx_id < argc)
              ? (sqlite3_value_text(argv[Int(indices.idx_id)]).flatMap(String.init(cString:)))
              : nil) ?? RecordType.schema.id.defaultValue,
            url: ((indices.idx_url >= 0) && (indices.idx_url < argc)
              ? (sqlite3_value_text(argv[Int(indices.idx_url)]).flatMap(String.init(cString:)))
              : nil) ?? RecordType.schema.url.defaultValue,
            title: (indices.idx_title >= 0) && (indices.idx_title < argc)
              ? (sqlite3_value_text(argv[Int(indices.idx_title)]).flatMap(String.init(cString:)))
              : RecordType.schema.title.defaultValue,
            createdAt: (indices.idx_createdAt >= 0) && (indices.idx_createdAt < argc)
              ? (sqlite3_value_type(argv[Int(indices.idx_createdAt)]) == SQLITE_TEXT
                ? (sqlite3_value_text(argv[Int(indices.idx_createdAt)]).flatMap({
                  ApplicationDatabase.dateFormatter?.date(from: String(cString: $0))
                }))
                : Date(
                  timeIntervalSince1970: sqlite3_value_double(argv[Int(indices.idx_createdAt)])
                )) : RecordType.schema.createdAt.defaultValue
          )
          sqlite3_result_int(context, closurePtr.pointee(record) ? 1 : 0)
        } else {
          sqlite3_result_error(context, "Missing Swift matcher closure", -1)
        }
      }
      return sqlite3_create_function(
        unsafeDatabaseHandle,
        "readwises_swift_match",
        Readwise.Schema.columnCount,
        flags,
        UnsafeMutableRawPointer(mutating: matcher),
        dispatch,
        nil,
        nil
      )
    }

    /**
     * Unregister the Swift matcher function for the ``Readwise`` record.
     *
     * SQLite Swift matcher functions are used to process `filter` queries
     * and low-level matching w/o the Lighter library.
     *
     * - Parameters:
     *   - unsafeDatabaseHandle: SQLite3 database handle.
     *   - flags: SQLite3 function registration flags, default: `SQLITE_UTF8`
     * - Returns: The result code of `sqlite3_create_function`, e.g. `SQLITE_OK`.
     */
    @inlinable
    @discardableResult
    public static func unregisterSwiftMatcher(
      `in` unsafeDatabaseHandle: OpaquePointer!,
      flags: Int32 = SQLITE_UTF8
    ) -> Int32 {
      sqlite3_create_function(
        unsafeDatabaseHandle,
        "readwises_swift_match",
        Readwise.Schema.columnCount,
        flags,
        nil,
        nil,
        nil,
        nil
      )
    }

    /// Type information for property ``Readwise/id`` (`id` column).
    public let id = MappedColumn<Readwise, String>(
      externalName: "id",
      defaultValue: "",
      keyPath: \Readwise.id
    )

    /// Type information for property ``Readwise/url`` (`url` column).
    public let url = MappedColumn<Readwise, String>(
      externalName: "url",
      defaultValue: "",
      keyPath: \Readwise.url
    )

    /// Type information for property ``Readwise/title`` (`title` column).
    public let title = MappedColumn<Readwise, String?>(
      externalName: "title",
      defaultValue: nil,
      keyPath: \Readwise.title
    )

    /// Type information for property ``Readwise/createdAt`` (`created_at` column).
    public let createdAt = MappedColumn<Readwise, Date?>(
      externalName: "created_at",
      defaultValue: nil,
      keyPath: \Readwise.createdAt
    )

    #if swift(>=5.7)
      public var _allColumns: [any SQLColumn] { [id, url, title, createdAt] }
    #endif  // swift(>=5.7)

    public init() {
    }
  }

  /**
   * Initialize a ``Readwise`` record from a SQLite statement handle.
   *
   * This initializer allows easy setup of a record structure from an
   * otherwise arbitrarily constructed SQLite prepared statement.
   *
   * If no `indices` are specified, the `Schema/lookupColumnIndices`
   * function will be used to find the positions of the structure properties
   * based on their external name.
   * When looping, it is recommended to do the lookup once, and then
   * provide the `indices` to the initializer.
   *
   * Required values that are missing in the statement are replaced with
   * their assigned default values, i.e. this can even be used to perform
   * partial selects w/ only a minor overhead (the extra space for a
   * record).
   *
   * Example:
   * ```swift
   * var statement : OpaquePointer?
   * sqlite3_prepare_v2(dbHandle, "SELECT * FROM readwise", -1, &statement, nil)
   * while sqlite3_step(statement) == SQLITE_ROW {
   *   let record = Readwise(statement)
   *   print("Fetched:", record)
   * }
   * sqlite3_finalize(statement)
   * ```
   *
   * - Parameters:
   *   - statement: Statement handle as returned by `sqlite3_prepare*` functions.
   *   - indices: Property bindings positions, defaults to `nil` (automatic lookup).
   */
  @inlinable
  public init(_ statement: OpaquePointer!, indices: Schema.PropertyIndices? = nil) {
    let indices = indices ?? Self.Schema.lookupColumnIndices(in: statement)
    let argc = sqlite3_column_count(statement)
    self.init(
      id: ((indices.idx_id >= 0) && (indices.idx_id < argc)
        ? (sqlite3_column_text(statement, indices.idx_id).flatMap(String.init(cString:))) : nil)
        ?? Self.schema.id.defaultValue,
      url: ((indices.idx_url >= 0) && (indices.idx_url < argc)
        ? (sqlite3_column_text(statement, indices.idx_url).flatMap(String.init(cString:))) : nil)
        ?? Self.schema.url.defaultValue,
      title: (indices.idx_title >= 0) && (indices.idx_title < argc)
        ? (sqlite3_column_text(statement, indices.idx_title).flatMap(String.init(cString:)))
        : Self.schema.title.defaultValue,
      createdAt: (indices.idx_createdAt >= 0) && (indices.idx_createdAt < argc)
        ? (sqlite3_column_type(statement, indices.idx_createdAt) == SQLITE_TEXT
          ? (sqlite3_column_text(statement, indices.idx_createdAt).flatMap({
            ApplicationDatabase.dateFormatter?.date(from: String(cString: $0))
          }))
          : Date(
            timeIntervalSince1970: sqlite3_column_double(statement, indices.idx_createdAt)
          )) : Self.schema.createdAt.defaultValue
    )
  }

  /**
   * Bind all ``Readwise`` properties to a prepared statement and call a closure.
   *
   * *Important*: The bindings are only valid within the closure being executed!
   *
   * Example:
   * ```swift
   * var statement : OpaquePointer?
   * sqlite3_prepare_v2(
   *   dbHandle,
   *   #"UPDATE "readwise" SET "url" = ?, "title" = ?, "created_at" = ? WHERE "id" = ?"#,
   *   -1, &statement, nil
   * )
   *
   * let record = Readwise(id: "Hello", url: "World", title: "Duck", createdAt: nil)
   * let ok = record.bind(to: statement, indices: ( 4, 1, 2, 3 )) {
   *   sqlite3_step(statement) == SQLITE_DONE
   * }
   * sqlite3_finalize(statement)
   * ```
   *
   * - Parameters:
   *   - statement: A SQLite3 statement handle as returned by the `sqlite3_prepare*` functions.
   *   - indices: The parameter positions for the bindings.
   *   - execute: Closure executed with bindings applied, bindings _only_ valid within the call!
   * - Returns: Returns the result of the closure that is passed in.
   */
  @inlinable
  @discardableResult
  public func bind<R>(
    to statement: OpaquePointer!,
    indices: Schema.PropertyIndices,
    then execute: () throws -> R
  ) rethrows -> R {
    return try id.withCString { (s) in
      if indices.idx_id >= 0 {
        sqlite3_bind_text(statement, indices.idx_id, s, -1, nil)
      }
      return try url.withCString { (s) in
        if indices.idx_url >= 0 {
          sqlite3_bind_text(statement, indices.idx_url, s, -1, nil)
        }
        return try ApplicationDatabase.withOptCString(title) { (s) in
          if indices.idx_title >= 0 {
            sqlite3_bind_text(statement, indices.idx_title, s, -1, nil)
          }
          if indices.idx_createdAt >= 0 {
            if let createdAt = createdAt {
              sqlite3_bind_double(
                statement,
                indices.idx_createdAt,
                createdAt.timeIntervalSince1970
              )
            } else {
              sqlite3_bind_null(statement, indices.idx_createdAt)
            }
          }
          return try execute()
        }
      }
    }
  }
}

extension ApiKeys {

  /**
   * Static type information for the ``ApiKeys`` record (`api_keys` SQL table).
   *
   * This structure captures the static SQL information associated with the
   * record.
   * It is used for static type lookups and more.
   */
  public struct Schema: SQLKeyedTableSchema, SQLSwiftMatchableSchema, SQLCreatableSchema {

    public typealias PropertyIndices = (idx_id: Int32, idx_keyValue: Int32, idx_createdAt: Int32)
    public typealias RecordType = ApiKeys
    public typealias MatchClosureType = (ApiKeys) -> Bool

    /// The SQL table name associated with the ``ApiKeys`` record.
    public static let externalName = "api_keys"

    /// The number of columns the `api_keys` table has.
    public static let columnCount: Int32 = 3

    /// Information on the records primary key (``ApiKeys/id``).
    public static let primaryKeyColumn = MappedColumn<ApiKeys, String>(
      externalName: "id",
      defaultValue: "",
      keyPath: \ApiKeys.id
    )

    /// The SQL used to create the `api_keys` table.
    public static let create =
      #"""
      CREATE TABLE api_keys(
          id TEXT PRIMARY KEY NOT NULL,
          key_value TEXT NOT NULL,
          created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
      );
      """#

    /// SQL to `SELECT` all columns of the `api_keys` table.
    public static let select = #"SELECT "id", "key_value", "created_at" FROM "api_keys""#

    /// SQL fragment representing all columns.
    public static let selectColumns = #""id", "key_value", "created_at""#

    /// Index positions of the properties in ``selectColumns``.
    public static let selectColumnIndices: PropertyIndices = (0, 1, 2)

    /// SQL to `SELECT` all columns of the `api_keys` table using a Swift filter.
    public static let matchSelect =
      #"SELECT "id", "key_value", "created_at" FROM "api_keys" WHERE apiKeys_swift_match("id", "key_value", "created_at") != 0"#

    /// SQL to `UPDATE` all columns of the `api_keys` table.
    public static let update =
      #"UPDATE "api_keys" SET "key_value" = ?, "created_at" = ? WHERE "id" = ?"#

    /// Property parameter indicies in the ``update`` SQL
    public static let updateParameterIndices: PropertyIndices = (3, 1, 2)

    /// SQL to `INSERT` a record into the `api_keys` table.
    public static let insert =
      #"INSERT INTO "api_keys" ( "id", "key_value", "created_at" ) VALUES ( ?, ?, ? )"#

    /// SQL to `INSERT` a record into the `api_keys` table.
    public static let insertReturning =
      #"INSERT INTO "api_keys" ( "id", "key_value", "created_at" ) VALUES ( ?, ?, ? ) RETURNING "id", "key_value", "created_at""#

    /// Property parameter indicies in the ``insert`` SQL
    public static let insertParameterIndices: PropertyIndices = (1, 2, 3)

    /// SQL to `DELETE` a record from the `api_keys` table.
    public static let delete = #"DELETE FROM "api_keys" WHERE "id" = ?"#

    /// Property parameter indicies in the ``delete`` SQL
    public static let deleteParameterIndices: PropertyIndices = (1, -1, -1)

    /**
     * Lookup property indices by column name in a statement handle.
     *
     * Properties are ordered in the schema and have a specific index
     * assigned.
     * E.g. if the record has two properties, `id` and `name`,
     * and the query was `SELECT age, api_keys_id FROM api_keys`,
     * this would return `( idx_id: 1, idx_name: -1 )`.
     * Because the `api_keys_id` is in the second position and `name`
     * isn't provided at all.
     *
     * - Parameters:
     *   - statement: A raw SQLite3 prepared statement handle.
     * - Returns: The positions of the properties in the prepared statement.
     */
    @inlinable
    public static func lookupColumnIndices(`in` statement: OpaquePointer!)
      -> PropertyIndices
    {
      var indices: PropertyIndices = (-1, -1, -1)
      for i in 0..<sqlite3_column_count(statement) {
        let col = sqlite3_column_name(statement, i)
        if strcmp(col!, "id") == 0 {
          indices.idx_id = i
        } else if strcmp(col!, "key_value") == 0 {
          indices.idx_keyValue = i
        } else if strcmp(col!, "created_at") == 0 {
          indices.idx_createdAt = i
        }
      }
      return indices
    }

    /**
     * Register the Swift matcher function for the ``ApiKeys`` record.
     *
     * SQLite Swift matcher functions are used to process `filter` queries
     * and low-level matching w/o the Lighter library.
     *
     * - Parameters:
     *   - unsafeDatabaseHandle: SQLite3 database handle.
     *   - flags: SQLite3 function registration flags, default: `SQLITE_UTF8`
     *   - matcher: A pointer to the Swift closure used to filter the records.
     * - Returns: The result code of `sqlite3_create_function`, e.g. `SQLITE_OK`.
     */
    @inlinable
    @discardableResult
    public static func registerSwiftMatcher(
      `in` unsafeDatabaseHandle: OpaquePointer!,
      flags: Int32 = SQLITE_UTF8,
      matcher: UnsafeRawPointer
    ) -> Int32 {
      func dispatch(
        _ context: OpaquePointer?,
        argc: Int32,
        argv: UnsafeMutablePointer<OpaquePointer?>!
      ) {
        if let closureRawPtr = sqlite3_user_data(context) {
          let closurePtr = closureRawPtr.bindMemory(to: MatchClosureType.self, capacity: 1)
          let indices = ApiKeys.Schema.selectColumnIndices
          let record = ApiKeys(
            id: ((indices.idx_id >= 0) && (indices.idx_id < argc)
              ? (sqlite3_value_text(argv[Int(indices.idx_id)]).flatMap(String.init(cString:)))
              : nil) ?? RecordType.schema.id.defaultValue,
            keyValue: ((indices.idx_keyValue >= 0) && (indices.idx_keyValue < argc)
              ? (sqlite3_value_text(argv[Int(indices.idx_keyValue)]).flatMap(String.init(cString:)))
              : nil) ?? RecordType.schema.keyValue.defaultValue,
            createdAt: (indices.idx_createdAt >= 0) && (indices.idx_createdAt < argc)
              ? (sqlite3_value_type(argv[Int(indices.idx_createdAt)]) == SQLITE_TEXT
                ? (sqlite3_value_text(argv[Int(indices.idx_createdAt)]).flatMap({
                  ApplicationDatabase.dateFormatter?.date(from: String(cString: $0))
                }))
                : Date(
                  timeIntervalSince1970: sqlite3_value_double(argv[Int(indices.idx_createdAt)])
                )) : RecordType.schema.createdAt.defaultValue
          )
          sqlite3_result_int(context, closurePtr.pointee(record) ? 1 : 0)
        } else {
          sqlite3_result_error(context, "Missing Swift matcher closure", -1)
        }
      }
      return sqlite3_create_function(
        unsafeDatabaseHandle,
        "apiKeys_swift_match",
        ApiKeys.Schema.columnCount,
        flags,
        UnsafeMutableRawPointer(mutating: matcher),
        dispatch,
        nil,
        nil
      )
    }

    /**
     * Unregister the Swift matcher function for the ``ApiKeys`` record.
     *
     * SQLite Swift matcher functions are used to process `filter` queries
     * and low-level matching w/o the Lighter library.
     *
     * - Parameters:
     *   - unsafeDatabaseHandle: SQLite3 database handle.
     *   - flags: SQLite3 function registration flags, default: `SQLITE_UTF8`
     * - Returns: The result code of `sqlite3_create_function`, e.g. `SQLITE_OK`.
     */
    @inlinable
    @discardableResult
    public static func unregisterSwiftMatcher(
      `in` unsafeDatabaseHandle: OpaquePointer!,
      flags: Int32 = SQLITE_UTF8
    ) -> Int32 {
      sqlite3_create_function(
        unsafeDatabaseHandle,
        "apiKeys_swift_match",
        ApiKeys.Schema.columnCount,
        flags,
        nil,
        nil,
        nil,
        nil
      )
    }

    /// Type information for property ``ApiKeys/id`` (`id` column).
    public let id = MappedColumn<ApiKeys, String>(
      externalName: "id",
      defaultValue: "",
      keyPath: \ApiKeys.id
    )

    /// Type information for property ``ApiKeys/keyValue`` (`key_value` column).
    public let keyValue = MappedColumn<ApiKeys, String>(
      externalName: "key_value",
      defaultValue: "",
      keyPath: \ApiKeys.keyValue
    )

    /// Type information for property ``ApiKeys/createdAt`` (`created_at` column).
    public let createdAt = MappedColumn<ApiKeys, Date?>(
      externalName: "created_at",
      defaultValue: nil,
      keyPath: \ApiKeys.createdAt
    )

    #if swift(>=5.7)
      public var _allColumns: [any SQLColumn] { [id, keyValue, createdAt] }
    #endif  // swift(>=5.7)

    public init() {
    }
  }

  /**
   * Initialize a ``ApiKeys`` record from a SQLite statement handle.
   *
   * This initializer allows easy setup of a record structure from an
   * otherwise arbitrarily constructed SQLite prepared statement.
   *
   * If no `indices` are specified, the `Schema/lookupColumnIndices`
   * function will be used to find the positions of the structure properties
   * based on their external name.
   * When looping, it is recommended to do the lookup once, and then
   * provide the `indices` to the initializer.
   *
   * Required values that are missing in the statement are replaced with
   * their assigned default values, i.e. this can even be used to perform
   * partial selects w/ only a minor overhead (the extra space for a
   * record).
   *
   * Example:
   * ```swift
   * var statement : OpaquePointer?
   * sqlite3_prepare_v2(dbHandle, "SELECT * FROM api_keys", -1, &statement, nil)
   * while sqlite3_step(statement) == SQLITE_ROW {
   *   let record = ApiKeys(statement)
   *   print("Fetched:", record)
   * }
   * sqlite3_finalize(statement)
   * ```
   *
   * - Parameters:
   *   - statement: Statement handle as returned by `sqlite3_prepare*` functions.
   *   - indices: Property bindings positions, defaults to `nil` (automatic lookup).
   */
  @inlinable
  public init(_ statement: OpaquePointer!, indices: Schema.PropertyIndices? = nil) {
    let indices = indices ?? Self.Schema.lookupColumnIndices(in: statement)
    let argc = sqlite3_column_count(statement)
    self.init(
      id: ((indices.idx_id >= 0) && (indices.idx_id < argc)
        ? (sqlite3_column_text(statement, indices.idx_id).flatMap(String.init(cString:))) : nil)
        ?? Self.schema.id.defaultValue,
      keyValue: ((indices.idx_keyValue >= 0) && (indices.idx_keyValue < argc)
        ? (sqlite3_column_text(statement, indices.idx_keyValue).flatMap(String.init(cString:)))
        : nil) ?? Self.schema.keyValue.defaultValue,
      createdAt: (indices.idx_createdAt >= 0) && (indices.idx_createdAt < argc)
        ? (sqlite3_column_type(statement, indices.idx_createdAt) == SQLITE_TEXT
          ? (sqlite3_column_text(statement, indices.idx_createdAt).flatMap({
            ApplicationDatabase.dateFormatter?.date(from: String(cString: $0))
          }))
          : Date(
            timeIntervalSince1970: sqlite3_column_double(statement, indices.idx_createdAt)
          )) : Self.schema.createdAt.defaultValue
    )
  }

  /**
   * Bind all ``ApiKeys`` properties to a prepared statement and call a closure.
   *
   * *Important*: The bindings are only valid within the closure being executed!
   *
   * Example:
   * ```swift
   * var statement : OpaquePointer?
   * sqlite3_prepare_v2(
   *   dbHandle,
   *   #"UPDATE "api_keys" SET "key_value" = ?, "created_at" = ? WHERE "id" = ?"#,
   *   -1, &statement, nil
   * )
   *
   * let record = ApiKeys(id: "Hello", keyValue: "World", createdAt: nil)
   * let ok = record.bind(to: statement, indices: ( 3, 1, 2 )) {
   *   sqlite3_step(statement) == SQLITE_DONE
   * }
   * sqlite3_finalize(statement)
   * ```
   *
   * - Parameters:
   *   - statement: A SQLite3 statement handle as returned by the `sqlite3_prepare*` functions.
   *   - indices: The parameter positions for the bindings.
   *   - execute: Closure executed with bindings applied, bindings _only_ valid within the call!
   * - Returns: Returns the result of the closure that is passed in.
   */
  @inlinable
  @discardableResult
  public func bind<R>(
    to statement: OpaquePointer!,
    indices: Schema.PropertyIndices,
    then execute: () throws -> R
  ) rethrows -> R {
    return try id.withCString { (s) in
      if indices.idx_id >= 0 {
        sqlite3_bind_text(statement, indices.idx_id, s, -1, nil)
      }
      return try keyValue.withCString { (s) in
        if indices.idx_keyValue >= 0 {
          sqlite3_bind_text(statement, indices.idx_keyValue, s, -1, nil)
        }
        if indices.idx_createdAt >= 0 {
          if let createdAt = createdAt {
            sqlite3_bind_double(
              statement,
              indices.idx_createdAt,
              createdAt.timeIntervalSince1970
            )
          } else {
            sqlite3_bind_null(statement, indices.idx_createdAt)
          }
        }
        return try execute()
      }
    }
  }
}

extension AppleNotes {

  /**
   * Static type information for the ``AppleNotes`` record (`apple_notes` SQL table).
   *
   * This structure captures the static SQL information associated with the
   * record.
   * It is used for static type lookups and more.
   */
  public struct Schema: SQLKeyedTableSchema, SQLSwiftMatchableSchema, SQLCreatableSchema {

    public typealias PropertyIndices = (idx_id: Int32, idx_title: Int32, idx_createdAt: Int32)
    public typealias RecordType = AppleNotes
    public typealias MatchClosureType = (AppleNotes) -> Bool

    /// The SQL table name associated with the ``AppleNotes`` record.
    public static let externalName = "apple_notes"

    /// The number of columns the `apple_notes` table has.
    public static let columnCount: Int32 = 3

    /// Information on the records primary key (``AppleNotes/id``).
    public static let primaryKeyColumn = MappedColumn<AppleNotes, String>(
      externalName: "id",
      defaultValue: "",
      keyPath: \AppleNotes.id
    )

    /// The SQL used to create the `apple_notes` table.
    public static let create =
      #"""
      CREATE TABLE apple_notes(
          id TEXT PRIMARY KEY NOT NULL,
          title TEXT,
          created_at DATETIME DEFAULT (CURRENT_TIMESTAMP)
      );
      """#

    /// SQL to `SELECT` all columns of the `apple_notes` table.
    public static let select = #"SELECT "id", "title", "created_at" FROM "apple_notes""#

    /// SQL fragment representing all columns.
    public static let selectColumns = #""id", "title", "created_at""#

    /// Index positions of the properties in ``selectColumns``.
    public static let selectColumnIndices: PropertyIndices = (0, 1, 2)

    /// SQL to `SELECT` all columns of the `apple_notes` table using a Swift filter.
    public static let matchSelect =
      #"SELECT "id", "title", "created_at" FROM "apple_notes" WHERE appleNotes_swift_match("id", "title", "created_at") != 0"#

    /// SQL to `UPDATE` all columns of the `apple_notes` table.
    public static let update =
      #"UPDATE "apple_notes" SET "title" = ?, "created_at" = ? WHERE "id" = ?"#

    /// Property parameter indicies in the ``update`` SQL
    public static let updateParameterIndices: PropertyIndices = (3, 1, 2)

    /// SQL to `INSERT` a record into the `apple_notes` table.
    public static let insert =
      #"INSERT INTO "apple_notes" ( "id", "title", "created_at" ) VALUES ( ?, ?, ? )"#

    /// SQL to `INSERT` a record into the `apple_notes` table.
    public static let insertReturning =
      #"INSERT INTO "apple_notes" ( "id", "title", "created_at" ) VALUES ( ?, ?, ? ) RETURNING "id", "title", "created_at""#

    /// Property parameter indicies in the ``insert`` SQL
    public static let insertParameterIndices: PropertyIndices = (1, 2, 3)

    /// SQL to `DELETE` a record from the `apple_notes` table.
    public static let delete = #"DELETE FROM "apple_notes" WHERE "id" = ?"#

    /// Property parameter indicies in the ``delete`` SQL
    public static let deleteParameterIndices: PropertyIndices = (1, -1, -1)

    /**
     * Lookup property indices by column name in a statement handle.
     *
     * Properties are ordered in the schema and have a specific index
     * assigned.
     * E.g. if the record has two properties, `id` and `name`,
     * and the query was `SELECT age, apple_notes_id FROM apple_notes`,
     * this would return `( idx_id: 1, idx_name: -1 )`.
     * Because the `apple_notes_id` is in the second position and `name`
     * isn't provided at all.
     *
     * - Parameters:
     *   - statement: A raw SQLite3 prepared statement handle.
     * - Returns: The positions of the properties in the prepared statement.
     */
    @inlinable
    public static func lookupColumnIndices(`in` statement: OpaquePointer!)
      -> PropertyIndices
    {
      var indices: PropertyIndices = (-1, -1, -1)
      for i in 0..<sqlite3_column_count(statement) {
        let col = sqlite3_column_name(statement, i)
        if strcmp(col!, "id") == 0 {
          indices.idx_id = i
        } else if strcmp(col!, "title") == 0 {
          indices.idx_title = i
        } else if strcmp(col!, "created_at") == 0 {
          indices.idx_createdAt = i
        }
      }
      return indices
    }

    /**
     * Register the Swift matcher function for the ``AppleNotes`` record.
     *
     * SQLite Swift matcher functions are used to process `filter` queries
     * and low-level matching w/o the Lighter library.
     *
     * - Parameters:
     *   - unsafeDatabaseHandle: SQLite3 database handle.
     *   - flags: SQLite3 function registration flags, default: `SQLITE_UTF8`
     *   - matcher: A pointer to the Swift closure used to filter the records.
     * - Returns: The result code of `sqlite3_create_function`, e.g. `SQLITE_OK`.
     */
    @inlinable
    @discardableResult
    public static func registerSwiftMatcher(
      `in` unsafeDatabaseHandle: OpaquePointer!,
      flags: Int32 = SQLITE_UTF8,
      matcher: UnsafeRawPointer
    ) -> Int32 {
      func dispatch(
        _ context: OpaquePointer?,
        argc: Int32,
        argv: UnsafeMutablePointer<OpaquePointer?>!
      ) {
        if let closureRawPtr = sqlite3_user_data(context) {
          let closurePtr = closureRawPtr.bindMemory(to: MatchClosureType.self, capacity: 1)
          let indices = AppleNotes.Schema.selectColumnIndices
          let record = AppleNotes(
            id: ((indices.idx_id >= 0) && (indices.idx_id < argc)
              ? (sqlite3_value_text(argv[Int(indices.idx_id)]).flatMap(String.init(cString:)))
              : nil) ?? RecordType.schema.id.defaultValue,
            title: (indices.idx_title >= 0) && (indices.idx_title < argc)
              ? (sqlite3_value_text(argv[Int(indices.idx_title)]).flatMap(String.init(cString:)))
              : RecordType.schema.title.defaultValue,
            createdAt: (indices.idx_createdAt >= 0) && (indices.idx_createdAt < argc)
              ? (sqlite3_value_type(argv[Int(indices.idx_createdAt)]) == SQLITE_TEXT
                ? (sqlite3_value_text(argv[Int(indices.idx_createdAt)]).flatMap({
                  ApplicationDatabase.dateFormatter?.date(from: String(cString: $0))
                }))
                : Date(
                  timeIntervalSince1970: sqlite3_value_double(argv[Int(indices.idx_createdAt)])
                )) : RecordType.schema.createdAt.defaultValue
          )
          sqlite3_result_int(context, closurePtr.pointee(record) ? 1 : 0)
        } else {
          sqlite3_result_error(context, "Missing Swift matcher closure", -1)
        }
      }
      return sqlite3_create_function(
        unsafeDatabaseHandle,
        "appleNotes_swift_match",
        AppleNotes.Schema.columnCount,
        flags,
        UnsafeMutableRawPointer(mutating: matcher),
        dispatch,
        nil,
        nil
      )
    }

    /**
     * Unregister the Swift matcher function for the ``AppleNotes`` record.
     *
     * SQLite Swift matcher functions are used to process `filter` queries
     * and low-level matching w/o the Lighter library.
     *
     * - Parameters:
     *   - unsafeDatabaseHandle: SQLite3 database handle.
     *   - flags: SQLite3 function registration flags, default: `SQLITE_UTF8`
     * - Returns: The result code of `sqlite3_create_function`, e.g. `SQLITE_OK`.
     */
    @inlinable
    @discardableResult
    public static func unregisterSwiftMatcher(
      `in` unsafeDatabaseHandle: OpaquePointer!,
      flags: Int32 = SQLITE_UTF8
    ) -> Int32 {
      sqlite3_create_function(
        unsafeDatabaseHandle,
        "appleNotes_swift_match",
        AppleNotes.Schema.columnCount,
        flags,
        nil,
        nil,
        nil,
        nil
      )
    }

    /// Type information for property ``AppleNotes/id`` (`id` column).
    public let id = MappedColumn<AppleNotes, String>(
      externalName: "id",
      defaultValue: "",
      keyPath: \AppleNotes.id
    )

    /// Type information for property ``AppleNotes/title`` (`title` column).
    public let title = MappedColumn<AppleNotes, String?>(
      externalName: "title",
      defaultValue: nil,
      keyPath: \AppleNotes.title
    )

    /// Type information for property ``AppleNotes/createdAt`` (`created_at` column).
    public let createdAt = MappedColumn<AppleNotes, Date?>(
      externalName: "created_at",
      defaultValue: nil,
      keyPath: \AppleNotes.createdAt
    )

    #if swift(>=5.7)
      public var _allColumns: [any SQLColumn] { [id, title, createdAt] }
    #endif  // swift(>=5.7)

    public init() {
    }
  }

  /**
   * Initialize a ``AppleNotes`` record from a SQLite statement handle.
   *
   * This initializer allows easy setup of a record structure from an
   * otherwise arbitrarily constructed SQLite prepared statement.
   *
   * If no `indices` are specified, the `Schema/lookupColumnIndices`
   * function will be used to find the positions of the structure properties
   * based on their external name.
   * When looping, it is recommended to do the lookup once, and then
   * provide the `indices` to the initializer.
   *
   * Required values that are missing in the statement are replaced with
   * their assigned default values, i.e. this can even be used to perform
   * partial selects w/ only a minor overhead (the extra space for a
   * record).
   *
   * Example:
   * ```swift
   * var statement : OpaquePointer?
   * sqlite3_prepare_v2(dbHandle, "SELECT * FROM apple_notes", -1, &statement, nil)
   * while sqlite3_step(statement) == SQLITE_ROW {
   *   let record = AppleNotes(statement)
   *   print("Fetched:", record)
   * }
   * sqlite3_finalize(statement)
   * ```
   *
   * - Parameters:
   *   - statement: Statement handle as returned by `sqlite3_prepare*` functions.
   *   - indices: Property bindings positions, defaults to `nil` (automatic lookup).
   */
  @inlinable
  public init(_ statement: OpaquePointer!, indices: Schema.PropertyIndices? = nil) {
    let indices = indices ?? Self.Schema.lookupColumnIndices(in: statement)
    let argc = sqlite3_column_count(statement)
    self.init(
      id: ((indices.idx_id >= 0) && (indices.idx_id < argc)
        ? (sqlite3_column_text(statement, indices.idx_id).flatMap(String.init(cString:))) : nil)
        ?? Self.schema.id.defaultValue,
      title: (indices.idx_title >= 0) && (indices.idx_title < argc)
        ? (sqlite3_column_text(statement, indices.idx_title).flatMap(String.init(cString:)))
        : Self.schema.title.defaultValue,
      createdAt: (indices.idx_createdAt >= 0) && (indices.idx_createdAt < argc)
        ? (sqlite3_column_type(statement, indices.idx_createdAt) == SQLITE_TEXT
          ? (sqlite3_column_text(statement, indices.idx_createdAt).flatMap({
            ApplicationDatabase.dateFormatter?.date(from: String(cString: $0))
          }))
          : Date(
            timeIntervalSince1970: sqlite3_column_double(statement, indices.idx_createdAt)
          )) : Self.schema.createdAt.defaultValue
    )
  }

  /**
   * Bind all ``AppleNotes`` properties to a prepared statement and call a closure.
   *
   * *Important*: The bindings are only valid within the closure being executed!
   *
   * Example:
   * ```swift
   * var statement : OpaquePointer?
   * sqlite3_prepare_v2(
   *   dbHandle,
   *   #"UPDATE "apple_notes" SET "title" = ?, "created_at" = ? WHERE "id" = ?"#,
   *   -1, &statement, nil
   * )
   *
   * let record = AppleNotes(id: "Hello", title: "World", createdAt: nil)
   * let ok = record.bind(to: statement, indices: ( 3, 1, 2 )) {
   *   sqlite3_step(statement) == SQLITE_DONE
   * }
   * sqlite3_finalize(statement)
   * ```
   *
   * - Parameters:
   *   - statement: A SQLite3 statement handle as returned by the `sqlite3_prepare*` functions.
   *   - indices: The parameter positions for the bindings.
   *   - execute: Closure executed with bindings applied, bindings _only_ valid within the call!
   * - Returns: Returns the result of the closure that is passed in.
   */
  @inlinable
  @discardableResult
  public func bind<R>(
    to statement: OpaquePointer!,
    indices: Schema.PropertyIndices,
    then execute: () throws -> R
  ) rethrows -> R {
    return try id.withCString { (s) in
      if indices.idx_id >= 0 {
        sqlite3_bind_text(statement, indices.idx_id, s, -1, nil)
      }
      return try ApplicationDatabase.withOptCString(title) { (s) in
        if indices.idx_title >= 0 {
          sqlite3_bind_text(statement, indices.idx_title, s, -1, nil)
        }
        if indices.idx_createdAt >= 0 {
          if let createdAt = createdAt {
            sqlite3_bind_double(
              statement,
              indices.idx_createdAt,
              createdAt.timeIntervalSince1970
            )
          } else {
            sqlite3_bind_null(statement, indices.idx_createdAt)
          }
        }
        return try execute()
      }
    }
  }
}

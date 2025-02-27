/// We have many tables in the database, and many different Schemas
/// For Rendering purposes, we need to agree on a set of columns that are relevant for
/// the user. This `GovernorRow` describes the agreed upon relevant columns.
/// Each displayed `Row` will be reduced to a `GoverNow` for rendering.
struct GovernorRow: Identifiable {
  let id: String
  let title: String
}

@MainActor
@Observable
final class Governor {

}

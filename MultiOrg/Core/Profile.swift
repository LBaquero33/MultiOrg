import Foundation

struct Profile: Identifiable, Decodable, Equatable, Sendable {
  let id: UUID
  let role: String
  let full_name: String?
  let avatar_path: String?

  var shortId: String {
    let s = id.uuidString.replacingOccurrences(of: "-", with: "")
    return String(s.prefix(6)).uppercased()
  }

  var displayName: String {
    let trimmed = (full_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return "Player \(shortId)"
  }

  var isCoach: Bool { role.lowercased() == "coach" }
  var isPlayer: Bool { role.lowercased() == "player" }
  var isParent: Bool { role.lowercased() == "parent" }
}

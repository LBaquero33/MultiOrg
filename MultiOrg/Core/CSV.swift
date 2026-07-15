import Foundation

enum CSV {
  // Minimal CSV parser (handles quoted fields with commas + escaped quotes).
  static func parse(text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false

    func endField() {
      row.append(field)
      field = ""
    }
    func endRow() {
      endField()
      rows.append(row)
      row = []
    }

    var i = text.startIndex
    while i < text.endIndex {
      let c = text[i]
      if inQuotes {
        if c == "\"" {
          let next = text.index(after: i)
          if next < text.endIndex, text[next] == "\"" {
            field.append("\"")
            i = next
          } else {
            inQuotes = false
          }
        } else {
          field.append(c)
        }
      } else {
        if c == "\"" {
          inQuotes = true
        } else if c == "," {
          endField()
        } else if c == "\n" {
          endRow()
        } else if c == "\r" {
          // ignore
        } else {
          field.append(c)
        }
      }
      i = text.index(after: i)
    }
    if !field.isEmpty || !row.isEmpty {
      endRow()
    }
    return rows
  }

  private static func norm(_ s: String) -> String {
    // Trim + lowercase + remove BOM if present.
    return s
      .replacingOccurrences(of: "\u{feff}", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  /// Finds the first row index that looks like a header row containing the required column names.
  /// Useful for CSVs that include preamble metadata rows before the actual header row (e.g. Rapsodo exports).
  static func detectHeaderRowIndex(rows: [[String]], requiredColumns: [String]) -> Int? {
    let req = requiredColumns.map(norm).filter { !$0.isEmpty }
    guard !req.isEmpty else { return nil }

    for (idx, row) in rows.enumerated() {
      let cells = Set(row.map(norm))
      if req.allSatisfy({ cells.contains($0) }) {
        return idx
      }
    }
    return nil
  }

  static func asTable(rows: [[String]], headerRowIndex: Int) -> (header: [String], body: [[String]])? {
    guard headerRowIndex >= 0, headerRowIndex < rows.count else { return nil }
    let header = rows[headerRowIndex]
    let body = Array(rows.dropFirst(headerRowIndex + 1)).filter {
      !$0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    return (header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, body)
  }

  static func asTable(rows: [[String]]) -> (header: [String], body: [[String]])? {
    guard let header = rows.first else { return nil }
    let body = Array(rows.dropFirst()).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    return (header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, body)
  }

  /// Convenience wrapper to auto-detect a header row when required columns are provided.
  static func asTableDetectingHeader(rows: [[String]], requiredColumns: [String]) -> (header: [String], body: [[String]])? {
    if let idx = detectHeaderRowIndex(rows: rows, requiredColumns: requiredColumns) {
      return asTable(rows: rows, headerRowIndex: idx)
    }
    return asTable(rows: rows)
  }
}

enum CSVFileReader {
  static func readText(from url: URL) throws -> String {
    let hasAccess = url.startAccessingSecurityScopedResource()
    defer {
      if hasAccess { url.stopAccessingSecurityScopedResource() }
    }
    let data = try Data(contentsOf: url)
    if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
      return text
    }
    throw NSError(domain: "CSV", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read the selected file as text."])
  }
}

enum BPImportSource: String, CaseIterable, Identifiable {
  case rapsodo
  case hitrax
  case trackman

  var id: String { rawValue }

  var label: String {
    switch self {
    case .rapsodo: return "Rapsodo"
    case .hitrax: return "HitTrax"
    case .trackman: return "TrackMan"
    }
  }

  static func parse(_ value: String) -> BPImportSource {
    BPImportSource(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .rapsodo
  }
}

struct BPMappedCSVRow {
  var pitch_num: Int?
  var exit_velo: Double?
  var distance: Double?
  var launch_angle: Double?
  var strike_x: Double?
  var strike_z: Double?
  var raw: [String: String]
}

struct BPImportResult {
  let source: BPImportSource
  let header: [String]
  let rows: [BPMappedCSVRow]
}

enum BPImportMapper {
  static func map(text: String, selectedSource: BPImportSource) throws -> BPImportResult {
    let parsed = CSV.parse(text: text)
    guard let table = detectTable(rows: parsed) else {
      throw NSError(domain: "CSV", code: 2, userInfo: [NSLocalizedDescriptionKey: "No usable CSV header row was found."])
    }
    let source = detectSource(header: table.header) ?? selectedSource
    let rows = map(header: table.header, rows: table.body, source: source)
    guard !rows.isEmpty else {
      throw NSError(domain: "CSV", code: 3, userInfo: [NSLocalizedDescriptionKey: "No usable batted-ball rows were found in this \(source.label) file."])
    }
    return BPImportResult(source: source, header: table.header, rows: rows)
  }

  private static func detectTable(rows: [[String]]) -> (header: [String], body: [[String]])? {
    let candidates = [
      ["PitchNo", "PlateLocSide", "ExitSpeed"],
      ["ExitVelocity", "LaunchAngle", "Distance"],
      ["Exit Velo", "Launch Angle", "Distance"],
      ["Velo", "LA", "Dist"],
      ["No", "ExitVelocity", "StrikeZoneX"]
    ]
    for required in candidates {
      if let table = CSV.asTableDetectingHeader(rows: rows, requiredColumns: required), table.header.count > 2 {
        return table
      }
    }
    return CSV.asTable(rows: rows)
  }

  private static func detectSource(header: [String]) -> BPImportSource? {
    let names = Set(header.map(normalize))
    if names.contains("pitchno") && (names.contains("platelocside") || names.contains("contactpositionx")) {
      return .trackman
    }
    if names.contains("strikezonex") || names.contains("contactdepth") { return .rapsodo }
    if names.contains("launchspeed") || names.contains("sprayangle") || (names.contains("velo") && names.contains("la")) {
      return .hitrax
    }
    return nil
  }

  private static func map(header: [String], rows: [[String]], source: BPImportSource) -> [BPMappedCSVRow] {
    func index(_ aliases: [String]) -> Int? {
      let normalizedAliases = aliases.map(normalize)
      return header.enumerated().first { _, headerName in
        let normalizedHeader = normalize(headerName)
        return normalizedAliases.contains(normalizedHeader)
          || normalizedAliases.contains(where: { normalizedHeader.contains($0) })
      }?.offset
    }

    let pitchIndex = index(["PitchNo", "Pitch Num", "PitchNumber", "No"])
    let exitVeloIndex: Int?
    let distanceIndex: Int?
    let launchAngleIndex: Int?
    let xIndex: Int?
    let zIndex: Int?

    switch source {
    case .trackman:
      exitVeloIndex = index(["ExitSpeed", "Exit Velocity", "ExitVelo"])
      distanceIndex = index(["Distance"])
      launchAngleIndex = index(["Angle", "LaunchAngle", "Launch Angle"])
      xIndex = index(["PlateLocSide", "StrikeZoneX"])
      zIndex = index(["PlateLocHeight", "StrikeZoneY"])
    case .rapsodo:
      exitVeloIndex = index(["ExitVelocity", "Exit Velocity", "ExitVelo", "Exit Velo"])
      distanceIndex = index(["Distance", "Carry"])
      launchAngleIndex = index(["LaunchAngle", "Launch Angle"])
      xIndex = index(["StrikeZoneX", "PlateLocSide", "Strike X"])
      zIndex = index(["StrikeZoneY", "PlateLocHeight", "Strike Z"])
    case .hitrax:
      exitVeloIndex = index(["ExitVelocity", "Exit Velocity", "ExitVelo", "Exit Velo", "LaunchSpeed", "Velo"])
      distanceIndex = index(["Distance", "Carry", "HitDistance", "Dist"])
      launchAngleIndex = index(["LaunchAngle", "Launch Angle", "Angle", "LA"])
      xIndex = index(["PlateLocSide", "StrikeZoneX", "ZoneX", "Horizontal Distance", "POI X"])
      zIndex = index(["PlateLocHeight", "StrikeZoneY", "ZoneY", "Vertical Distance", "POI Z", "POI Y"])
    }

    return rows.enumerated().compactMap { offset, row in
      var raw: [String: String] = ["import_source": source.rawValue]
      for (index, headerName) in header.enumerated() where index < row.count {
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { raw[headerName.trimmingCharacters(in: .whitespacesAndNewlines)] = value }
      }
      let mapped = BPMappedCSVRow(
        pitch_num: valueInt(row, pitchIndex) ?? offset + 1,
        exit_velo: valueDouble(row, exitVeloIndex),
        distance: valueDouble(row, distanceIndex),
        launch_angle: valueDouble(row, launchAngleIndex),
        strike_x: valueDouble(row, xIndex),
        strike_z: valueDouble(row, zIndex),
        raw: raw
      )
      guard mapped.exit_velo != nil || mapped.distance != nil || mapped.launch_angle != nil || mapped.strike_x != nil || mapped.strike_z != nil else { return nil }
      return mapped
    }
  }

  private static func valueDouble(_ row: [String], _ index: Int?) -> Double? {
    guard let index, index < row.count else { return nil }
    let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value != "-" else { return nil }
    return Double(value.replacingOccurrences(of: ",", with: ""))
  }

  private static func valueInt(_ row: [String], _ index: Int?) -> Int? {
    guard let index, index < row.count else { return nil }
    let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value != "-" else { return nil }
    return Int(value) ?? Double(value).map(Int.init)
  }

  private static func normalize(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\u{feff}", with: "")
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: ".", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }
}

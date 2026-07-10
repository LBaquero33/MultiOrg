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

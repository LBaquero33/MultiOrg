import Foundation
@preconcurrency import AVFoundation

enum CompatibleVideoTranscoder {
  static let maximumBytes = 262_144_000

  static func mp4Data(from sourceData: Data, sourceExtension: String) async throws -> Data {
    guard sourceData.count <= maximumBytes else {
      throw TranscodeError.tooLarge
    }

    if sourceExtension.lowercased() == "mp4" {
      return sourceData
    }

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("homeplate-video-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let inputURL = directory.appendingPathComponent("source.\(sourceExtension.isEmpty ? "mov" : sourceExtension)")
    let outputURL = directory.appendingPathComponent("compatible.mp4")
    try sourceData.write(to: inputURL, options: .atomic)

    let asset = AVURLAsset(url: inputURL)
    guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
      throw TranscodeError.exportUnavailable
    }
    guard exporter.supportedFileTypes.contains(.mp4) else {
      throw TranscodeError.unsupported
    }

    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = true

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      exporter.exportAsynchronously {
        switch exporter.status {
        case .completed:
          continuation.resume()
        case .failed, .cancelled:
          continuation.resume(throwing: exporter.error ?? TranscodeError.failed)
        default:
          continuation.resume(throwing: TranscodeError.failed)
        }
      }
    }

    let outputData = try Data(contentsOf: outputURL)
    guard !outputData.isEmpty, outputData.count <= maximumBytes else {
      throw outputData.count > maximumBytes ? TranscodeError.tooLarge : TranscodeError.failed
    }
    return outputData
  }
}

extension CompatibleVideoTranscoder {
  enum TranscodeError: LocalizedError {
    case tooLarge
    case exportUnavailable
    case unsupported
    case failed

    var errorDescription: String? {
      switch self {
      case .tooLarge:
        return "Videos must be 250 MB or smaller after preparation."
      case .exportUnavailable, .unsupported:
        return "That video cannot be converted to a compatible MP4 file."
      case .failed:
        return "That video could not be prepared. Try another clip."
      }
    }
  }
}

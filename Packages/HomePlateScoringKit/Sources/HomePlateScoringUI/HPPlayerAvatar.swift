import Foundation
import HomePlateScoringCore
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias HPPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias HPPlatformImage = NSImage
#endif

/// A photo treatment shared by the matchup strip and defensive field markers.
///
/// The bundled portrait is drawn synchronously. A configured remote portrait is
/// allowed to replace it only after a memory/disk-cached image has been decoded,
/// so the scoring surface never waits on the network to become usable.
public struct HPPlayerAvatar: View {
  private let player: Player?
  private let size: CGFloat
  private let emphasized: Bool

  @State private var remoteImageData: Data?

  public init(player: Player?, size: CGFloat = 38, emphasized: Bool = false) {
    self.player = player
    self.size = size
    self.emphasized = emphasized
  }

  public var body: some View {
    avatarContent
      .frame(width: size, height: size)
      .background(HPTheme.ColorToken.surfaceRaised)
      .clipShape(Circle())
      .overlay(
        Circle().stroke(
          emphasized ? HPTheme.ColorToken.gold : HPTheme.ColorToken.borderStrong,
          lineWidth: emphasized ? 2 : 1
        )
      )
      .accessibilityHidden(true)
      .task(id: remoteIdentity) {
        remoteImageData = nil
        guard let photo = player?.photo, photo.remoteURL != nil else { return }
        remoteImageData = await HPAvatarRemoteCache.shared.data(for: photo)
      }
  }

  @ViewBuilder private var avatarContent: some View {
    if let remoteImageData, let image = platformImage(data: remoteImageData) {
      platformImageView(image)
        .resizable()
        .scaledToFill()
    } else if let name = player?.photo?.bundledAssetName,
              let image = HPBundledAvatarCache.image(named: name) {
      platformImageView(image)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        LinearGradient(
          colors: [HPTheme.ColorToken.fieldGreen.opacity(0.72), HPTheme.ColorToken.surfaceRaised],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        Text(initials)
          .font(.system(size: max(11, size * 0.31), weight: .black, design: .rounded))
          .foregroundStyle(HPTheme.ColorToken.text)
      }
    }
  }

  private var initials: String {
    guard let player else { return "HP" }
    let values = [player.firstName.first, player.lastName.first].compactMap { $0 }
    return values.isEmpty ? "#\(player.jerseyNumber)" : String(values)
  }

  private var remoteIdentity: String? {
    guard let photo = player?.photo, let url = photo.remoteURL else { return nil }
    return photo.cacheKey ?? url.absoluteString
  }

  private func platformImage(data: Data) -> HPPlatformImage? {
    #if canImport(UIKit)
    UIImage(data: data)
    #elseif canImport(AppKit)
    NSImage(data: data)
    #endif
  }

  @ViewBuilder private func platformImageView(_ image: HPPlatformImage) -> Image {
    #if canImport(UIKit)
    Image(uiImage: image)
    #elseif canImport(AppKit)
    Image(nsImage: image)
    #endif
  }
}

@MainActor private enum HPBundledAvatarCache {
  private static let cache = NSCache<NSString, HPPlatformImage>()

  static func image(named name: String) -> HPPlatformImage? {
    if let cached = cache.object(forKey: name as NSString) { return cached }
    let candidates = [
      Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "PlayerHeadshots"),
      Bundle.module.url(forResource: name, withExtension: "png"),
    ]
    guard let url = candidates.compactMap({ $0 }).first,
          let image = HPPlatformImage(contentsOfFile: url.path) else { return nil }
    cache.setObject(image, forKey: name as NSString)
    return image
  }
}

private actor HPAvatarRemoteCache {
  static let shared = HPAvatarRemoteCache()

  private var memory: [String: Data] = [:]
  private let folder: URL?

  init() {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    folder = base?.appendingPathComponent("HomePlateScoringLab/PlayerPhotos", isDirectory: true)
    if let folder { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
  }

  func data(for reference: PlayerPhotoReference) async -> Data? {
    guard let remoteURL = reference.remoteURL else { return nil }
    let key = reference.cacheKey ?? remoteURL.absoluteString
    if let cached = memory[key] { return cached }

    if let diskURL = diskURL(for: key), let cached = try? Data(contentsOf: diskURL) {
      memory[key] = cached
      return cached
    }

    do {
      let (data, response) = try await URLSession.shared.data(from: remoteURL)
      guard !data.isEmpty,
            (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
            HPPlatformImage(data: data) != nil else { return nil }
      memory[key] = data
      if let diskURL = diskURL(for: key) { try? data.write(to: diskURL, options: .atomic) }
      return data
    } catch {
      return nil
    }
  }

  private func diskURL(for key: String) -> URL? {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in key.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return folder?.appendingPathComponent(String(hash, radix: 16)).appendingPathExtension("img")
  }
}

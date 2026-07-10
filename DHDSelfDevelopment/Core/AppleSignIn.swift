import AuthenticationServices
import CryptoKit
import Foundation
import Security

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

enum AppleSignInError: LocalizedError {
  case missingIdentityToken
  case invalidIdentityToken
  case invalidNonceLength
  case nonceGenerationFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .missingIdentityToken: "Apple Sign-In failed: missing identity token."
    case .invalidIdentityToken: "Apple Sign-In failed: invalid identity token."
    case .invalidNonceLength: "Apple Sign-In could not prepare a secure request. Please try again."
    case .nonceGenerationFailed: "Apple Sign-In could not generate a secure nonce. Please try again."
    }
  }
}

enum Nonce {
  static func randomString(length: Int = 32) throws -> String {
    guard length > 0 else { throw AppleSignInError.invalidNonceLength }
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
      var randoms = [UInt8](repeating: 0, count: 16)
      let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
      if status != errSecSuccess {
        throw AppleSignInError.nonceGenerationFailed(status)
      }

      randoms.forEach { random in
        if remainingLength == 0 { return }
        if random < charset.count {
          result.append(charset[Int(random)])
          remainingLength -= 1
        }
      }
    }

    return result
  }

  static func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.map { String(format: "%02x", $0) }.joined()
  }
}

@MainActor
final class AppleSignInCoordinator: NSObject {
  private let nonce: String
  private let onComplete: (Result<AppleSignInResult, Error>) -> Void

  init(nonce: String, onComplete: @escaping (Result<AppleSignInResult, Error>) -> Void) {
    self.nonce = nonce
    self.onComplete = onComplete
  }

  func start() {
    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    request.requestedScopes = [.fullName, .email]
    request.nonce = Nonce.sha256(nonce)

    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.presentationContextProvider = self
    controller.performRequests()
  }
}

struct AppleSignInResult: Sendable {
  let idToken: String
  let nonce: String
  let fullName: PersonNameComponents?
  let email: String?
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
  func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      onComplete(.failure(AppleSignInError.missingIdentityToken))
      return
    }
    guard let tokenData = credential.identityToken else {
      onComplete(.failure(AppleSignInError.missingIdentityToken))
      return
    }
    guard let token = String(data: tokenData, encoding: .utf8) else {
      onComplete(.failure(AppleSignInError.invalidIdentityToken))
      return
    }

    onComplete(
      .success(
        AppleSignInResult(
          idToken: token,
          nonce: nonce,
          fullName: credential.fullName,
          email: credential.email
        )
      )
    )
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    onComplete(.failure(error))
  }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    // Best-effort: use the key window.
#if canImport(UIKit)
    return (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow ?? ASPresentationAnchor()
#elseif canImport(AppKit)
    return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
#else
    return ASPresentationAnchor()
#endif
  }
}

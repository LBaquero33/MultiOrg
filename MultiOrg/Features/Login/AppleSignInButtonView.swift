import AuthenticationServices
import SwiftUI

struct AppleSignInButtonView: View {
  @EnvironmentObject private var appState: AppState
  @State private var coordinator: AppleSignInCoordinator?
  @State private var isWorking = false

  var body: some View {
    VStack(spacing: 10) {
      SignInWithAppleButton(.signIn) { _ in
        // We drive the request inside our coordinator to control the nonce.
      } onCompletion: { _ in
        // No-op: coordinator handles the real callbacks.
      }
      .signInWithAppleButtonStyle(.black)
      .frame(height: 48)
      .overlay {
        if isWorking {
          ProgressView().tint(.white)
        }
      }
      .onTapGesture {
        guard !isWorking else { return }
        isWorking = true
        let rawNonce: String
        do {
          rawNonce = try Nonce.randomString()
        } catch {
          isWorking = false
          appState.authError = error.localizedDescription
          return
        }
        let coord = AppleSignInCoordinator(nonce: rawNonce) { result in
          Task { @MainActor in
            isWorking = false
            switch result {
            case .failure(let error):
              appState.authError = error.localizedDescription
            case .success(let success):
              let formatter = PersonNameComponentsFormatter()
              let name = success.fullName.map { formatter.string(from: $0) }
              await appState.signInWithApple(idToken: success.idToken, nonce: success.nonce, fullName: name)
            }
          }
        }
        coordinator = coord
        coord.start()
      }
    }
  }
}

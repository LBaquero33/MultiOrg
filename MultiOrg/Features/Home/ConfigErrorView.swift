import SwiftUI

struct ConfigErrorView: View {
  let message: String

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 40))
        .foregroundStyle(.yellow)
      Text("Supabase not configured")
        .font(.title2.bold())
      Text(message)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Text("Fix: copy `Configs/Secrets.example.xcconfig` → `Configs/Secrets.xcconfig`, fill values, then regenerate the project with XcodeGen.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
  }
}


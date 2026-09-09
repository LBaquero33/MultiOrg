import CoreGraphics

/// Auditable layout limits for the scoring surface. Keeping these values out of
/// individual views makes the iPhone space budget and iPad rail width testable.
public enum HPGameDayLayoutMetrics {
  public static let commandBarHeight: CGFloat = 44
  public static let scoreboardHeight: CGFloat = 94
  public static let accessibilityScoreboardHeight: CGFloat = 112
  public static let matchupHeight: CGFloat = 52
  public static let scoringDockHeight: CGFloat = 72
  public static let tabBarMinimumHeight: CGFloat = 48
  public static let tabBarMaximumHeight: CGFloat = 50
  public static let compactMinimumFieldHeight: CGFloat = 390
  public static let compactHorizontalPadding: CGFloat = 8
  public static let actionRailWidth: CGFloat = 350

  public static func compactFieldHeight(atScreenWidth width: CGFloat) -> CGFloat {
    let fieldWidth = max(0, width - compactHorizontalPadding * 2)
    return max(compactMinimumFieldHeight, fieldWidth / 0.88)
  }
}

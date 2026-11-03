import SwiftUI
import WidgetKit

/// The DrivalryWidgets extension: one Live Activity (docs/04 §2). This target
/// is created in Xcode on the Mac (README-mac.md, "Live Activity"); these
/// sources are then added to it together with
/// `Runner/Tracking/DriveActivityAttributes.swift`.
@main
struct DrivalryWidgetsBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.2, *) {
      DriveLiveActivity()
    }
  }
}

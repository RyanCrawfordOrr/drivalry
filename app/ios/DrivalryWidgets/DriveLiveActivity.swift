import ActivityKit
import SwiftUI
import WidgetKit

/// Lock-screen banner and Dynamic Island for a drive (docs/04 §2).
///
/// Rules: one number per region, no scores, no roasts, no feed. The limit and
/// the current speed come from the on-device pack and GPS; the convoy line
/// appears only during an active convoy.
@available(iOS 16.2, *)
struct DriveLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DriveActivityAttributes.self) { context in
      LockScreenView(state: context.state, startedAt: context.attributes.startedAt)
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          LimitBadge(state: context.state)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          SpeedText(state: context.state)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(DriveText.headline(context.state))
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            if let road = context.state.roadName, !road.isEmpty {
              Text(road).font(.caption).lineLimit(1)
            }
            Text(DriveText.footer(context.state, startedAt: context.attributes.startedAt))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            if let convoy = DriveText.convoyLine(context.state) {
              Text(convoy).font(.caption).lineLimit(1)
            }
          }
        }
      } compactLeading: {
        LimitBadge(state: context.state)
      } compactTrailing: {
        SpeedText(state: context.state)
      } minimal: {
        LimitBadge(state: context.state)
      }
      .keylineTint(DriveText.tint(context.state))
    }
  }
}

// MARK: - Views

@available(iOS 16.2, *)
private struct LockScreenView: View {
  let state: DriveActivityAttributes.ContentState
  let startedAt: Date?

  var body: some View {
    HStack(spacing: 14) {
      LimitBadge(state: state, large: true)
      VStack(alignment: .leading, spacing: 3) {
        Text(DriveText.headline(state))
          .font(.headline)
          .lineLimit(1)
        if let road = state.roadName, !road.isEmpty {
          Text(road)
            .font(.subheadline)
            .lineLimit(1)
        }
        Text(DriveText.footer(state, startedAt: startedAt))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let convoy = DriveText.convoyLine(state) {
          Text(convoy)
            .font(.caption)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      SpeedText(state: state, large: true)
    }
    .padding(14)
  }
}

/// The posted limit drawn like a US sign (white box, black number); a grey
/// dash when the pack has no limit here.
@available(iOS 16.2, *)
private struct LimitBadge: View {
  let state: DriveActivityAttributes.ContentState
  var large = false

  var body: some View {
    let side: CGFloat = large ? 44 : 24
    ZStack {
      RoundedRectangle(cornerRadius: large ? 6 : 4)
        .fill(Color.white)
      RoundedRectangle(cornerRadius: large ? 6 : 4)
        .strokeBorder(Color.black, lineWidth: large ? 2 : 1.5)
      if let limit = state.limitPosted {
        Text("\(limit)")
          .font(.system(size: large ? 20 : 12, weight: .bold, design: .rounded))
          .foregroundStyle(.black)
          .minimumScaleFactor(0.6)
      } else {
        Text("–")
          .font(.system(size: large ? 20 : 12, weight: .bold))
          .foregroundStyle(.gray)
      }
    }
    .frame(width: side, height: side)
    .accessibilityLabel(state.limitPosted.map { "Limit \($0) \(state.limitUnit)" } ?? "No posted limit")
  }
}

/// Current speed; turns orange when over the limit.
@available(iOS 16.2, *)
private struct SpeedText: View {
  let state: DriveActivityAttributes.ContentState
  var large = false

  var body: some View {
    if let speed = state.speedPosted {
      VStack(spacing: 0) {
        Text("\(speed)")
          .font(.system(size: large ? 28 : 15, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(DriveText.tint(state))
        if large {
          Text(state.limitUnit)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    } else {
      Image(systemName: "car.fill")
        .font(large ? .title2 : .caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Copy

/// All strings in one place so the car rules (short, factual, no roasts) are
/// easy to check.
@available(iOS 16.2, *)
enum DriveText {
  static func headline(_ s: DriveActivityAttributes.ContentState) -> String {
    if let over = s.overBy, over > 0, let limit = s.limitPosted {
      return "\(over) over · limit \(limit)"
    }
    if let limit = s.limitPosted, let speed = s.speedPosted {
      return "Limit \(limit) · \(speed) \(s.limitUnit)"
    }
    if let limit = s.limitPosted {
      return "Limit \(limit) \(s.limitUnit)"
    }
    return s.cleanSoFar ? "Clean so far" : "Recording"
  }

  /// Trip minutes tick between updates: from the trip start when the activity
  /// was opened for this trip, else from the minutes the phone last sent plus
  /// the time since that update. No minutes at all without a trip.
  static func footer(_ s: DriveActivityAttributes.ContentState, startedAt: Date?) -> String {
    var parts: [String] = []
    if s.recording {
      var minutes = s.tripMinutes
      if let startedAt = startedAt {
        minutes = max(minutes, Int(Date().timeIntervalSince(startedAt) / 60))
      } else {
        minutes += max(0, Int(Date().timeIntervalSince(s.updatedAt) / 60))
      }
      parts.append("\(minutes) min")
    }
    if s.cleanSoFar, s.limitPosted != nil {
      parts.append("clean so far")
    }
    if let talking = s.talking, !talking.isEmpty {
      parts.append("\(talking) talking")
    }
    if parts.isEmpty {
      if let convoy = s.convoyName, !convoy.isEmpty { return "Convoy · \(convoy)" }
      return "Drivalry"
    }
    return parts.joined(separator: " · ")
  }

  static func convoyLine(_ s: DriveActivityAttributes.ContentState) -> String? {
    guard let name = s.convoyName, !name.isEmpty else { return nil }
    var parts = ["Convoy \(name)"]
    if let gap = s.gapMinutes {
      parts.append(gap <= 0 ? "leading" : "\(gap) min behind")
    }
    if let eta = s.etaMinutes {
      parts.append("ETA \(eta) min")
    }
    return parts.joined(separator: " · ")
  }

  static func tint(_ s: DriveActivityAttributes.ContentState) -> Color {
    if let over = s.overBy, over > 0 { return .orange }
    return s.cleanSoFar ? .green : .white
  }
}

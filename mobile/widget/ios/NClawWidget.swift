/**
 * nclaw/mobile — iOS WidgetKit Extension (SwiftUI)
 *
 * Purpose: Home screen widget that displays the last AI summary from shared app group storage
 *          and provides a quick-capture button to open the app.
 * Inputs:  Reads lastSummary + captureDeepLink from UserDefaults (app group: group.org.nself.nclaw.widget).
 * Outputs: Widget UI on home screen; tap opens nclaw://capture deep link.
 * Constraints:
 *   - WidgetKit requires iOS 14+.
 *   - App must have shared app group entitlement configured (in Xcode project settings + provisioning profile).
 *   - Widget data is cached; updates occur when app writes to UserDefaults.
 *   - Widget lock screen (iOS 16+) sized at fixed .systemSmall or .systemMedium.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn ios-widget)
 */

import WidgetKit
import SwiftUI

// MARK: - Widget Entry Point

@main
struct NClawWidgetBundle: WidgetBundle {
  var body: some Widget {
    NClawHomeWidget()
  }
}

// MARK: - Widget Definition

struct NClawHomeWidget: Widget {
  let kind: String = "org.nself.nclaw.home-widget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: NClawWidgetProvider()) { entry in
      NClawWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("ɳClaw Summary")
    .description("Quick access to your last conversation and quick capture.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// MARK: - Timeline Entry

struct NClawWidgetEntry: TimelineEntry {
  let date: Date
  let lastSummary: String
  let captureDeepLink: String
}

// MARK: - Timeline Provider

struct NClawWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> NClawWidgetEntry {
    NClawWidgetEntry(
      date: Date(),
      lastSummary: "Loading...",
      captureDeepLink: "nclaw://capture"
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (NClawWidgetEntry) -> Void) {
    let entry = loadWidgetData()
    completion(entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NClawWidgetEntry>) -> Void) {
    // Load data from shared app group storage
    let entry = loadWidgetData()

    // Widget refresh interval: 15 minutes (or when app updates UserDefaults)
    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
    let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

    completion(timeline)
  }

  private func loadWidgetData() -> NClawWidgetEntry {
    let appGroupId = "group.org.nself.nclaw.widget"
    let defaults = UserDefaults(suiteName: appGroupId)

    // Read stored widget data (JSON: { lastSummary, captureDeepLink, updatedAt })
    if let jsonData = defaults?.data(forKey: "nclaw_widget_data"),
       let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
       let lastSummary = dict["lastSummary"] as? String,
       let captureDeepLink = dict["captureDeepLink"] as? String {
      return NClawWidgetEntry(
        date: Date(),
        lastSummary: lastSummary,
        captureDeepLink: captureDeepLink
      )
    }

    // Fallback: no data stored yet
    return NClawWidgetEntry(
      date: Date(),
      lastSummary: "Start a conversation to see summaries here.",
      captureDeepLink: "nclaw://capture"
    )
  }
}

// MARK: - Widget View

struct NClawWidgetEntryView: View {
  var entry: NClawWidgetEntry

  var body: some View {
    ZStack {
      // Background gradient
      LinearGradient(
        gradient: Gradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.18), Color(red: 0.08, green: 0.08, blue: 0.16)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      VStack(alignment: .leading, spacing: 12) {
        // Header: ɳClaw logo/text
        HStack {
          Text("ɳClaw")
            .font(.system(.headline, design: .default))
            .fontWeight(.semibold)
            .foregroundColor(.white)

          Spacer()

          // Refresh indicator (iOS 17+ via @Environment, stubbed for earlier versions)
          Image(systemName: "arrow.clockwise.circle")
            .font(.system(size: 14))
            .foregroundColor(.gray)
        }

        Divider()
          .background(Color.gray.opacity(0.3))

        // Last summary display (truncated for .systemSmall)
        Text(entry.lastSummary)
          .font(.system(.caption, design: .default))
          .lineLimit(2)
          .foregroundColor(.white)
          .multilineTextAlignment(.leading)

        Spacer()

        // Quick capture button
        Link(destination: URL(string: entry.captureDeepLink) ?? URL(fileURLWithPath: "")) {
          HStack {
            Image(systemName: "plus.circle.fill")
              .font(.system(size: 14))

            Text("Quick Capture")
              .font(.system(.caption, design: .default))
              .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .padding(.horizontal, 10)
          .background(Color.blue.opacity(0.8))
          .foregroundColor(.white)
          .cornerRadius(6)
        }
      }
      .padding(12)
    }
    .cornerRadius(12)
  }
}

// MARK: - Preview

#Preview {
  NClawWidgetEntryView(
    entry: NClawWidgetEntry(
      date: Date(),
      lastSummary: "Last chat: How does machine learning work?",
      captureDeepLink: "nclaw://capture"
    )
  )
  .previewContext(WidgetPreviewContext(family: .systemSmall))
}

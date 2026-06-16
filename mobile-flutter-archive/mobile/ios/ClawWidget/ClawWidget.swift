/// F-28-05: iOS WidgetKit extension for nClaw.
///
/// Three sizes: Small (latest topic), Medium (3 recent topics),
/// Large (morning briefing or active topic with messages).
/// Reads shared UserDefaults from App Group `group.com.nself.claw`.

import WidgetKit
import SwiftUI

// MARK: - Data Models

struct ClawTopic: Codable, Identifiable {
    let id: String
    let title: String
    let lastMessage: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case lastMessage = "last_message"
        case updatedAt = "updated_at"
    }
}

struct ClawWidgetData: Codable {
    let recentConversations: [ClawTopic]
    let pendingCount: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case recentConversations = "recent_conversations"
        case pendingCount = "pending_count"
        case updatedAt = "updated_at"
    }
}

// MARK: - Timeline Entry

struct ClawEntry: TimelineEntry {
    let date: Date
    let topics: [ClawTopic]
    let pendingCount: Int
    let isPlaceholder: Bool

    static var placeholder: ClawEntry {
        ClawEntry(
            date: Date(),
            topics: [
                ClawTopic(id: "1", title: "Morning Briefing", lastMessage: "Your day ahead...", updatedAt: ""),
                ClawTopic(id: "2", title: "Project Notes", lastMessage: "Last updated 2h ago", updatedAt: ""),
                ClawTopic(id: "3", title: "Reading List", lastMessage: "3 new items saved", updatedAt: ""),
            ],
            pendingCount: 0,
            isPlaceholder: true
        )
    }
}

// MARK: - Timeline Provider

struct ClawProvider: TimelineProvider {
    private let appGroupId = "group.com.nself.claw"
    private let dataKey = "widget_topics"

    func placeholder(in context: Context) -> ClawEntry {
        ClawEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ClawEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClawEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> ClawEntry {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let jsonString = defaults.string(forKey: dataKey),
              let jsonData = jsonString.data(using: .utf8) else {
            return ClawEntry.placeholder
        }

        do {
            let widgetData = try JSONDecoder().decode(ClawWidgetData.self, from: jsonData)
            return ClawEntry(
                date: Date(),
                topics: widgetData.recentConversations,
                pendingCount: widgetData.pendingCount,
                isPlaceholder: false
            )
        } catch {
            return ClawEntry.placeholder
        }
    }
}

// MARK: - Small Widget (158x158): Latest topic + 1-line summary

struct ClawWidgetSmallView: View {
    let entry: ClawEntry

    var body: some View {
        if let topic = entry.topics.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.indigo)
                        .font(.title3)
                    Spacer()
                    if entry.pendingCount > 0 {
                        Text("\(entry.pendingCount)")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text(topic.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(topic.lastMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding()
            .widgetURL(URL(string: "claw://topic/\(topic.id)"))
        } else {
            VStack {
                Image(systemName: "brain.head.profile")
                    .font(.largeTitle)
                    .foregroundColor(.indigo)
                Text("Open nClaw")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Medium Widget (338x158): 3 recent topics + timestamps

struct ClawWidgetMediumView: View {
    let entry: ClawEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.indigo)
                Text("nClaw")
                    .font(.headline)
                    .foregroundColor(.indigo)
                Spacer()
                if entry.pendingCount > 0 {
                    Text("\(entry.pendingCount) pending")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 4)

            ForEach(entry.topics.prefix(3)) { topic in
                Link(destination: URL(string: "claw://topic/\(topic.id)")!) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(topic.lastMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if !topic.updatedAt.isEmpty {
                            Text(formatTimestamp(topic.updatedAt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if entry.topics.isEmpty {
                Spacer()
                Text("No recent topics")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
        .padding()
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Large Widget (338x354): Morning briefing or active topic

struct ClawWidgetLargeView: View {
    let entry: ClawEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.indigo)
                    .font(.title2)
                Text("nClaw")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.indigo)
                Spacer()
                if entry.pendingCount > 0 {
                    Text("\(entry.pendingCount) pending")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            if let first = entry.topics.first {
                // Featured topic (morning briefing or most recent).
                VStack(alignment: .leading, spacing: 4) {
                    Text(first.title)
                        .font(.headline)
                    Text(first.lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 4)
                .widgetURL(URL(string: "claw://topic/\(first.id)"))

                Divider()
            }

            // Remaining topics.
            ForEach(entry.topics.dropFirst().prefix(4)) { topic in
                Link(destination: URL(string: "claw://topic/\(topic.id)")!) {
                    HStack {
                        Circle()
                            .fill(Color.indigo.opacity(0.3))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(topic.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(topic.lastMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }

            Spacer()

            if entry.topics.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.largeTitle)
                        .foregroundColor(.indigo.opacity(0.5))
                    Text("Start a conversation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding()
    }
}

// MARK: - Widget Configuration

@main
struct ClawWidget: Widget {
    let kind: String = "ClawWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClawProvider()) { entry in
            if #available(iOS 17.0, *) {
                ClawWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ClawWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("nClaw")
        .description("Your recent topics and morning briefing.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ClawWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ClawEntry

    var body: some View {
        switch family {
        case .systemSmall:
            ClawWidgetSmallView(entry: entry)
        case .systemMedium:
            ClawWidgetMediumView(entry: entry)
        case .systemLarge:
            ClawWidgetLargeView(entry: entry)
        default:
            ClawWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Previews

#if DEBUG
struct ClawWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ClawWidgetEntryView(entry: ClawEntry.placeholder)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            ClawWidgetEntryView(entry: ClawEntry.placeholder)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            ClawWidgetEntryView(entry: ClawEntry.placeholder)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif

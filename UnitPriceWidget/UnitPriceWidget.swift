import SwiftUI
import WidgetKit

struct CompareEntry: TimelineEntry {
    let date: Date
    var snapshot: WidgetSnapshot?
}

struct CompareProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompareEntry { CompareEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (CompareEntry) -> Void) {
        completion(CompareEntry(date: .now, snapshot: read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompareEntry>) -> Void) {
        let now = Date()
        let snapshot = read()
        var entries = [CompareEntry(date: now, snapshot: snapshot)]
        if let entitlement = snapshot?.entitlement, !Launch.isFree, !entitlement.purchasedPro,
           entitlement.hasPro(at: now) {
            entries.append(CompareEntry(date: entitlement.trialEnd, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60))))
    }

    private func read() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: Launch.group)?.data(forKey: WidgetSnapshot.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

struct CompareWidgetView: View {
    let entry: CompareEntry

    var body: some View {
        let low = entry.snapshot?.visibleLow(at: entry.date)
        let staple = low.flatMap { _ in entry.snapshot?.staple }
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "tag").font(.title3).accessibilityHidden(true)
            Text(L.t("widget.title")).font(.headline)
            Spacer(minLength: 2)
            if let low, let name = entry.snapshot?.name {
                Text(name).font(.caption).lineLimit(1)
                Text(L.f("price.per", L.money(low.quote.rate * low.display.factor, code: low.currency, precision: 3),
                         low.display.label)).font(.headline.monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
                Text(low.date, style: .date).font(.caption2).foregroundStyle(.secondary)
            } else if entry.snapshot?.entitlement.hasPro(at: entry.date) == true {
                Text(L.t("widget.pinHint")).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(L.t("widget.proHint")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Color(red: 251/255, green: 248/255, blue: 242/255), for: .widget)
        .environment(\.colorScheme, .light)
        .widgetURL(URL(string: staple.map { "unitprice://staple/\($0.uuidString)" } ?? "unitprice://compare"))
    }
}

@main
struct UnitPriceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UnitPriceWidget", provider: CompareProvider()) { entry in
            CompareWidgetView(entry: entry)
        }
        .configurationDisplayName(L.t("widget.title"))
        .description(L.t("widget.description"))
        .supportedFamilies([.systemSmall])
    }
}

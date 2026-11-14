import SwiftUI
import WidgetKit

struct WeatherEntry: TimelineEntry {
    let date: Date
    let snapshot: WeatherSnapshot?
}

struct WeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        let cached = WeatherCache().load()
        completion(WeatherEntry(date: .now, snapshot: cached ?? (context.isPreview ? Self.sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        Task {
            let cache = WeatherCache()
            var snapshot = cache.load()
            // Refresh only when cached data is older than 20 minutes; iOS decides actual reload timing.
            if snapshot == nil || Date().timeIntervalSince(snapshot!.fetchedAt) > 20 * 60 {
                let coordinate = cache.loadLocation() ?? .lombard
                if case .fresh(let s) = await WeatherRepository(service: WeatherService(), cache: cache).refresh(for: coordinate) {
                    snapshot = s
                }
            }
            // One entry per minute for an hour keeps the clocks current without background work.
            // Weather itself is requested again after ~30 minutes; iOS may delay this.
            let start = Calendar.current.date(bySetting: .second, value: 0, of: .now) ?? .now
            let entries = (0..<60).map { WeatherEntry(date: start.addingTimeInterval(Double($0) * 60), snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .after(start.addingTimeInterval(30 * 60))))
        }
    }

    static let sample = WeatherSnapshot(
        locationName: "LOMBARD", latitude: 41.88, longitude: -88.02, source: .noaa,
        stationID: "KDPA", stationName: "DuPage", current: Temperature(fahrenheit: 54),
        observedAt: .now, high: Temperature(fahrenheit: 58), low: Temperature(fahrenheit: 41),
        fetchedAt: .now, observationNote: nil)
}

struct WeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
            Text(s?.locationName ?? "LOMBARD").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.accent)
            if let c = s?.current {
                if family == .systemSmall {
                    Text("\(c.fahrenheitRounded)°F").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("\(c.celsiusRounded)°C").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                } else {
                    Text(c.dualText).font(.system(size: family == .systemLarge ? 44 : 32, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(.white)
                }
            } else {
                Text(s == nil ? "Open app" : "No reading").font(.headline).foregroundStyle(.white.opacity(0.8))
            }
            if let s {
                Text("H \(s.high.fText)/\(s.high.cText)  L \(s.low.fText)/\(s.low.cText)")
                    .font(family == .systemSmall ? .caption2 : .footnote).foregroundStyle(.white)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            Spacer(minLength: 0)
            if family == .systemSmall {
                ForEach(CityClock.all) { clock in
                    HStack { Text(clock.name.prefix(3).uppercased()).font(.caption2).foregroundStyle(Theme.secondary)
                        Spacer(); Text(clock.string(at: entry.date)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.white) }
                }
            } else {
                HStack {
                    ForEach(CityClock.all) { clock in
                        VStack(alignment: .leading) {
                            Text(clock.name).font(.caption).foregroundStyle(Theme.secondary)
                            Text(clock.string(at: entry.date)).font(family == .systemLarge ? .title.monospacedDigit().bold() : .title3.monospacedDigit().bold()).foregroundStyle(.white)
                        }
                        if clock != CityClock.all.last { Spacer() }
                    }
                }
            }
            if family == .systemLarge, let s {
                Text([s.source.label, s.stationID.map { "Station \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Theme.background, for: .widget)
    }
}

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeatherDashboardWidget", provider: WeatherProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("Weather Dashboard")
        .description("Lombard temperature, forecast, and Guntur and London times.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct WeatherWidgetBundle: WidgetBundle {
    var body: some Widget { WeatherWidget() }
}

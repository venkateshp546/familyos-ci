import SwiftUI
import WidgetKit

struct CityEntry: Identifiable {
    let city: City
    let snapshot: WeatherSnapshot?
    var id: String { city.id }
    var displayName: String { city.isHome ? (snapshot?.locationName ?? city.name) : city.name }
}

struct WeatherEntry: TimelineEntry {
    let date: Date
    let rows: [CityEntry]
}

extension WidgetFamily {
    /// How many cities fit.
    var rowCount: Int { self == .systemLarge ? 6 : 3 }
}

struct WeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, rows: Self.sampleRows)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        let cache = WeatherCache()
        let rows = cache.loadCities().prefix(context.family.rowCount).map { CityEntry(city: $0, snapshot: cache.load(cityID: $0.id)) }
        let hasData = rows.contains { $0.snapshot != nil }
        completion(WeatherEntry(date: .now, rows: (context.isPreview && !hasData) ? Self.sampleRows : Array(rows)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        let family = context.family
        Task {
            let cache = WeatherCache()
            let cities = Array(cache.loadCities().prefix(family.rowCount))
            var service = WeatherService()
            service.allowOpenMeteoFallback = cache.fallbackEnabled
            let repo = WeatherRepository(service: service, cache: cache)

            // Refresh only cities whose cache is older than 20 minutes; iOS decides actual reload timing.
            var snapshots: [String: WeatherSnapshot] = [:]
            await withTaskGroup(of: (String, WeatherSnapshot?).self) { group in
                for city in cities {
                    group.addTask {
                        let cached = cache.load(cityID: city.id)
                        if let cached, Date().timeIntervalSince(cached.fetchedAt) <= 20 * 60 { return (city.id, cached) }
                        switch await repo.refresh(for: city.coordinate, cityID: city.id) {
                        case .fresh(let s): return (city.id, s)
                        case .cached(let s, _): return (city.id, s)
                        case .failed: return (city.id, nil)
                        }
                    }
                }
                for await (id, s) in group { snapshots[id] = s }
            }
            let rows = cities.map { CityEntry(city: $0, snapshot: snapshots[$0.id] ?? nil) }
            // One entry per minute for an hour keeps the clocks current without background work.
            // Weather is requested again after ~30 minutes; iOS may delay this.
            let start = Calendar.current.date(bySetting: .second, value: 0, of: .now) ?? .now
            let entries = (0..<60).map { WeatherEntry(date: start.addingTimeInterval(Double($0) * 60), rows: rows) }
            completion(Timeline(entries: entries, policy: .after(start.addingTimeInterval(30 * 60))))
        }
    }

    static let sampleRows: [CityEntry] = {
        let now = Date()
        func snap(_ name: String, _ f: Double, _ h: Double, _ l: Double) -> WeatherSnapshot {
            WeatherSnapshot(locationName: name, latitude: 0, longitude: 0, source: .noaa, stationID: nil, stationName: nil,
                            current: Temperature(fahrenheit: f), observedAt: now, high: Temperature(fahrenheit: h),
                            low: Temperature(fahrenheit: l), fetchedAt: now, observationNote: nil)
        }
        return [
            CityEntry(city: City.defaults[0], snapshot: snap("LOMBARD", 54, 58, 41)),
            CityEntry(city: City.defaults[1], snapshot: snap("Guntur", 88, 93, 77)),
            CityEntry(city: City.defaults[2], snapshot: snap("London", 50, 53, 44)),
        ]
    }()
}

/// Three columns per row: name | time | temperature with high/low.
struct WeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    private var large: Bool { family == .systemLarge }
    private var small: Bool { family == .systemSmall }

    var body: some View {
        VStack(spacing: 0) {
            if entry.rows.isEmpty {
                Text("Open app").font(.headline).foregroundStyle(.white.opacity(0.8))
            }
            ForEach(Array(entry.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(.white.opacity(0.15)) }
                rowView(row).frame(maxHeight: .infinity)
            }
            if large, entry.rows.contains(where: { $0.snapshot?.source == .openMeteo }) {
                Text("* Open-Meteo (fallback). Others: NOAA.").font(.caption2).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Theme.background, for: .widget)
    }

    @ViewBuilder private func rowView(_ row: CityEntry) -> some View {
        let s = row.snapshot
        let star = s?.source == .openMeteo ? "*" : ""
        if small {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.displayName).font(.caption.weight(.bold)).foregroundStyle(row.city.isHome ? Theme.accent : Theme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text((s?.current.map { "\($0.fahrenheitRounded)°F" } ?? "—") + star)
                        .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
                Spacer(minLength: 2)
                Text(row.city.clock.string(at: entry.date))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
        } else {
            HStack(spacing: 6) {
                Text(row.displayName)
                    .font(large ? .title3.weight(.bold) : .subheadline.weight(.bold))
                    .foregroundStyle(row.city.isHome ? Theme.accent : .white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.city.clock.string(at: entry.date))
                    .font(.system(size: large ? 24 : 18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: large ? 110 : 84)
                VStack(alignment: .trailing, spacing: 1) {
                    Text((s?.current?.dualText ?? "—") + star)
                        .font(.system(size: large ? 22 : 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let s {
                        Text("H \(s.high.pairText)  L \(s.low.pairText)")
                            .font(large ? .footnote : .caption2).foregroundStyle(Theme.secondary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeatherDashboardWidget", provider: WeatherProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("Weather Dashboard")
        .description("Time and weather for your cities.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct WeatherWidgetBundle: WidgetBundle {
    var body: some Widget { WeatherWidget() }
}

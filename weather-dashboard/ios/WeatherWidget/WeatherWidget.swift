import CoreLocation
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
            Self.refreshHomeLocation(cache)
            let cities = Array(cache.loadCities().prefix(family.rowCount))
            // Fetch only cities whose cache is older than 15 minutes (NOAA stations report about hourly).
            let snapshots = await WeatherRefresher.refresh(cities: cities, cache: cache, maxAge: 15 * 60)
            let rows = cities.map { CityEntry(city: $0, snapshot: snapshots[$0.id]) }
            // Clocks are live (system-rendered), so one entry is enough.
            // Ask iOS to reload in ~20 minutes; it may choose a different time within its budget.
            let entry = WeatherEntry(date: .now, rows: rows)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(20 * 60))))
        }
    }

    /// Widgets may read the system's last known location when the app has location permission
    /// (NSWidgetWantsLocation). This follows you without "Always" or opening the app.
    static func refreshHomeLocation(_ cache: WeatherCache) {
        guard cache.manualLocation == nil else { return }
        let manager = CLLocationManager()
        guard manager.isAuthorizedForWidgetUpdates, let loc = manager.location,
              abs(loc.timestamp.timeIntervalSinceNow) < 6 * 3600 else { return }
        let c = Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, name: nil,
                           timeZoneID: TimeZone.current.identifier)
        cache.saveLocation(c)
        cache.updateHome(c)
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

/// Per row: name | time | temperature | high/low.
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
            footer
            if large, entry.rows.contains(where: { $0.snapshot?.source == .openMeteo }) {
                Text("* Open-Meteo (fallback). Others: NOAA.").font(.caption2).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Theme.background, for: .widget)
    }

    /// "Updated 8:40 AM" plus a tap-to-refresh button.
    private var footer: some View {
        let updated = entry.rows.compactMap { $0.snapshot?.fetchedAt }.max()
        return HStack(spacing: 4) {
            if let updated { Text("Updated \(updated, style: .time)") }
            Spacer()
            Button(intent: RefreshWeatherIntent()) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
        .padding(.top, 2)
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
                Text(entry.date, style: .time).environment(\.timeZone, row.city.clock.timeZone)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
        } else {
            // Four columns: name | time | temperature | high/low.
            HStack(spacing: 8) {
                Text(row.displayName)
                    .font(large ? .title3.weight(.bold) : .subheadline.weight(.bold))
                    .foregroundStyle(row.city.isHome ? Theme.accent : .white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.date, style: .time).environment(\.timeZone, row.city.clock.timeZone)
                    .font(.system(size: large ? 22 : 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: large ? 96 : 70, alignment: .leading)
                Text((s?.current?.dualText ?? "—") + star)
                    .font(.system(size: large ? 19 : 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: large ? 118 : 92, alignment: .trailing)
                // One text block so the two lines sit tight together.
                Text("H \(s?.high.pairText ?? "—")\nL \(s?.low.pairText ?? "—")")
                    .font(large ? .footnote : .caption2).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.trailing).lineSpacing(0).lineLimit(2).minimumScaleFactor(0.6)
                    .frame(width: large ? 72 : 56, alignment: .trailing)
            }
            .padding(.vertical, 4)
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

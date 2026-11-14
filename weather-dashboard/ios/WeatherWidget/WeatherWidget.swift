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

    private var tempSize: CGFloat { family == .systemLarge ? 64 : (family == .systemMedium ? 50 : 36) }
    private var clockSize: CGFloat { family == .systemLarge ? 44 : (family == .systemMedium ? 32 : 17) }

    var body: some View {
        if family == .systemMedium { mediumBody } else { stackedBody }
    }

    /// Medium: weather on the left, both clocks stacked on the right.
    private var mediumBody: some View {
        let s = entry.snapshot
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(s?.locationName ?? "LOMBARD").font(.headline.weight(.bold)).tracking(2).foregroundStyle(Theme.accent)
                Spacer(minLength: 2)
                if let c = s?.current {
                    Text(c.dualText).font(.system(size: 34, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(.white)
                } else {
                    Text(s == nil ? "Open app" : "No reading").font(.title2.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 4)
                if let s {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("H \(s.high.fText) / \(s.high.cText)")
                        Text("L \(s.low.fText) / \(s.low.cText)")
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    .minimumScaleFactor(0.7).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(CityClock.all) { clock in
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(clock.name).font(.subheadline).foregroundStyle(Theme.secondary)
                        Text(clock.string(at: entry.date))
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Theme.background, for: .widget)
    }

    private var stackedBody: some View {
        let s = entry.snapshot
        return VStack(alignment: .leading, spacing: 0) {
            Text(s?.locationName ?? "LOMBARD")
                .font(family == .systemSmall ? .footnote.weight(.bold) : .headline.weight(.bold))
                .tracking(2).foregroundStyle(Theme.accent)
            Spacer(minLength: 2)
            temperature(s)
            Spacer(minLength: 2)
            highLow(s)
            Spacer(minLength: 2)
            clocks
            if family == .systemLarge, let s {
                Spacer(minLength: 4)
                Text([s.source.label, s.stationID.map { "Station \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Theme.background, for: .widget)
    }

    @ViewBuilder private func temperature(_ s: WeatherSnapshot?) -> some View {
        if let c = s?.current {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(c.fahrenheitRounded)°F").font(.system(size: tempSize, weight: .bold, design: .rounded))
                    Text("\(c.celsiusRounded)°C").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                }.foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
            } else {
                Text(c.dualText).font(.system(size: tempSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(.white)
            }
        } else {
            Text(s == nil ? "Open app" : "No reading").font(.title2.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
        }
    }

    @ViewBuilder private func highLow(_ s: WeatherSnapshot?) -> some View {
        if let s {
            if family == .systemSmall {
                Text("H \(s.high.fText)  L \(s.low.fText)").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .minimumScaleFactor(0.7).lineLimit(1)
            } else {
                HStack {
                    Text("H \(s.high.fText) / \(s.high.cText)")
                    Spacer()
                    Text("L \(s.low.fText) / \(s.low.cText)")
                }
                .font(family == .systemLarge ? .title3.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1)
            }
        }
    }

    private var clocks: some View {
        HStack(alignment: .bottom) {
            ForEach(Array(CityClock.all.enumerated()), id: \.element.id) { index, clock in
                VStack(alignment: index == 0 ? .leading : .trailing, spacing: 0) {
                    Text(family == .systemSmall ? clock.name.prefix(3).uppercased() : clock.name)
                        .font(family == .systemSmall ? .caption2 : .subheadline).foregroundStyle(Theme.secondary)
                    Text(clock.string(at: entry.date))
                        .font(.system(size: clockSize, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                }
                if index == 0 { Spacer(minLength: 4) }
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
        .description("Lombard temperature, forecast, and Guntur and London times.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct WeatherWidgetBundle: WidgetBundle {
    var body: some Widget { WeatherWidget() }
}

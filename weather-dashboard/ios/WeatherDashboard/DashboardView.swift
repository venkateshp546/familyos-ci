import SwiftUI

struct DashboardView: View {
    @StateObject private var model = DashboardModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let msg = model.location.access.message, model.manualLocation == nil {
                        banner(msg, color: .orange)
                    }
                    if let err = model.errorMessage { banner(err, color: .red) }
                    VStack(spacing: 0) {
                        ForEach(model.cities) { city in
                            CityRow(name: model.displayName(city), clock: city.clock,
                                    snapshot: model.snapshots[city.id], isHome: city.isHome)
                            Divider().overlay(.white.opacity(0.15))
                        }
                    }
                    if model.isLoading && model.snapshots.isEmpty {
                        ProgressView("Loading weather…").tint(.white).foregroundStyle(Theme.secondary)
                    }
                    sources
                    Button { Task { await model.refresh() } } label: {
                        Label("Refresh weather", systemImage: "arrow.clockwise").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered).tint(Theme.accent).disabled(model.isLoading)
                }
                .padding(20)
            }
            .refreshable { await model.refresh() }
        }
        .task { model.start() }
        .onChange(of: model.location.coordinate) { _, _ in Task { await model.gpsUpdated() } }
        .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
    }

    private var header: some View {
        HStack {
            Text("WEATHER").font(.headline).tracking(2).foregroundStyle(Theme.accent)
            Spacer()
            if model.isLoading { ProgressView().tint(.white) }
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .tint(Theme.accent).accessibilityLabel("Settings")
        }
    }

    /// Data provenance per city; Open-Meteo is always called out.
    private var sources: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.cities) { city in
                    if let s = model.snapshots[city.id] {
                        Text("\(model.displayName(city)): \(sourceLine(s, now: ctx.date))")
                    }
                }
            }
            .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    private func sourceLine(_ s: WeatherSnapshot, now: Date) -> String {
        var parts = [s.source.label]
        if let id = s.stationID { parts.append("station \(id)") }
        if let age = s.observationAge(now: now) { parts.append("observed \(age)") }
        else if let n = s.observationNote { parts.append(n) }
        return parts.joined(separator: " · ")
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text).font(.footnote).foregroundStyle(color)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Three columns: name | live time | temperature with high/low.
struct CityRow: View {
    let name: String
    let clock: CityClock
    let snapshot: WeatherSnapshot?
    let isHome: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(name).font(.headline).foregroundStyle(isHome ? Theme.accent : .white)
                .lineLimit(2).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .center, spacing: 0) {
                // Ticks each second while the app is active; SwiftUI pauses it in the background.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(clock.string(at: ctx.date, seconds: true))
                        .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                }
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    Text(clock.abbreviation(at: ctx.date)).font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 112)
            VStack(alignment: .trailing, spacing: 2) {
                Group {
                    if let c = snapshot?.current {
                        Text(c.dualText + (snapshot?.source == .openMeteo ? "*" : ""))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    } else {
                        Text(snapshot == nil ? "…" : "No reading").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                if let s = snapshot {
                    Text("H \(s.high.pairText)  L \(s.low.pairText)").font(.caption).foregroundStyle(Theme.secondary)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 14)
    }
}

struct SettingsSheet: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var place = ""
    @State private var newCity = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(model.cities) { c in
                        HStack {
                            Text(model.displayName(c))
                            Spacer()
                            Text(c.isHome ? "Home" : c.zoneID).font(.caption).foregroundStyle(.secondary)
                        }
                        .deleteDisabled(c.isHome)
                    }
                    .onDelete { model.removeCities(at: $0) }
                    TextField("Add city", text: $newCity).textInputAutocapitalization(.words)
                    Button("Add city") {
                        Task { await model.addCity(newCity); if model.cityError == nil { newCity = "" } }
                    }
                    .disabled(newCity.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let e = model.cityError { Text(e).foregroundStyle(.red) }
                } header: { Text("Cities") } footer: { Text("Swipe to delete. Time zone is set automatically. The widget shows the first 3 (medium) or 6 (large).") }

                Section("Home location") {
                    Button("Use GPS") { model.useGPS(); dismiss() }
                    TextField("City or address", text: $place).textInputAutocapitalization(.words)
                    Button("Use this place") { Task { await model.setManual(place); if model.manualError == nil { dismiss() } } }
                        .disabled(place.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let e = model.manualError { Text(e).foregroundStyle(.red) }
                    if let m = model.manualLocation { Text("Manual: \(m.name ?? "custom")").foregroundStyle(.secondary) }
                }
                Section {
                    Toggle("Open-Meteo fallback", isOn: $model.useFallback)
                } footer: {
                    Text("NOAA covers the US only. Elsewhere, or when NOAA is unreachable, Open-Meteo supplies data, marked with * and labeled.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

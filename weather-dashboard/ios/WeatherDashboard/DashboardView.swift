import SwiftUI

struct DashboardView: View {
    @StateObject private var model = DashboardModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    weatherBlock
                    if let msg = model.location.access.message, model.manualLocation == nil {
                        banner(msg, color: .orange)
                    }
                    if let err = model.errorMessage { banner(err, color: .red) }
                    Divider().overlay(.white.opacity(0.2))
                    ForEach(CityClock.all) { ClockRow(clock: $0) }
                    footer
                }
                .padding(24)
            }
            .refreshable { await model.refresh() }
        }
        .task { model.start() }
        .onChange(of: model.location.coordinate) { _, _ in Task { await model.gpsUpdated() } }
        .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
    }

    private var header: some View {
        HStack {
            Text(model.snapshot?.locationName ?? model.effectiveCoordinate.name ?? "LOMBARD")
                .font(.headline).tracking(2).foregroundStyle(Theme.accent)
            Spacer()
            if model.isLoading { ProgressView().tint(.white) }
            Button { showSettings = true } label: { Image(systemName: "location.circle") }
                .tint(Theme.accent).accessibilityLabel("Location settings")
        }
    }

    @ViewBuilder private var weatherBlock: some View {
        if let s = model.snapshot {
            if let c = s.current {
                Text(c.dualText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(.white)
            } else {
                Text("No current reading").font(.title2.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                if let n = s.observationNote { Text(n).font(.footnote).foregroundStyle(Theme.secondary) }
            }
            HStack {
                Text("HIGH \(s.high.fText) / \(s.high.cText)")
                Spacer()
                Text("LOW \(s.low.fText) / \(s.low.cText)")
            }.font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(sourceLine(s, now: ctx.date)).font(.caption).foregroundStyle(Theme.secondary)
            }
        } else if model.isLoading {
            ProgressView("Loading weather…").tint(.white).foregroundStyle(Theme.secondary)
        } else {
            Text("No weather yet").foregroundStyle(Theme.secondary)
        }
    }

    private func sourceLine(_ s: WeatherSnapshot, now: Date) -> String {
        var parts = [s.source.label]
        if let id = s.stationID { parts.append("Station \(id)") }
        if let age = s.observationAge(now: now) { parts.append("observed \(age)") }
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        Button { Task { await model.refresh() } } label: {
            Label("Refresh weather", systemImage: "arrow.clockwise").font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered).tint(Theme.accent).disabled(model.isLoading)
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text).font(.footnote).foregroundStyle(color)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ClockRow: View {
    let clock: CityClock
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(clock.name).font(.title3.weight(.semibold)).foregroundStyle(.white)
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    Text(clock.abbreviation(at: ctx.date)).font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            // Ticks each second while the app is active; SwiftUI pauses it in the background.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(clock.string(at: ctx.date, seconds: true))
                    .font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
            }
        }
    }
}

struct SettingsSheet: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var place = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
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
                    Text("When NOAA is unreachable or does not cover the location, Open-Meteo may supply data. It is always labeled.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

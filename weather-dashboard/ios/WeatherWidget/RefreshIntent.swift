import AppIntents

/// Tap-to-refresh button on the widget (iOS 17+). WidgetKit reloads the timeline afterwards.
struct RefreshWeatherIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Weather"

    func perform() async throws -> some IntentResult {
        let cache = WeatherCache()
        _ = await WeatherRefresher.refresh(cities: cache.loadCities(), cache: cache, maxAge: 0)
        return .result()
    }
}

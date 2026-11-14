import BackgroundTasks
import WidgetKit

/// Opportunistic background refresh. iOS decides if and when it runs (typically a few times a day).
enum BackgroundRefresh {
    static let identifier = "com.vtsapps.weatherdashboard.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run() async {
        let cache = WeatherCache()
        _ = await WeatherRefresher.refresh(cities: cache.loadCities(), cache: cache, maxAge: 10 * 60)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import SwiftUI

@main
struct WeatherDashboardApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView().preferredColorScheme(.dark)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()
            await BackgroundRefresh.run()
        }
    }
}

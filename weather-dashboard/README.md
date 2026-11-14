# Weather Dashboard

Small native iPhone dashboard.

- Lombard weather: NOAA observations and forecast.
- Fahrenheit and Celsius.
- Guntur and London clocks.
- SwiftUI interface.
- Rust static library reserved for shared conversion logic.
- Built remotely on GitHub macOS runners.

The initial build uses a fallback Lombard coordinate. Next iteration adds full CoreLocation authorization and WidgetKit.

iOS controls background widget refresh frequency. The open app updates clocks continuously and fetches weather on launch or manual refresh.

# Weather Dashboard

Native iPhone app plus WidgetKit widget (small, medium, large).

- Lombard weather from NOAA observations (nearest valid station) and official forecast. Open-Meteo is an optional, labeled fallback.
- Fahrenheit and Celsius, Guntur and London clocks.
- Rust core (`rust-core/`) does conversions, observation validation and station sorting; Swift calls it through a cbindgen header.
- Bundle IDs: `com.vtsapps.weatherdashboard` and `com.vtsapps.weatherdashboard.widget`. App Group: `group.com.vtsapps.weatherdashboard`.

## Build
Run the **Build Weather Dashboard IPA** workflow (manual dispatch). It builds Rust, generates the project with XcodeGen, runs tests, builds the IPA, validates it, and publishes it to the `weather-dashboard-latest` release (replaced each run). No signing credentials are used.

## Install with Signulous
1. Download `WeatherDashboard.ipa` from the `weather-dashboard-latest` release.
2. Upload it to Signulous and sign it. Signulous re-signs both the app and the widget.
3. Install from Signulous on the device.
4. If the App Group is not part of your profile, the widget cannot read the app cache and fetches Lombard weather itself.

iOS decides when widgets refresh. Updates are not guaranteed every minute.

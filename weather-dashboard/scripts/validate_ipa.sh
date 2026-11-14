#!/usr/bin/env bash
# Usage: validate_ipa.sh path/to/App.ipa
set -euo pipefail
IPA="$1"
APP_ID="com.vtsapps.weatherdashboard"
WIDGET_ID="com.vtsapps.weatherdashboard.widget"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
unzip -q "$IPA" -d "$W"
APP="$W/Payload/WeatherDashboard.app"
APPEX="$APP/PlugIns/WeatherWidget.appex"
fail() { echo "FAIL: $*" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

[ -d "$APP" ] || fail "missing app bundle"
[ -d "$APPEX" ] || fail "missing widget extension at PlugIns/WeatherWidget.appex"
[ "$(ls "$W/Payload" | wc -l | tr -d ' ')" = "1" ] || fail "Payload must contain exactly one app"
[ "$(plist "$APP/Info.plist" CFBundleIdentifier)" = "$APP_ID" ] || fail "app bundle id"
[ "$(plist "$APPEX/Info.plist" CFBundleIdentifier)" = "$WIDGET_ID" ] || fail "widget bundle id"
[ "$(plist "$APPEX/Info.plist" NSExtension:NSExtensionPointIdentifier)" = "com.apple.widgetkit-extension" ] || fail "widget extension point"
[ -n "$(plist "$APP/Info.plist" NSLocationWhenInUseUsageDescription)" ] || fail "location usage description"
for p in "$APP/Info.plist" "$APPEX/Info.plist"; do
  for k in CFBundleExecutable CFBundleShortVersionString CFBundleVersion MinimumOSVersion; do
    [ -n "$(plist "$p" $k)" ] || fail "$p missing $k"
  done
  plist "$p" CFBundleSupportedPlatforms | grep -q iPhoneOS || fail "$p not iPhoneOS platform"
  plist "$p" CFBundleSupportedPlatforms | grep -qi simulator && fail "$p simulator platform"
done
for bin in "$APP/WeatherDashboard" "$APPEX/WeatherWidget"; do
  [ -f "$bin" ] || fail "missing binary $bin"
  archs=$(lipo -archs "$bin")
  [ "$archs" = "arm64" ] || fail "$bin archs: $archs"
  vtool -show-build "$bin" | grep -q "platform IOS$" || fail "$bin is not built for the iOS device platform"
done
echo "IPA OK"
echo "App    : $APP_ID"
echo "Widget : $WIDGET_ID"
(cd "$W" && find Payload -maxdepth 4 | sort)

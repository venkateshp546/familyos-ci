//! Shared weather calculations and normalization.
//! Exposed to Swift through a C ABI (see `include/weather_core.h`).

/// Observation is usable.
pub const WD_OBS_OK: i32 = 0;
/// Temperature missing or not a finite number.
pub const WD_OBS_MISSING: i32 = 1;
/// Temperature outside the physically plausible range.
pub const WD_OBS_OUT_OF_RANGE: i32 = 2;
/// Timestamp lies in the future beyond clock-skew tolerance.
pub const WD_OBS_FUTURE: i32 = 3;
/// Observation older than the allowed maximum age.
pub const WD_OBS_STALE: i32 = 4;

const MIN_PLAUSIBLE_C: f64 = -90.0;
const MAX_PLAUSIBLE_C: f64 = 60.0;
const FUTURE_TOLERANCE_SECONDS: f64 = 300.0;
const EARTH_RADIUS_KM: f64 = 6371.0088;

/// Convert Celsius to Fahrenheit.
#[no_mangle]
pub extern "C" fn weather_celsius_to_fahrenheit(celsius: f64) -> f64 {
    celsius * 9.0 / 5.0 + 32.0
}

/// Convert Fahrenheit to Celsius.
#[no_mangle]
pub extern "C" fn weather_fahrenheit_to_celsius(fahrenheit: f64) -> f64 {
    (fahrenheit - 32.0) * 5.0 / 9.0
}

/// Classify an observation. `age_seconds` is now minus observation time.
/// Returns one of the `WD_OBS_*` codes.
#[no_mangle]
pub extern "C" fn weather_observation_status(
    temperature_c: f64,
    age_seconds: f64,
    max_age_seconds: f64,
) -> i32 {
    if !temperature_c.is_finite() || !age_seconds.is_finite() {
        return WD_OBS_MISSING;
    }
    if !(MIN_PLAUSIBLE_C..=MAX_PLAUSIBLE_C).contains(&temperature_c) {
        return WD_OBS_OUT_OF_RANGE;
    }
    if age_seconds < -FUTURE_TOLERANCE_SECONDS {
        return WD_OBS_FUTURE;
    }
    if age_seconds > max_age_seconds {
        return WD_OBS_STALE;
    }
    WD_OBS_OK
}

/// Great-circle distance in kilometres.
#[no_mangle]
pub extern "C" fn weather_distance_km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let (p1, p2) = (lat1.to_radians(), lat2.to_radians());
    let dphi = (lat2 - lat1).to_radians();
    let dlambda = (lon2 - lon1).to_radians();
    let a = (dphi / 2.0).sin().powi(2) + p1.cos() * p2.cos() * (dlambda / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_KM * a.sqrt().min(1.0).asin()
}

/// Fill `out_order` with the indices `0..count` sorted by distance to the
/// target point (nearest first). Returns the number written (`count`), or 0
/// for null pointers / zero count.
///
/// # Safety
/// `lats`, `lons` and `out_order` must each point to `count` valid elements.
#[no_mangle]
pub unsafe extern "C" fn weather_sort_by_distance(
    target_lat: f64,
    target_lon: f64,
    lats: *const f64,
    lons: *const f64,
    count: usize,
    out_order: *mut usize,
) -> usize {
    if lats.is_null() || lons.is_null() || out_order.is_null() || count == 0 {
        return 0;
    }
    let lats = std::slice::from_raw_parts(lats, count);
    let lons = std::slice::from_raw_parts(lons, count);
    let out = std::slice::from_raw_parts_mut(out_order, count);
    let mut idx: Vec<(usize, f64)> = (0..count)
        .map(|i| {
            let d = weather_distance_km(target_lat, target_lon, lats[i], lons[i]);
            (i, if d.is_nan() { f64::INFINITY } else { d })
        })
        .collect();
    idx.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap().then(a.0.cmp(&b.0)));
    for (slot, (i, _)) in out.iter_mut().zip(idx) {
        *slot = i;
    }
    count
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn conversions() {
        assert_eq!(weather_celsius_to_fahrenheit(0.0), 32.0);
        assert_eq!(weather_celsius_to_fahrenheit(100.0), 212.0);
        assert!((weather_celsius_to_fahrenheit(-40.0) + 40.0).abs() < 1e-9);
        assert!((weather_fahrenheit_to_celsius(98.6) - 37.0).abs() < 1e-9);
        let c = 21.3;
        assert!((weather_fahrenheit_to_celsius(weather_celsius_to_fahrenheit(c)) - c).abs() < 1e-9);
    }

    #[test]
    fn observation_status() {
        assert_eq!(weather_observation_status(20.0, 600.0, 5400.0), WD_OBS_OK);
        assert_eq!(weather_observation_status(f64::NAN, 0.0, 5400.0), WD_OBS_MISSING);
        assert_eq!(weather_observation_status(80.0, 0.0, 5400.0), WD_OBS_OUT_OF_RANGE);
        assert_eq!(weather_observation_status(-95.0, 0.0, 5400.0), WD_OBS_OUT_OF_RANGE);
        assert_eq!(weather_observation_status(20.0, -3600.0, 5400.0), WD_OBS_FUTURE);
        assert_eq!(weather_observation_status(20.0, -60.0, 5400.0), WD_OBS_OK);
        assert_eq!(weather_observation_status(20.0, 5401.0, 5400.0), WD_OBS_STALE);
    }

    #[test]
    fn distance() {
        // Lombard IL to Chicago O'Hare is roughly 20 km.
        let d = weather_distance_km(41.88, -88.01, 41.98, -87.90);
        assert!(d > 10.0 && d < 20.0, "{d}");
        assert_eq!(weather_distance_km(1.0, 2.0, 1.0, 2.0), 0.0);
    }

    #[test]
    fn sorting() {
        let lats = [42.0, 41.9, 41.0];
        let lons = [-88.0, -88.0, -88.0];
        let mut out = [0usize; 3];
        let n = unsafe {
            weather_sort_by_distance(41.88, -88.0, lats.as_ptr(), lons.as_ptr(), 3, out.as_mut_ptr())
        };
        assert_eq!(n, 3);
        assert_eq!(out, [1, 0, 2]);
        let n = unsafe {
            weather_sort_by_distance(0.0, 0.0, std::ptr::null(), lons.as_ptr(), 3, out.as_mut_ptr())
        };
        assert_eq!(n, 0);
    }
}

use std::ffi::c_double;

/// Convert Celsius to Fahrenheit.
#[no_mangle]
pub extern "C" fn weather_celsius_to_fahrenheit(celsius: c_double) -> c_double {
    celsius * 9.0 / 5.0 + 32.0
}

import XCTest

final class ConversionTests: XCTestCase {
    func testCelsiusToFahrenheitViaRust() {
        XCTAssertEqual(RustCore.celsiusToFahrenheit(0), 32, accuracy: 1e-9)
        XCTAssertEqual(RustCore.celsiusToFahrenheit(100), 212, accuracy: 1e-9)
        XCTAssertEqual(RustCore.celsiusToFahrenheit(-40), -40, accuracy: 1e-9)
    }

    func testFahrenheitToCelsiusViaRust() {
        XCTAssertEqual(RustCore.fahrenheitToCelsius(32), 0, accuracy: 1e-9)
        XCTAssertEqual(RustCore.fahrenheitToCelsius(212), 100, accuracy: 1e-9)
    }

    func testTemperatureDisplay() {
        let t = Temperature(celsius: 21.5)
        XCTAssertEqual(t.fahrenheitRounded, 71)
        XCTAssertEqual(t.celsiusRounded, 22)
        XCTAssertEqual(Temperature(fahrenheit: 54).dualText, "54°F / 12°C")
        let neg = Temperature(celsius: -3.4)
        XCTAssertEqual(neg.celsiusRounded, -3)
        XCTAssertEqual(neg.fahrenheitRounded, 26)
    }

    func testStationSortingUsesRust() {
        let order = RustCore.sortByDistance(latitude: 41.88, longitude: -88.02,
                                            points: [(41.0, -87.0), (41.9, -88.05), (45.0, -90.0)])
        XCTAssertEqual(order, [1, 0, 2])
        XCTAssertEqual(RustCore.sortByDistance(latitude: 0, longitude: 0, points: []), [])
    }
}

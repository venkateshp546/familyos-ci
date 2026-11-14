import XCTest

final class NOAATests: XCTestCase {
    func testDecodesPoint() throws {
        let p = try JSONDecoder().decode(NOAAPointResponse.self, from: Fixtures.point)
        XCTAssertEqual(p.properties.timeZone, "America/Chicago")
        XCTAssertEqual(p.properties.relativeLocation?.properties?.city, "Lombard")
    }

    func testDecodesStationsAndObservation() throws {
        let s = try JSONDecoder().decode(NOAAStationsResponse.self, from: Fixtures.stations)
        XCTAssertEqual(s.features.count, 2)
        XCTAssertEqual(s.features[1].latitude, 41.90)
        let o = try JSONDecoder().decode(NOAAObservationResponse.self, from: Fixtures.observation(temp: "12.5", time: "2026-11-14T17:53:00+00:00"))
        XCTAssertEqual(o.temperatureCelsius, 12.5)
        XCTAssertNotNil(o.timestamp)
    }

    func testFahrenheitObservationUnitIsConverted() throws {
        let o = try JSONDecoder().decode(NOAAObservationResponse.self, from: Fixtures.observation(temp: "50", time: "2026-11-14T17:53:00Z", unit: "wmoUnit:degF"))
        XCTAssertEqual(o.temperatureCelsius!, 10, accuracy: 1e-9)
    }

    func testNearestStationUsedAndBothScalesCorrect() async throws {
        let client = Fixtures.client(observationNear: Fixtures.observation(temp: "12.5", time: "2026-11-14T17:50:00Z"))
        let snap = try await Fixtures.service(client).fetch(for: Fixtures.coordinate)
        XCTAssertEqual(snap.source, .noaa)
        XCTAssertEqual(snap.stationID, "KNEAR")
        XCTAssertEqual(snap.current?.celsius ?? 0, 12.5, accuracy: 1e-9)
        XCTAssertEqual(snap.current?.fahrenheit ?? 0, 54.5, accuracy: 1e-9)
        XCTAssertEqual(snap.locationName, "LOMBARD")
        XCTAssertEqual(snap.high?.fahrenheitRounded, 58)
        XCTAssertEqual(snap.low?.fahrenheitRounded, 41)
        XCTAssertFalse(client.requested.contains { $0.contains("KFAR/observations") }, "nearest valid station must win")
    }

    // MARK: invalid / stale

    func testNullTemperatureSkipsToNextStationWithoutUsingForecast() async throws {
        let client = Fixtures.client(observationNear: Fixtures.observation(temp: "null", time: "2026-11-14T17:50:00Z"))
        let snap = try await Fixtures.service(client).fetch(for: Fixtures.coordinate)
        XCTAssertEqual(snap.stationID, "KFAR")
        XCTAssertEqual(snap.current?.celsius, 10.0)
    }

    func testAllObservationsInvalidLeavesCurrentNilNeverForecast() async throws {
        let client = Fixtures.client(observationNear: Fixtures.observation(temp: "null", time: "2026-11-14T17:50:00Z"))
        client.responses["/stations/KFAR/observations/latest"] = Fixtures.observation(temp: "999", time: "2026-11-14T17:50:00Z")
        let snap = try await Fixtures.service(client).fetch(for: Fixtures.coordinate)
        XCTAssertNil(snap.current)
        XCTAssertNil(snap.stationID)
        XCTAssertNotNil(snap.observationNote)
        XCTAssertEqual(snap.high?.fahrenheitRounded, 58, "forecast still shown as forecast")
    }

    func testQualityControlFailedRejected() async throws {
        let client = Fixtures.client(observationNear: Fixtures.observation(temp: "12.5", time: "2026-11-14T17:50:00Z", qc: "X"))
        let snap = try await Fixtures.service(client).fetch(for: Fixtures.coordinate)
        XCTAssertEqual(snap.stationID, "KFAR")
    }

    func testStaleObservationRejected() async throws {
        let stale = Fixtures.observation(temp: "12.5", time: "2026-11-14T12:00:00Z")
        let client = Fixtures.client(observationNear: stale)
        client.responses["/stations/KFAR/observations/latest"] = stale
        let snap = try await Fixtures.service(client).fetch(for: Fixtures.coordinate)
        XCTAssertNil(snap.current)
        XCTAssertTrue(snap.observationNote?.contains("stale") == true)
    }

    func testFutureTimestampRejected() {
        XCTAssertEqual(RustCore.observationStatus(temperatureC: 10, ageSeconds: -7200, maxAgeSeconds: 5400), .future)
        XCTAssertEqual(RustCore.observationStatus(temperatureC: 10, ageSeconds: 10000, maxAgeSeconds: 5400), .stale)
        XCTAssertEqual(RustCore.observationStatus(temperatureC: nil, ageSeconds: 0, maxAgeSeconds: 5400), .missing)
        XCTAssertEqual(RustCore.observationStatus(temperatureC: 10, ageSeconds: 60, maxAgeSeconds: 5400), .ok)
    }

    // MARK: forecast

    func testMissingForecastPeriodsGiveNilHighLow() async throws {
        let client = Fixtures.client(observationNear: Fixtures.observation(temp: "12.5", time: "2026-11-14T17:50:00Z"),
                                     forecast: #"{"properties":{"periods":[]}}"#.data(using: .utf8)!)
        let snap = try await Fixtures.service(client).fetch(for: Fixtures.coordinate)
        XCTAssertNil(snap.high)
        XCTAssertNil(snap.low)
        XCTAssertNotNil(snap.current)
    }

    func testForecastWithoutPeriodsKeyDoesNotCrash() throws {
        let f = try JSONDecoder().decode(NOAAForecastResponse.self, from: #"{"properties":{}}"#.data(using: .utf8)!)
        let (h, l) = WeatherService.todayHighLow(periods: f.properties.periods ?? [], now: Fixtures.now, timeZone: TimeZone(identifier: "America/Chicago")!)
        XCTAssertNil(h); XCTAssertNil(l)
    }

    func testEveningForecastHasNoDaytimeHigh() throws {
        // At 23:00 local only the night period remains.
        let json = #"""
        {"properties":{"periods":[{"startTime":"2026-11-14T18:00:00-06:00","endTime":"2026-11-15T06:00:00-06:00","isDaytime":false,"temperature":41,"temperatureUnit":"F"}]}}
        """#.data(using: .utf8)!
        let f = try JSONDecoder().decode(NOAAForecastResponse.self, from: json)
        let now = ISO8601.parse("2026-11-15T05:00:00Z")! // 23:00 local on the 14th
        let (h, l) = WeatherService.todayHighLow(periods: f.properties.periods!, now: now, timeZone: TimeZone(identifier: "America/Chicago")!)
        XCTAssertNil(h)
        XCTAssertEqual(l?.fahrenheitRounded, 41)
    }

    // MARK: fallback

    func testNOAAOutageFallsBackToLabeledOpenMeteo() async throws {
        let client = MockClient()
        client.responses["open-meteo"] = #"{"utc_offset_seconds":-21600,"current":{"time":"2026-11-14T12:00","temperature_2m":9.0},"daily":{"temperature_2m_max":[12.0],"temperature_2m_min":[3.0]}}"#.data(using: .utf8)!
        let snap = try await Fixtures.service(client, fallback: true).fetch(for: Fixtures.coordinate)
        XCTAssertEqual(snap.source, .openMeteo)
        XCTAssertEqual(snap.source.label, "Open-Meteo (fallback)")
        XCTAssertEqual(snap.current?.celsius, 9.0)
    }

    func testFallbackDisabledPropagatesError() async {
        let client = MockClient(); client.failAll = true
        do { _ = try await Fixtures.service(client, fallback: false).fetch(for: Fixtures.coordinate); XCTFail("expected throw") }
        catch { XCTAssertTrue(error is WeatherError) }
    }
}

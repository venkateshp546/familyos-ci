import CoreLocation
import XCTest

final class ClockTests: XCTestCase {
    // 2026-11-14 18:00 UTC: London on GMT, Guntur UTC+5:30.
    func testWinter() {
        XCTAssertEqual(CityClock.london.string(at: Fixtures.now), "6:00 PM")
        XCTAssertEqual(CityClock.guntur.string(at: Fixtures.now), "11:30 PM")
    }

    // 2026-07-01 18:00 UTC: London on BST (UTC+1), Guntur unchanged.
    func testSummerDaylightSaving() {
        let d = ISO8601.parse("2026-07-01T18:00:00Z")!
        XCTAssertEqual(CityClock.london.string(at: d), "7:00 PM")
        XCTAssertEqual(CityClock.guntur.string(at: d), "11:30 PM")
    }

    func testSecondsAndDayRollover() {
        let d = ISO8601.parse("2026-11-14T19:00:09Z")!
        XCTAssertEqual(CityClock.guntur.string(at: d, seconds: true), "12:30:09 AM")
    }
}

final class LocationTests: XCTestCase {
    func testPermissionMapping() {
        XCTAssertEqual(LocationAccess(status: .notDetermined, servicesEnabled: true), .notDetermined)
        XCTAssertEqual(LocationAccess(status: .authorizedWhenInUse, servicesEnabled: true), .authorized)
        XCTAssertEqual(LocationAccess(status: .authorizedAlways, servicesEnabled: true), .authorized)
        XCTAssertEqual(LocationAccess(status: .denied, servicesEnabled: true), .denied)
        XCTAssertEqual(LocationAccess(status: .restricted, servicesEnabled: true), .restricted)
        XCTAssertEqual(LocationAccess(status: .authorizedWhenInUse, servicesEnabled: false), .servicesDisabled)
    }

    func testFailuresRequireManualFallbackAndExplain() {
        for a in [LocationAccess.denied, .restricted, .servicesDisabled] {
            XCTAssertTrue(a.needsManualFallback)
            XCTAssertNotNil(a.message)
        }
        XCTAssertFalse(LocationAccess.authorized.needsManualFallback)
        XCTAssertFalse(LocationAccess.notDetermined.needsManualFallback)
    }

    func testResolverPrecedence() {
        let m = Coordinate(latitude: 1, longitude: 1, name: "M")
        let g = Coordinate(latitude: 2, longitude: 2, name: nil)
        let k = Coordinate(latitude: 3, longitude: 3, name: nil)
        XCTAssertEqual(LocationResolver.resolve(manual: m, gps: g, lastKnown: k), m)
        XCTAssertEqual(LocationResolver.resolve(manual: nil, gps: g, lastKnown: k), g)
        XCTAssertEqual(LocationResolver.resolve(manual: nil, gps: nil, lastKnown: k), k)
        XCTAssertEqual(LocationResolver.resolve(manual: nil, gps: nil, lastKnown: nil), .lombard)
    }
}

final class CacheTests: XCTestCase {
    private func makeCache() -> (WeatherCache, UserDefaults) {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return (WeatherCache(defaults: d), d)
    }

    private let snapshot = WeatherSnapshot(
        locationName: "LOMBARD", latitude: 41.88, longitude: -88.02, source: .noaa, stationID: "KDPA", stationName: nil,
        current: Temperature(celsius: 12.5), observedAt: Fixtures.now, high: Temperature(fahrenheit: 58), low: nil,
        fetchedAt: Fixtures.now, observationNote: nil)

    func testRoundTrip() {
        let (cache, _) = makeCache()
        XCTAssertNil(cache.load())
        cache.save(snapshot)
        XCTAssertEqual(cache.load(), snapshot)
    }

    func testCorruptDataRecoversAsNil() {
        let (cache, defaults) = makeCache()
        defaults.set(Data("not json".utf8), forKey: WeatherCache.snapshotKey)
        XCTAssertNil(cache.load())
    }

    func testLocationRoundTrip() {
        let (cache, _) = makeCache()
        cache.saveLocation(.lombard)
        XCTAssertEqual(cache.loadLocation(), .lombard)
    }

    func testRepositoryRecoversCachedWeatherOnFailure() async {
        let (cache, _) = makeCache()
        cache.save(snapshot)
        let client = MockClient(); client.failAll = true
        let repo = WeatherRepository(service: Fixtures.service(client), cache: cache)
        let outcome = await repo.refresh(for: Fixtures.coordinate)
        guard case .cached(let s, let err) = outcome else { return XCTFail("expected cached, got \(outcome)") }
        XCTAssertEqual(s, snapshot)
        XCTAssertFalse(err.isEmpty)
    }

    func testRepositoryFailsWithoutCache() async {
        let (cache, _) = makeCache()
        let client = MockClient(); client.failAll = true
        let outcome = await WeatherRepository(service: Fixtures.service(client), cache: cache).refresh(for: Fixtures.coordinate)
        guard case .failed = outcome else { return XCTFail("expected failed") }
    }

    func testRepositoryWritesThroughOnSuccess() async {
        let (cache, _) = makeCache()
        let client = Fixtures.client(observationNear: Fixtures.observation(temp: "12.5", time: "2026-11-14T17:50:00Z"))
        let outcome = await WeatherRepository(service: Fixtures.service(client), cache: cache).refresh(for: Fixtures.coordinate)
        guard case .fresh(let s) = outcome else { return XCTFail("expected fresh") }
        XCTAssertEqual(cache.load(), s)
    }
}

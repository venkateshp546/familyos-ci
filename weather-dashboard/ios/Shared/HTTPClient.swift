import Foundation

protocol HTTPClient {
    func data(from url: URL) async throws -> Data
}

struct URLSessionClient: HTTPClient {
    var session: URLSession = .shared

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("WeatherDashboard/1.0 (iOS personal app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw http.statusCode == 404 ? WeatherError.unsupportedLocation : WeatherError.network("HTTP \(http.statusCode)")
            }
            return data
        } catch let e as WeatherError {
            throw e
        } catch {
            throw WeatherError.network(error.localizedDescription)
        }
    }
}

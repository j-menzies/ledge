import Foundation
import os.log

/// Client for the Open-Meteo weather API (free, no key required).
///
/// Fetches current conditions and daily forecasts using latitude/longitude.
/// See: https://open-meteo.com/en/docs
class OpenMeteoClient {

    private let logger = Logger(subsystem: "com.ledge.app", category: "OpenMeteoClient")

    struct WeatherData {
        var temperature: Double = 0
        var apparentTemperature: Double = 0
        var weatherCode: Int = 0
        var windSpeed: Double = 0
        var humidity: Int = 0
        var isDay: Bool = true
        var dailyForecast: [DailyForecast] = []
    }

    struct DailyForecast: Identifiable {
        let id = UUID()
        let date: Date
        let weatherCode: Int
        let tempMax: Double
        let tempMin: Double
    }

    /// Fetch weather for the given coordinates.
    func fetchWeather(latitude: Double, longitude: Double, temperatureUnit: String = "celsius") async -> WeatherData? {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min&temperature_unit=\(temperatureUnit)&timezone=auto&forecast_days=7"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let current = json?["current"] as? [String: Any] else { return nil }

            var weather = WeatherData(
                temperature: current["temperature_2m"] as? Double ?? 0,
                apparentTemperature: current["apparent_temperature"] as? Double ?? 0,
                weatherCode: current["weather_code"] as? Int ?? 0,
                windSpeed: current["wind_speed_10m"] as? Double ?? 0,
                humidity: current["relative_humidity_2m"] as? Int ?? 0,
                isDay: (current["is_day"] as? Int ?? 1) == 1
            )

            // Parse daily forecast
            if let daily = json?["daily"] as? [String: Any],
               let dates = daily["time"] as? [String],
               let codes = daily["weather_code"] as? [Int],
               let maxTemps = daily["temperature_2m_max"] as? [Double],
               let minTemps = daily["temperature_2m_min"] as? [Double] {

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"

                weather.dailyForecast = zip(dates, zip(codes, zip(maxTemps, minTemps)))
                    .compactMap { dateStr, rest in
                        guard let date = dateFormatter.date(from: dateStr) else { return nil }
                        return DailyForecast(
                            date: date,
                            weatherCode: rest.0,
                            tempMax: rest.1.0,
                            tempMin: rest.1.1
                        )
                    }
            }

            return weather
        } catch {
            logger.error("Failed to fetch weather: \(error.localizedDescription)")
            return nil
        }
    }

    /// Map WMO weather code to SF Symbol name.
    static func sfSymbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.min.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57: return "cloud.sleet.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75: return "cloud.snow.fill"
        case 77: return "cloud.hail.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    /// Map WMO weather code to human-readable description.
    static func description(for code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snowfall"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }
}

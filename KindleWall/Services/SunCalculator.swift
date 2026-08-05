import Foundation
import OSLog

// MARK: - Protocol

/// Computes the wall-clock times a dynamic wallpaper's frames are anchored to.
protocol SunCalculatorProtocol {
    /// The six phase times for the given day at the given location.
    /// - Parameters:
    ///   - date: Any instant on the day of interest.
    ///   - coordinate: Observer position; nil falls back to fixed clock times.
    /// - Returns: Six phases in chronological order.
    func phases(for date: Date, at coordinate: GeoCoordinate?) -> [SolarPhaseTime]
}

/// A point on the globe, in degrees.
struct GeoCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Implementation

/// Sunrise/sunset via the NOAA solar position algorithm, with no dependencies and no
/// Location Services prompt.
///
/// The location comes from the system time zone: macOS ships `/usr/share/zoneinfo/zone.tab`,
/// which lists a representative coordinate for all ~420 IANA zones. That is far coarser than
/// GPS and far more than accurate enough — being a hundred kilometres off moves sunrise by a
/// few minutes, which nobody can see in a wallpaper's colour temperature.
final class SunCalculator: SunCalculatorProtocol {

    private let logger = Logger(subsystem: Constants.App.bundleIdentifier, category: "solar")

    /// Clock times used when no coordinate is available. Deliberately plain: a wrong-looking
    /// sunset beats a wallpaper that fails to generate.
    private static let fallbackHours: [SolarPhase: Double] = [
        .dawn: 5.5, .sunrise: 6.5, .noon: 12.0, .afternoon: 16.0, .sunset: 19.0, .night: 21.5
    ]

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func phases(for date: Date, at coordinate: GeoCoordinate?) -> [SolarPhaseTime] {
        guard let coordinate,
              let sunrise = solarEvent(.sunrise, date: date, at: coordinate),
              let sunset = solarEvent(.sunset, date: date, at: coordinate),
              sunset > sunrise else {
            // No coordinate, or a polar day/night where the sun never crosses the horizon.
            return fallbackPhases(for: date)
        }

        let dayLength = sunset.timeIntervalSince(sunrise)
        let solarNoon = sunrise.addingTimeInterval(dayLength / 2)

        // Dawn and night are placed a fixed hour outside the sun's arc rather than computed
        // from civil twilight: twilight length varies wildly with latitude and the extra
        // precision would not change the colours by anything visible.
        let times: [SolarPhase: Date] = [
            .dawn:      sunrise.addingTimeInterval(-3600),
            .sunrise:   sunrise,
            .noon:      solarNoon,
            .afternoon: solarNoon.addingTimeInterval(dayLength / 4),
            .sunset:    sunset,
            .night:     sunset.addingTimeInterval(3600)
        ]

        return SolarPhase.allCases
            .compactMap { phase in times[phase].map { SolarPhaseTime(phase: phase, date: $0) } }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Fallback

    private func fallbackPhases(for date: Date) -> [SolarPhaseTime] {
        let startOfDay = calendar.startOfDay(for: date)
        return SolarPhase.allCases.map { phase in
            let hours = Self.fallbackHours[phase] ?? 12
            return SolarPhaseTime(phase: phase, date: startOfDay.addingTimeInterval(hours * 3600))
        }
    }

    // MARK: - NOAA solar position

    private enum Event {
        case sunrise, sunset

        /// Hour-angle sign: the sun reaches the same altitude twice a day, once either side
        /// of solar noon.
        var sign: Double { self == .sunrise ? -1 : 1 }
    }

    /// NOAA sunrise/sunset equations, working in Julian days.
    private func solarEvent(_ event: Event, date: Date, at coordinate: GeoCoordinate) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        // Julian day number for the local day, referenced to 2000-01-01 12:00 UTC.
        let julianDay = startOfDay.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let n = (julianDay - 2_451_545.0 + 0.0008).rounded()

        let meanSolarNoon = n - coordinate.longitude / 360
        let meanAnomaly = (357.5291 + 0.985_600_28 * meanSolarNoon)
            .truncatingRemainder(dividingBy: 360)
        let m = meanAnomaly.degreesToRadians

        let center = 1.9148 * sin(m) + 0.0200 * sin(2 * m) + 0.0003 * sin(3 * m)
        let eclipticLongitude = (meanAnomaly + center + 180 + 102.9372)
            .truncatingRemainder(dividingBy: 360)
        let lambda = eclipticLongitude.degreesToRadians

        let solarTransit = 2_451_545.0 + meanSolarNoon
            + 0.0053 * sin(m) - 0.0069 * sin(2 * lambda)

        // Declination of the sun; 23.44° is Earth's axial tilt.
        let sinDeclination = sin(lambda) * sin(23.44.degreesToRadians)
        let declination = asin(sinDeclination)

        // -0.833° accounts for atmospheric refraction plus the sun's apparent radius.
        let latitude = coordinate.latitude.degreesToRadians
        let cosHourAngle = (sin((-0.833).degreesToRadians) - sin(latitude) * sinDeclination)
            / (cos(latitude) * cos(declination))

        // |cos| > 1 means the sun never reaches that altitude: polar day or polar night.
        guard cosHourAngle >= -1, cosHourAngle <= 1 else {
            logger.info("Kutup gün/gecesi: enlem \(coordinate.latitude) için güneş ufku geçmiyor")
            return nil
        }

        let hourAngle = acos(cosHourAngle).radiansToDegrees
        let eventJulian = solarTransit + event.sign * hourAngle / 360

        return Date(timeIntervalSince1970: (eventJulian - 2_440_587.5) * 86_400)
    }
}

// MARK: - Time-zone derived location

extension GeoCoordinate {
    /// Reads the representative coordinate for `timeZone` out of the system tz database.
    ///
    /// `zone.tab` lines look like: `TR\t+4101+02858\tEurope/Istanbul`, where the coordinate is
    /// ISO 6709 (`±DDMM±DDDMM`, sometimes with seconds).
    /// - Returns: The coordinate, or nil if the file is missing or the zone is unlisted.
    static func fromSystemTimeZone(
        _ timeZone: TimeZone = .current,
        zoneTabPath: String = "/usr/share/zoneinfo/zone.tab"
    ) -> GeoCoordinate? {
        guard let contents = try? String(contentsOfFile: zoneTabPath, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, fields[2] == timeZone.identifier else { continue }
            return parseISO6709(String(fields[1]))
        }
        return nil
    }

    /// Parses `±DDMM±DDDMM` or `±DDMMSS±DDDMMSS`.
    static func parseISO6709(_ value: String) -> GeoCoordinate? {
        // Split at the longitude's sign, which is the second + or - in the string.
        guard let splitIndex = value.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else {
            return nil
        }
        let latPart = String(value[value.startIndex..<splitIndex])
        let lonPart = String(value[splitIndex...])

        guard let latitude = degrees(from: latPart, degreeDigits: 2),
              let longitude = degrees(from: lonPart, degreeDigits: 3) else { return nil }
        return GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func degrees(from field: String, degreeDigits: Int) -> Double? {
        guard let sign = field.first, sign == "+" || sign == "-" else { return nil }
        let digits = Array(field.dropFirst())
        guard digits.count >= degreeDigits + 2, digits.allSatisfy(\.isNumber) else { return nil }

        func number(_ range: Range<Int>) -> Double {
            Double(String(digits[range])) ?? 0
        }

        let deg = number(0..<degreeDigits)
        let minutes = number(degreeDigits..<(degreeDigits + 2))
        let seconds = digits.count >= degreeDigits + 4
            ? number((degreeDigits + 2)..<(degreeDigits + 4))
            : 0

        let magnitude = deg + minutes / 60 + seconds / 3600
        return sign == "-" ? -magnitude : magnitude
    }
}

// MARK: - Angle helpers

private extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}

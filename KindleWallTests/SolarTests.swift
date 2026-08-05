import XCTest
@testable import KindleWall

/// The solar layer is pure computation with no UI, so it can be pinned precisely.
final class SolarTests: XCTestCase {

    private let istanbul = GeoCoordinate(latitude: 41.01, longitude: 28.98)
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func hour(of date: Date) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return Double(comps.hour!) + Double(comps.minute!) / 60
    }

    private func phase(_ phases: [SolarPhaseTime], _ want: SolarPhase) -> SolarPhaseTime {
        phases.first { $0.phase == want }!
    }

    // MARK: - Sunrise / sunset

    private func dayLengthHours(_ phases: [SolarPhaseTime]) -> Double {
        phase(phases, .sunset).date.timeIntervalSince(phase(phases, .sunrise).date) / 3600
    }

    /// Day length depends only on latitude and declination, so it can be derived from first
    /// principles and checked exactly — unlike clock times, which also fold in longitude and
    /// whatever offset the country's politicians chose. At 41.01°N with δ = −23.44°, the
    /// hour angle works out to 69.2°, giving 2 × 69.2 / 15 = 9.22 h.
    func test_winterSolsticeDayLength() {
        let phases = SunCalculator(calendar: calendar).phases(for: date(2026, 12, 21), at: istanbul)
        XCTAssertEqual(dayLengthHours(phases), 9.22, accuracy: 0.1)
    }

    /// Same latitude with δ = +23.44° gives an hour angle of 113.4° → 15.13 h.
    func test_summerSolsticeDayLength() {
        let phases = SunCalculator(calendar: calendar).phases(for: date(2026, 6, 21), at: istanbul)
        XCTAssertEqual(dayLengthHours(phases), 15.13, accuracy: 0.1)
    }

    /// Guards against a calculator that returns fixed times: the two solstices must be far apart.
    func test_dayLengthIsSeasonal() {
        let sut = SunCalculator(calendar: calendar)
        let winter = dayLengthHours(sut.phases(for: date(2026, 12, 21), at: istanbul))
        let summer = dayLengthHours(sut.phases(for: date(2026, 6, 21), at: istanbul))

        XCTAssertGreaterThan(summer - winter, 5.5, "yaz ve kış gün uzunluğu farkı en az 5.5 saat olmalı")
    }

    /// The equator's day is ~12 h year round; a latitude sign error would break this.
    func test_equatorDayLengthIsAboutTwelveHoursInBothSolstices() {
        let quito = GeoCoordinate(latitude: -0.18, longitude: -78.47)
        let sut = SunCalculator(calendar: calendar)

        XCTAssertEqual(dayLengthHours(sut.phases(for: date(2026, 12, 21), at: quito)), 12.1, accuracy: 0.2)
        XCTAssertEqual(dayLengthHours(sut.phases(for: date(2026, 6, 21), at: quito)), 12.1, accuracy: 0.2)
    }

    /// Southern hemisphere seasons are inverted: December is the long day, not the short one.
    func test_southernHemisphereSeasonsAreInverted() {
        let sydney = GeoCoordinate(latitude: -33.87, longitude: 151.21)
        let sut = SunCalculator(calendar: calendar)

        let december = dayLengthHours(sut.phases(for: date(2026, 12, 21), at: sydney))
        let june = dayLengthHours(sut.phases(for: date(2026, 6, 21), at: sydney))

        XCTAssertGreaterThan(december, june,
                             "güney yarımkürede aralık günü haziran gününden uzun olmalı")
    }

    func test_phasesAreChronologicalAndComplete() {
        let phases = SunCalculator(calendar: calendar).phases(for: date(2026, 8, 5), at: istanbul)

        XCTAssertEqual(phases.count, SolarPhase.allCases.count)
        XCTAssertEqual(Set(phases.map(\.phase)), Set(SolarPhase.allCases))
        XCTAssertEqual(phases.map(\.date), phases.map(\.date).sorted())
    }

    /// Above the Arctic Circle in midsummer the sun never sets; the calculator must fall back
    /// rather than return nonsense or crash.
    func test_polarDay_fallsBackToFixedHours() {
        let longyearbyen = GeoCoordinate(latitude: 78.22, longitude: 15.63)
        let phases = SunCalculator(calendar: calendar).phases(for: date(2026, 6, 21), at: longyearbyen)

        XCTAssertEqual(phases.count, SolarPhase.allCases.count)
        XCTAssertEqual(hour(of: phase(phases, .noon).date), 12.0, accuracy: 0.01)
    }

    func test_noCoordinate_fallsBackToFixedHours() {
        let phases = SunCalculator(calendar: calendar).phases(for: date(2026, 8, 5), at: nil)

        XCTAssertEqual(hour(of: phase(phases, .noon).date), 12.0, accuracy: 0.01)
        XCTAssertEqual(hour(of: phase(phases, .night).date), 21.5, accuracy: 0.01)
    }

    // MARK: - Day fraction

    func test_dayFractionMapsMidnightToZeroAndNoonToHalf() {
        let midnight = calendar.startOfDay(for: date(2026, 8, 5))
        let noon = midnight.addingTimeInterval(12 * 3600)

        XCTAssertEqual(SolarPhaseTime(phase: .dawn, date: midnight).dayFraction(calendar: calendar),
                       0.0, accuracy: 0.001)
        XCTAssertEqual(SolarPhaseTime(phase: .noon, date: noon).dayFraction(calendar: calendar),
                       0.5, accuracy: 0.001)
    }

    // MARK: - Coordinates from the tz database

    func test_iso6709ParsesDegreesAndMinutes() {
        // Europe/Istanbul's entry in zone.tab.
        let coordinate = GeoCoordinate.parseISO6709("+4101+02858")
        XCTAssertEqual(coordinate?.latitude ?? 0, 41.017, accuracy: 0.01)
        XCTAssertEqual(coordinate?.longitude ?? 0, 28.967, accuracy: 0.01)
    }

    func test_iso6709HandlesSouthernAndWesternHemispheres() {
        let coordinate = GeoCoordinate.parseISO6709("-3352-05836")   // America/Argentina/Buenos_Aires
        XCTAssertEqual(coordinate?.latitude ?? 0, -33.867, accuracy: 0.01)
        XCTAssertEqual(coordinate?.longitude ?? 0, -58.6, accuracy: 0.01)
    }

    func test_iso6709HandlesSeconds() {
        let coordinate = GeoCoordinate.parseISO6709("+404251+0740023")   // America/New_York
        XCTAssertEqual(coordinate?.latitude ?? 0, 40.714, accuracy: 0.01)
        XCTAssertEqual(coordinate?.longitude ?? 0, 74.006, accuracy: 0.01)
    }

    func test_systemZoneTabResolvesAKnownZone() throws {
        let coordinate = GeoCoordinate.fromSystemTimeZone(TimeZone(identifier: "Europe/Istanbul")!)
        let resolved = try XCTUnwrap(coordinate, "zone.tab okunamadı — sistem dosyası eksik olabilir")
        XCTAssertEqual(resolved.latitude, 41.017, accuracy: 0.05)
    }

    func test_missingZoneTabReturnsNilRatherThanCrashing() {
        XCTAssertNil(GeoCoordinate.fromSystemTimeZone(.current, zoneTabPath: "/nonexistent/zone.tab"))
    }

    // MARK: - Palette

    /// The guarantee that makes the whole feature safe: no style, at any hour, produces a
    /// frame whose text washes into its background.
    func test_everyStyleAndPhaseKeepsTextLegible() {
        for style in WallpaperStyle.allCases {
            for phase in SolarPhase.allCases {
                let transforms = SolarPalette.transforms(for: phase, style: style)
                let background = SolarPalette.representativeBackground(for: style)
                let text = SolarPalette.representativeText(for: style)

                let bgLuminance = luminance(background, exposure: transforms.background.exposure)
                let textLuminance = luminance(text, exposure: transforms.text.exposure)

                XCTAssertGreaterThanOrEqual(
                    abs(textLuminance - bgLuminance), 0.34,
                    "\(style.rawValue) / \(phase.rawValue) okunaksız"
                )
            }
        }
    }

    /// Paper is the light style, and the agreed behaviour is a full night flip: its background
    /// must genuinely darken after dark rather than stay a glowing rectangle.
    func test_lightStyleDarkensAtNight() {
        let noon = SolarPalette.transforms(for: .noon, style: .paper)
        let night = SolarPalette.transforms(for: .night, style: .paper)

        XCTAssertLessThan(night.background.exposure, noon.background.exposure - 0.8,
                          "Kağıt gece belirgin şekilde koyulaşmalı")
        XCTAssertGreaterThan(night.text.exposure, noon.text.exposure,
                             "Kağıt gece metnini açmalı (kontrast koruması)")
    }

    /// Night's whole identity is staying dark; the floor must stop it drifting light.
    func test_darkStyleNeverBrightensPastItsFloor() {
        for phase in SolarPhase.allCases {
            let transforms = SolarPalette.transforms(for: phase, style: .night)
            XCTAssertLessThanOrEqual(transforms.background.exposure, 0.01,
                                     "Gece \(phase.rawValue) fazında açılmamalı")
        }
    }

    func test_goldenHoursAreWarmerThanNoon() {
        let noon = SolarPalette.transforms(for: .noon, style: .forestLight)
        let sunset = SolarPalette.transforms(for: .sunset, style: .forestLight)

        XCTAssertLessThan(sunset.background.kelvin, noon.background.kelvin,
                          "günbatımı öğlenden daha sıcak olmalı")
    }

    private func luminance(_ color: NSColor, exposure: Double) -> Double {
        let rgb = color.usingColorSpace(.deviceRGB)!
        let base = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return min(max(Double(base) * pow(2, exposure), 0), 1)
    }
}

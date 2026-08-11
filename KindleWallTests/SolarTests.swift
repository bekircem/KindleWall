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

    /// Every phase must land on the day that was asked for. Anchoring the Julian day number on
    /// local midnight used to put them a day early in positive UTC offsets — the clock times
    /// looked right, so only the dates gave it away.
    func test_phasesFallOnTheRequestedCalendarDay() {
        let target = date(2026, 8, 5)
        let phases = SunCalculator(calendar: calendar).phases(for: target, at: istanbul)

        let wanted = calendar.dateComponents([.year, .month, .day], from: target)
        for phaseTime in phases {
            let got = calendar.dateComponents([.year, .month, .day], from: phaseTime.date)
            XCTAssertEqual(got, wanted, "\(phaseTime.phase.rawValue) yanlış güne düştü")
        }
    }

    /// Same check in a negative UTC offset, where the error would appear in the other direction.
    func test_phasesFallOnTheRequestedDayInWesternTimeZones() {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let losAngeles = GeoCoordinate(latitude: 34.05, longitude: -118.24)

        let target = pacific.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 12))!
        let phases = SunCalculator(calendar: pacific).phases(for: target, at: losAngeles)

        let wanted = pacific.dateComponents([.year, .month, .day], from: target)
        for phaseTime in phases {
            let got = pacific.dateComponents([.year, .month, .day], from: phaseTime.date)
            XCTAssertEqual(got, wanted, "\(phaseTime.phase.rawValue) yanlış güne düştü")
        }
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

    /// Legibility guarantee: whatever ink a frame ends up with must stand clear of the
    /// background that frame actually renders.
    ///
    /// This test used to score the frame with `luminance × 2^exposure` — the same approximation
    /// the code under test used, so it was checking the model against itself and passed while
    /// Paper's evening frames were genuinely unreadable on screen. `CIExposureAdjust` works in
    /// linear light and darkens far less than that formula predicts. The surface is now pushed
    /// through the real Core Image chain and scored with a WCAG contrast ratio, which is a
    /// property of the pixels the user actually sees.
    func test_everyStyleAndPhaseKeepsTextLegible() {
        for style in WallpaperStyle.allCases {
            for phase in SolarPhase.allCases {
                let transforms = SolarPalette.transforms(for: phase, style: style)
                let surface = SolarColorTransform.resolve(
                    SolarPalette.representativeBackground(for: style),
                    through: transforms.background
                )
                let ink = SolarPalette.inkColor(for: style, inverted: transforms.usesInvertedInk)
                let ratio = SolarColorTransform.contrastRatio(ink, surface)

                XCTAssertGreaterThanOrEqual(
                    ratio, SolarPalette.minimumContrast,
                    "\(style.rawValue) / \(phase.rawValue) okunaksız — kontrast \(ratio)"
                )
            }
        }
    }

    /// A custom gradient replaces the style's surface, so the ink decision has to follow it.
    /// It did not: the palette kept asking about the style's own colour, so with a light custom
    /// gradient the frames were scored against a colour that was nowhere on screen.
    func test_customGradientDrivesTheInkDecision() {
        var typography = TypographySettings.default
        typography.backgroundStartColorHex = "F7F3E8"   // near-white surface
        typography.backgroundEndColorHex = "F0E6D2"

        for phase in SolarPhase.allCases {
            // Night is the dark style, but with a light custom gradient its frames are light,
            // so they must use dark ink.
            let transforms = SolarPalette.transforms(for: phase, style: .night, typography: typography)
            let surface = SolarColorTransform.resolve(
                WallpaperGenerator.backgroundColor(for: .night, typography: typography),
                through: transforms.background
            )
            let ink = WallpaperGenerator.inkColor(for: .night, typography: typography,
                                                  inverted: transforms.usesInvertedInk)
            XCTAssertGreaterThanOrEqual(
                SolarColorTransform.contrastRatio(ink, surface), SolarPalette.minimumContrast,
                "özel gradient / \(phase.rawValue) okunaksız"
            )
        }
    }

    /// Paper is the light style, and the agreed behaviour is a full night flip: its background
    /// must genuinely darken after dark rather than stay a glowing rectangle.
    func test_lightStyleDarkensAtNight() {
        let noon = SolarPalette.transforms(for: .noon, style: .paper)
        let night = SolarPalette.transforms(for: .night, style: .paper)

        XCTAssertLessThan(night.background.exposure, noon.background.exposure - 0.8,
                          "Kağıt gece belirgin şekilde koyulaşmalı")
        XCTAssertTrue(night.usesInvertedInk, "Kağıt gece açık mürekkebe geçmeli")
    }

    /// The reported bug: the ink drifted with the background instead of staying put, and by
    /// sunset a Paper wallpaper was brown text on brown paper. Time of day must change the
    /// background only — the ink is either the style's normal colour or, once the background
    /// has genuinely gone dark, its inverse. Never anything in between.
    func test_inkIsNeverPartiallyShifted() {
        for style in WallpaperStyle.allCases {
            let inks = SolarPhase.allCases.map {
                SolarPalette.inkColor(for: style, inverted: SolarPalette.transforms(for: $0, style: style).usesInvertedInk)
            }
            let distinct = Set(inks.map { $0.description })
            XCTAssertLessThanOrEqual(distinct.count, 2,
                                     "\(style.rawValue) gün içinde ikiden fazla mürekkep rengi kullanıyor")
        }
    }

    /// Daylight hours must keep the style's authored ink. This is what broke: at sunset the
    /// text had already started moving toward the background.
    func test_daylightPhasesKeepTheAuthoredInk() {
        for style in WallpaperStyle.allCases {
            for phase in [SolarPhase.sunrise, .noon, .afternoon, .sunset] {
                XCTAssertFalse(SolarPalette.transforms(for: phase, style: style).usesInvertedInk,
                               "\(style.rawValue) / \(phase.rawValue) gündüz mürekkebini korumalı")
            }
        }
    }

    /// Dark styles have no reason to ever swap ink — their backgrounds only get darker.
    func test_darkStylesNeverSwapInk() {
        for style in WallpaperStyle.allCases where !style.hasLightBackground {
            for phase in SolarPhase.allCases {
                XCTAssertFalse(SolarPalette.transforms(for: phase, style: style).usesInvertedInk,
                               "\(style.rawValue) mürekkebini hiç değiştirmemeli")
            }
        }
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

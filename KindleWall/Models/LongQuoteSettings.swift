import Foundation

struct LongQuoteSettings: Codable, Equatable {
    // MARK: - Skip filter
    var skipEnabled: Bool = false
    var skipThreshold: Int = 500
    var skipUnit: LengthUnit = .characters

    // MARK: - Auto-tighten
    var autoTightenEnabled: Bool = true
    var tightenThreshold: Int = 250
    var tightenUnit: LengthUnit = .characters
    var minFontPt: Double = 14.0
    var lineSpacingMultiplier: Double = 0.22

    static let `default` = LongQuoteSettings()

    // Migration-safe decoder: missing keys (older persisted JSON) fall back to defaults.
    init(
        skipEnabled: Bool = false,
        skipThreshold: Int = 500,
        skipUnit: LengthUnit = .characters,
        autoTightenEnabled: Bool = true,
        tightenThreshold: Int = 250,
        tightenUnit: LengthUnit = .characters,
        minFontPt: Double = 14.0,
        lineSpacingMultiplier: Double = 0.22
    ) {
        self.skipEnabled = skipEnabled
        self.skipThreshold = skipThreshold
        self.skipUnit = skipUnit
        self.autoTightenEnabled = autoTightenEnabled
        self.tightenThreshold = tightenThreshold
        self.tightenUnit = tightenUnit
        self.minFontPt = minFontPt
        self.lineSpacingMultiplier = lineSpacingMultiplier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LongQuoteSettings.default
        self.skipEnabled            = try c.decodeIfPresent(Bool.self,        forKey: .skipEnabled)            ?? d.skipEnabled
        self.skipThreshold          = try c.decodeIfPresent(Int.self,         forKey: .skipThreshold)          ?? d.skipThreshold
        self.skipUnit               = try c.decodeIfPresent(LengthUnit.self,  forKey: .skipUnit)               ?? d.skipUnit
        self.autoTightenEnabled     = try c.decodeIfPresent(Bool.self,        forKey: .autoTightenEnabled)     ?? d.autoTightenEnabled
        self.tightenThreshold       = try c.decodeIfPresent(Int.self,         forKey: .tightenThreshold)       ?? d.tightenThreshold
        self.tightenUnit            = try c.decodeIfPresent(LengthUnit.self,  forKey: .tightenUnit)            ?? d.tightenUnit
        self.minFontPt              = try c.decodeIfPresent(Double.self,      forKey: .minFontPt)              ?? d.minFontPt
        self.lineSpacingMultiplier  = try c.decodeIfPresent(Double.self,      forKey: .lineSpacingMultiplier)  ?? d.lineSpacingMultiplier
    }
}

enum LengthUnit: String, Codable, CaseIterable, Identifiable {
    case characters
    case words

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .characters: return "Karakter"
        case .words:      return "Kelime"
        }
    }

    func measure(_ text: String) -> Int {
        switch self {
        case .characters: return text.count
        case .words:      return text.split { $0.isWhitespace }.count
        }
    }
}

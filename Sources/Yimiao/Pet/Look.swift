import CoreGraphics
import Foundation

/// How he looks: his coat and whatever he is wearing.
struct PetLook: Equatable {
    var coat = Coat.orange
    var outfit = Outfit.none
}

/// Fur colours. The cat is drawn in code, so a coat is a palette and a few patches.
enum Coat: String, CaseIterable, Identifiable, Sendable {
    case orange, black, white, calico, tuxedo, blue

    var id: String { rawValue }

    var name: String {
        switch self {
        case .orange: "橘猫"
        case .black: "黑猫"
        case .white: "白猫"
        case .calico: "三花"
        case .tuxedo: "奶牛猫"
        case .blue: "蓝猫"
        }
    }

    var palette: CoatPalette {
        switch self {
        case .orange:
            CoatPalette(
                furTop: rgb(0xFFC56B), furBottom: rgb(0xFFA443), stripe: rgb(0xEE8526),
                belly: rgb(0xFFF4DF), tail: rgb(0xFFA443), tailTip: rgb(0xFFF4DF),
                earLeft: rgb(0xFFC56B), earRight: rgb(0xFFC56B), earInner: rgb(0xFF9FA6),
                outline: rgb(0x4B2E1E), faceLine: rgb(0x4B2E1E)
            )
        case .black:
            CoatPalette(
                furTop: rgb(0x4C4C58), furBottom: rgb(0x34343E), stripe: nil,
                belly: rgb(0x5A5A66), tail: rgb(0x34343E), tailTip: rgb(0x4C4C58),
                earLeft: rgb(0x4C4C58), earRight: rgb(0x4C4C58), earInner: rgb(0xD98C99),
                // A dark line vanishes into black fur, so the mouth and closed eyes are drawn light.
                outline: rgb(0x17171D), faceLine: rgb(0xE4E4EC)
            )
        case .white:
            CoatPalette(
                furTop: rgb(0xFFFFFF), furBottom: rgb(0xECECF2), stripe: nil,
                belly: rgb(0xFFF7EE), tail: rgb(0xECECF2), tailTip: rgb(0xD8D8E2),
                earLeft: rgb(0xFFFFFF), earRight: rgb(0xFFFFFF), earInner: rgb(0xFFADB6),
                outline: rgb(0x6B5A52), faceLine: rgb(0x6B5A52)
            )
        case .calico:
            CoatPalette(
                furTop: rgb(0xFFFDF8), furBottom: rgb(0xF2ECE3), stripe: nil,
                belly: rgb(0xFFFDF8), tail: rgb(0xF5A347), tailTip: rgb(0x3B3438),
                earLeft: rgb(0xF5A347), earRight: rgb(0x3B3438), earInner: rgb(0xFF9FA6),
                outline: rgb(0x4B2E1E), faceLine: rgb(0x4B2E1E),
                patches: [
                    CoatPalette.Patch(center: CGPoint(x: -34, y: -76), radii: CGSize(width: 30, height: 23), angle: -0.45, color: rgb(0xF5A347)),
                    CoatPalette.Patch(center: CGPoint(x: 44, y: -34), radii: CGSize(width: 24, height: 30), angle: 0.3, color: rgb(0x3B3438)),
                    CoatPalette.Patch(center: CGPoint(x: 20, y: -93), radii: CGSize(width: 15, height: 8), angle: 0.2, color: rgb(0xF5A347)),
                ]
            )
        case .tuxedo:
            CoatPalette(
                furTop: rgb(0xFFFFFF), furBottom: rgb(0xEFEFF4), stripe: nil,
                belly: rgb(0xFFFFFF), tail: rgb(0x2E2B30), tailTip: rgb(0xFFFFFF),
                earLeft: rgb(0x2E2B30), earRight: rgb(0x2E2B30), earInner: rgb(0xE59AA6),
                outline: rgb(0x2A2226), faceLine: rgb(0x2A2226),
                patches: [
                    CoatPalette.Patch(center: CGPoint(x: 28, y: -82), radii: CGSize(width: 34, height: 22), angle: 0.25, color: rgb(0x2E2B30)),
                    CoatPalette.Patch(center: CGPoint(x: -48, y: -30), radii: CGSize(width: 22, height: 27), angle: -0.2, color: rgb(0x2E2B30)),
                ]
            )
        case .blue:
            CoatPalette(
                furTop: rgb(0xA6B1C4), furBottom: rgb(0x8794AA), stripe: nil,
                belly: rgb(0xCBD3DF), tail: rgb(0x8794AA), tailTip: rgb(0xCBD3DF),
                earLeft: rgb(0xA6B1C4), earRight: rgb(0xA6B1C4), earInner: rgb(0xE8A7B1),
                outline: rgb(0x363B4A), faceLine: rgb(0x363B4A)
            )
        }
    }
}

struct CoatPalette {
    var furTop: CGColor
    var furBottom: CGColor
    /// Tabby stripes on the forehead, if he has any.
    var stripe: CGColor?
    /// Belly and paws.
    var belly: CGColor
    var tail: CGColor
    var tailTip: CGColor
    /// As the viewer sees them.
    var earLeft: CGColor
    var earRight: CGColor
    var earInner: CGColor
    var outline: CGColor
    /// Mouth, whiskers and closed eyes, which sit on the fur rather than around it.
    var faceLine: CGColor
    /// Blotches of colour on the body, clipped to its outline.
    var patches: [Patch] = []

    struct Patch {
        var center: CGPoint
        var radii: CGSize
        var angle: CGFloat
        var color: CGColor
    }
}

/// Something he wears. Hats sit on his head; the New Year outfit swaps his collar.
enum Outfit: String, CaseIterable, Sendable {
    case none, santa, witch, newYear

    var hat: Hat? {
        switch self {
        case .santa: .santa
        case .witch: .witch
        case .none, .newYear: nil
        }
    }

    /// How much taller a hat makes him, in design points.
    var extraHeight: CGFloat {
        switch self {
        case .santa: 26
        case .witch: 36
        case .none, .newYear: 0
        }
    }

    enum Hat { case santa, witch, nightcap }

    /// The outfit the calendar calls for: a witch's hat around Halloween, a Santa hat around
    /// Christmas, a red collar from 小年 to 元宵.
    static func festival(on date: Date, calendar: Calendar = .current) -> Outfit {
        let day = calendar.dateComponents([.month, .day], from: date)
        let (month, dayOfMonth) = (day.month ?? 0, day.day ?? 0)
        if (month == 10 && dayOfMonth >= 24) || (month == 11 && dayOfMonth <= 1) { return .witch }
        if month == 12, (18...26).contains(dayOfMonth) { return .santa }

        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = calendar.timeZone
        let moon = lunar.dateComponents([.month, .day, .isLeapMonth], from: date)
        if moon.isLeapMonth != true, let lunarMonth = moon.month, let lunarDay = moon.day,
           (lunarMonth == 12 && lunarDay >= 23) || (lunarMonth == 1 && lunarDay <= 15) {
            return .newYear
        }
        return .none
    }
}

/// What the user picked in settings.
enum OutfitChoice: String, CaseIterable, Identifiable, Sendable {
    case festival, none, santa, witch, newYear

    var id: String { rawValue }

    var name: String {
        switch self {
        case .festival: "按节日自动换"
        case .none: "什么都不戴"
        case .santa: "圣诞帽"
        case .witch: "巫师帽"
        case .newYear: "春节红项圈"
        }
    }

    func outfit(on date: Date, calendar: Calendar = .current) -> Outfit {
        switch self {
        case .festival: Outfit.festival(on: date, calendar: calendar)
        case .none: .none
        case .santa: .santa
        case .witch: .witch
        case .newYear: .newYear
        }
    }
}

private func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

import CoreGraphics
import Foundation

/// How he looks: what animal he is, his coat or skin, and whatever he is wearing.
struct PetLook: Equatable {
    var coat = Coat.orange
    var outfit = Outfit.none
    var species = Species.cat
    /// Only used when he is a snake; the cat's coat is kept for when he turns back.
    var skin = SnakeSkin.mint
    /// Only used when he is a dragon.
    var dragonSkin = DragonSkin.red
}

/// The animal he is drawn as. All are driven by the same brain; only the drawing differs.
enum Species: String, CaseIterable, Identifiable, Sendable {
    case cat, snake, crab, dragon

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cat: "小猫"
        case .snake: "小蛇"
        case .crab: "像素小蟹"
        case .dragon: "小龙"
        }
    }
}

/// Colours for the dragon: scales, the mane and fins, and the horns.
enum DragonSkin: String, CaseIterable, Identifiable, Sendable {
    case red, gold, azure, white, ink

    var id: String { rawValue }

    var name: String {
        switch self {
        case .red: "赤龙"
        case .gold: "金龙"
        case .azure: "青龙"
        case .white: "白龙"
        case .ink: "墨龙"
        }
    }

    var palette: DragonPalette {
        switch self {
        case .red:
            DragonPalette(top: rgb(0xF4644F), bottom: rgb(0xD93B33), belly: rgb(0xFFE39E), bellyLine: rgb(0xE9BE6A),
                          mane: rgb(0xFFC93C), horn: rgb(0xFFF1CC), outline: rgb(0x5A1712))
        case .gold:
            DragonPalette(top: rgb(0xFFD966), bottom: rgb(0xF2B23C), belly: rgb(0xFFF4D2), bellyLine: rgb(0xEBCB8A),
                          mane: rgb(0xF0603A), horn: rgb(0xFFF6E0), outline: rgb(0x5A3510))
        case .azure:
            DragonPalette(top: rgb(0x5ACDBF), bottom: rgb(0x2E9E9C), belly: rgb(0xF2F0C4), bellyLine: rgb(0xD3D094),
                          mane: rgb(0xFFCF45), horn: rgb(0xFFF3D1), outline: rgb(0x123E3F))
        case .white:
            DragonPalette(top: rgb(0xFFFFFF), bottom: rgb(0xE3EAF4), belly: rgb(0xFFF3DA), bellyLine: rgb(0xEAD3A8),
                          mane: rgb(0x7DB4FF), horn: rgb(0xFFE9B0), outline: rgb(0x34405E))
        case .ink:
            DragonPalette(top: rgb(0x4A4B58), bottom: rgb(0x2E2F39), belly: rgb(0xEACB72), bellyLine: rgb(0xC9A64C),
                          mane: rgb(0xEACB72), horn: rgb(0xF4E6BF), outline: rgb(0x121217))
        }
    }
}

struct DragonPalette {
    /// Scales, lighter on top.
    var top: CGColor
    var bottom: CGColor
    /// Belly plates and snout.
    var belly: CGColor
    var bellyLine: CGColor
    /// Mane, brows, whiskers, beard, back fins and tail tuft.
    var mane: CGColor
    var horn: CGColor
    var outline: CGColor
}

/// Scale colours for the snake.
enum SnakeSkin: String, CaseIterable, Identifiable, Sendable {
    case mint, banana, sakura, sky, corn

    var id: String { rawValue }

    var name: String {
        switch self {
        case .mint: "薄荷绿"
        case .banana: "香蕉黄"
        case .sakura: "樱花粉"
        case .sky: "晴空蓝"
        case .corn: "玉米蛇"
        }
    }

    var palette: SkinPalette {
        switch self {
        case .mint:
            SkinPalette(top: rgb(0xB4EB8E), bottom: rgb(0x7FCB66), spot: rgb(0x5DAE52),
                        belly: rgb(0xFFF4C9), bellyLine: rgb(0xE9D79A), outline: rgb(0x2F4A26))
        case .banana:
            SkinPalette(top: rgb(0xFFE78F), bottom: rgb(0xFFC954), spot: rgb(0xF39C3B),
                        belly: rgb(0xFFF8E8), bellyLine: rgb(0xF2DDB0), outline: rgb(0x5A3A1C))
        case .sakura:
            SkinPalette(top: rgb(0xFFD0DF), bottom: rgb(0xFFA8C4), spot: rgb(0xF07AA2),
                        belly: rgb(0xFFF3F6), bellyLine: rgb(0xF6CCD8), outline: rgb(0x6A2C45))
        case .sky:
            SkinPalette(top: rgb(0xAEDFFF), bottom: rgb(0x7BBFF2), spot: rgb(0x4F98DB),
                        belly: rgb(0xF0F8FF), bellyLine: rgb(0xC9E1F5), outline: rgb(0x25405E))
        case .corn:
            SkinPalette(top: rgb(0xFFBE95), bottom: rgb(0xFF9469), spot: rgb(0xDB5532),
                        belly: rgb(0xFFF2E2), bellyLine: rgb(0xF3D3B8), outline: rgb(0x5A2A1A))
        }
    }
}

struct SkinPalette {
    /// Back of the coils and top of the head, lighter on top.
    var top: CGColor
    var bottom: CGColor
    /// Round markings along the back.
    var spot: CGColor
    /// Underside and chin.
    var belly: CGColor
    /// The lines between belly scales.
    var bellyLine: CGColor
    var outline: CGColor
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

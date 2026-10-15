import Foundation

/// What he says when he speaks up. Every occasion has stock lines that work offline; with an
/// API key the model can write a fresh one from `brief`, so he does not repeat himself.
enum Lines {
    /// Who he is, for the model.
    static let persona = """
        你是「译喵」，一只住在主人 Mac 桌面上的橘猫，本职是帮主人翻译他选中的文字。现在你要主动对主人说一句话。
        只输出这一句话：简体中文，不超过 28 个字，口语、俏皮、有猫的性子，可以偶尔带一个「喵」。\
        不说教，不用书面语，不加引号、表情符号和任何解释。
        """

    /// The situation, for the model.
    static func brief(for occasion: Companion.Occasion, at date: Date, calendar: Calendar = .current) -> String {
        let scene = switch occasion {
        case .hello:
            "今天第一次见到主人，跟他打个招呼。"
        case .welcomeBack(let minutes):
            "主人离开了\(span(minutes))，刚回到电脑前，欢迎他回来。"
        case .takeBreak(let minutes):
            "主人已经连续工作\(span(minutes))没有休息，劝他起来活动一下、喝口水或者看看远处。"
        case .backFromBreak:
            "刚才你劝主人休息，他休息完回来了，给他打打气。"
        case .offWork:
            "到了主人给自己定的下班时间，他还在电脑前，劝他收工。"
        case .bedtime:
            "已经过了主人给自己定的睡觉时间，他还在用电脑，催他去睡。"
        case .busyDay(let count):
            "今天主人已经让你翻译了 \(count) 段文字，夸夸他，或者小小地邀个功。"
        case .quiz:
            "你想考考主人之前查过的生词。"
        }
        let weekday = ["日", "一", "二", "三", "四", "五", "六"][(calendar.component(.weekday, from: date) + 6) % 7]
        let minute = Companion.minuteOfDay(date, calendar)
        return "场合：\(scene)\n现在是周\(weekday) \(String(format: "%02d:%02d", minute / 60, minute % 60))。"
    }

    static func stock(for occasion: Companion.Occasion, at date: Date, calendar: Calendar = .current) -> String {
        let pool: [String]
        switch occasion {
        case .hello:
            switch Companion.minuteOfDay(date, calendar) / 60 {
            case 5..<11:
                pool = ["早呀，今天也一起加油喵", "早上好。我已经伸过懒腰了，你呢", "新的一天，先喝口水再开工吧", "早。今天想翻点什么，随时叫我"]
            case 11..<13:
                pool = ["中午好，饭点可别错过了", "来啦？先吃饭，再干活", "中午好喵，吃了吗"]
            case 13..<18:
                pool = ["下午好，我刚睡醒，正好陪你", "下午好喵，今天也拜托多选点字给我", "来啦，下午的活儿我陪你干"]
            case 18..<23:
                pool = ["晚上好，今天过得怎么样", "晚上还要忙呀，那我陪你", "晚上好喵，慢慢来不着急"]
            default:
                pool = ["这么晚才来找我，那就速战速决", "夜猫子模式启动？我本来就是猫", "大半夜的，忙完早点睡喵"]
            }
        case .welcomeBack(let minutes):
            pool = ["回来啦，我刚打了个盹", "你走了\(span(minutes))，我数着呢", "欢迎回来，位置我帮你看着呢", "回来得正好，我刚睡醒"]
        case .takeBreak(let minutes):
            pool = [
                "已经连续忙了\(span(minutes))，起来走两步吧",
                "\(span(minutes))没挪窝了，学我伸个懒腰",
                "眼睛该歇歇了，看看窗外喵",
                "你已经坐了\(span(minutes))，去喝口水吧",
                "再不动一动，尾巴都要坐麻了",
            ]
        case .backFromBreak:
            pool = ["歇好了？那就接着来", "回来啦，气色不错嘛", "休息过的脑袋最好用，开工喵"]
        case .offWork:
            pool = ["到点啦，今天就到这儿吧", "下班时间到，剩下的明天再说", "该收工了喵，今天辛苦了", "到点了，存个盘，回家"]
        case .bedtime:
            pool = ["很晚了，再不睡明天要变熊猫了", "我都困了，你还不睡吗", "夜深了，剩下的交给明天吧", "该睡觉了喵，屏幕又不会跑"]
        case .busyDay(let count):
            pool = ["今天已经帮你翻了 \(count) 段，辛苦啦", "第 \(count) 段了，今天你很用功嘛", "翻了 \(count) 段，我也算加班了喵"]
        case .quiz:
            pool = ["考考你"]
        }
        return (pool.randomElement() ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// Cleans up a line from the model, or returns nil if it is not usable as one.
    static func tidy(_ reply: String) -> String? {
        let quotes = CharacterSet(charactersIn: "\"'“”‘’「」『』")
        let line = reply
            .split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: CharacterSet.whitespaces.union(quotes)) ?? ""
        // Much longer than asked for means he started explaining himself.
        return line.isEmpty || line.count > 45 ? nil : line
    }

    /// "40 分钟", "1 个半小时", "2 小时".
    static func span(_ minutes: Int) -> String {
        guard minutes >= 60 else { return " \(max(minutes, 1)) 分钟" }
        let hours = minutes / 60
        switch minutes % 60 {
        case ..<15: return " \(hours) 小时"
        case ..<45: return " \(hours) 个半小时"
        default: return " \(hours + 1) 小时"
        }
    }
}

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Offscreen renders: contact sheets for eyeballing the artwork and the bubble, and the app icon.
enum Snapshot {
    /// Real bubble/pet rendering against selected-text fixtures: top, bottom, tall and wide.
    @MainActor
    static func writeSelectionLayouts(to path: String) {
        _ = NSApplication.shared
        let screen = CGRect(x: 0, y: 0, width: 960, height: 720)
        let selections = [
            CGRect(x: 320, y: 600, width: 300, height: 75),
            CGRect(x: 320, y: 40, width: 300, height: 75),
            CGRect(x: 350, y: 30, width: 230, height: 660),
            CGRect(x: 0, y: 330, width: 960, height: 60),
        ]
        let ctx = makeContext(width: screen.width * 2, height: screen.height * 2, density: 1)
        for (index, selection) in selections.enumerated() {
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(index % 2) * screen.width, y: CGFloat(1 - index / 2) * screen.height)
            ctx.setFillColor(CGColor(gray: index == 2 ? 0.16 : 0.95, alpha: 1))
            ctx.fill(screen)
            ctx.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
            ctx.stroke(screen.insetBy(dx: 1, dy: 1))
            ctx.setFillColor(CGColor(srgbRed: 0.3, green: 0.6, blue: 0.95, alpha: 0.35))
            ctx.fill(selection)
            // Lines represent the protected source text, without depending on any user's content.
            ctx.setStrokeColor(CGColor(gray: 0.35, alpha: 1))
            for y in stride(from: selection.minY + 12, to: selection.maxY - 4, by: 16) {
                ctx.move(to: CGPoint(x: selection.minX + 10, y: y))
                ctx.addLine(to: CGPoint(x: selection.maxX - 10, y: y))
            }
            ctx.strokePath()
            if let placement = SelectionPlacement.place(avoiding: selection,
                near: CGPoint(x: selection.midX, y: selection.midY), screens: [screen],
                preferredSize: BubbleLayout.windowSize, petHead: PetRenderer.headTop, petHalfWidth: 64) {
                let model = BubbleModel()
                model.windowSize = placement.bubbleFrame.size
                model.isBelow = placement.isBelow
                model.tailX = placement.feet.x - placement.bubbleFrame.minX
                model.begin(caption: "英语 → 简体中文")
                model.append(String(repeating: "这是一段用于验证气泡避让的长译文。原文选区应始终完整可见，空间不足时可滚动阅读译文。", count: index == 3 ? 6 : 2))
                model.finish()
                // ImageRenderer omits native scroll views. Render an offscreen hosting view
                // so the compact long-text fixture verifies the actual scrolling content too.
                let host = NSHostingView(rootView: BubbleView(model: model).environment(\.colorScheme, index == 2 ? .dark : .light))
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: model.windowSize),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = host
                host.frame = CGRect(origin: .zero, size: model.windowSize)
                host.layoutSubtreeIfNeeded()
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let image = bitmap.cgImage { ctx.draw(image, in: placement.bubbleFrame) }
                }
                let origin = CGPoint(x: placement.feet.x - PetRenderer.feet.x,
                                     y: placement.feet.y + PetRenderer.feet.y - PetRenderer.canvas.height)
                draw(run(PetBrain(), 0.5), in: ctx, at: origin, scale: 1, density: 1)
            }
            ctx.restoreGState()
        }
        write(ctx, to: path)
    }

    /// The speech bubble in each of its states, light and dark.
    @MainActor
    static func writeBubbles(to path: String) {
        let paragraph = "敏捷的棕色狐狸跳过了那只懒狗。这句话包含了英文字母表中的每一个字母，所以常被用来测试字体和键盘。"
        let states: [(BubbleModel) -> Void] = [
            { $0.begin(caption: "英语 → 简体中文") },
            { $0.begin(caption: "英语 → 简体中文"); $0.append("你好，世界"); $0.finish() },
            { $0.begin(caption: "英语 → 简体中文"); $0.append(paragraph); $0.finish(); $0.hovered = .card },
            { $0.begin(caption: "中文 → English"); $0.append("apple\nn. 苹果；苹果树\nn. 苹果公司"); $0.finish(); $0.click() },
            { $0.fail("API Key 无效，去设置里检查一下") },
            { $0.say("喵～我是翻译官译喵！\n点这里打开设置，选择 AI 服务并填上 API Key 我就能开工啦") },
            { $0.isBelow = true; $0.tailX = 340; $0.begin(caption: "中文 → English"); $0.append("The weather is lovely today."); $0.finish() },
            { $0.ask("考考你：还记得「ephemeral」怎么翻吗？", seconds: 25, choices: [.init(title: "看答案") {}]) },
            { $0.ask("ephemeral\nadj. 短暂的；瞬息的", seconds: 30, choices: [.init(title: "记得 ✓") {}, .init(title: "忘了") {}]) },
            { $0.say("已经连续忙了 50 分钟，起来走两步吧") },
            { $0.fail("等了 20 秒，DeepSeek 一直没回话，可能是服务器太忙或出故障了", caption: "DeepSeek 服务异常", choices: [.init(title: "重试") {}]) },
            { model in
                model.fail(
                    "DeepSeek 服务器太忙了，暂时接不了活（503）\n连续 2 次了，多半是 DeepSeek 那边出了故障，过会儿再来",
                    caption: "DeepSeek 服务异常",
                    choices: [.init(title: "重试") {}, .init(title: "看服务状态") {}]
                )
                model.hovered = .choice(model.choices[0].id)
            },
            { $0.fail("API Key 无效，去设置里检查一下", caption: "设置需要检查", choices: [.init(title: "去设置") {}]) },
            { $0.tailX = 40; $0.begin(caption: "英语 → 简体中文"); $0.append(String(repeating: paragraph, count: 9)); $0.finish() },
        ]

        let cell = BubbleLayout.windowSize
        let columns = 4
        let rows = (states.count + columns - 1) / columns
        let ctx = makeContext(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows), density: 2)
        for (index, prepare) in states.enumerated() {
            let model = BubbleModel()
            prepare(model)
            let dark = index % 2 == 1
            let renderer = ImageRenderer(
                content: BubbleView(model: model)
                    .background(dark ? Color(white: 0.13) : Color(white: 0.9))
                    .environment(\.colorScheme, dark ? .dark : .light)
            )
            renderer.scale = 2
            guard let image = renderer.cgImage else { continue }
            let origin = CGPoint(x: CGFloat(index % columns) * cell.width, y: CGFloat(rows - 1 - index / columns) * cell.height)
            ctx.draw(image, in: CGRect(origin: origin, size: cell))
        }
        write(ctx, to: path)
    }

    /// Drives a fresh brain through a few situations and lays the resulting poses out in a grid.
    static func writeSheet(to path: String) {
        let scenes: [(PetBrain) -> PetPose] = [
            { run($0, 1.0, cursor: CGPoint(x: -160, y: -220)) },
            { run($0, 1.0, cursor: CGPoint(x: 220, y: 40)) },
            { run($0, 1.0, cursor: CGPoint(x: 0, y: -50)) },
            { $0.activity = .thinking; return run($0, 1.0) },
            { $0.activity = .speaking; return run($0, 0.62) },
            { $0.notice(); return run($0, 0.25) },
            { $0.celebrate(); return run($0, 0.3) },
            { brain in
                for i in 0..<60 {
                    let x = sin(Double(i) * 0.5) * 30
                    brain.updateMouse(CGPoint(x: x, y: -70), travel: 12, dt: 1.0 / 60)
                    _ = brain.tick(dt: 1.0 / 60)
                }
                return brain.tick(dt: 1.0 / 60)
            },
            { $0.isHeld = true; $0.carrySpeed = 500; return run($0, 0.5) },
            { $0.confuse(); return run($0, 0.6) },
            { $0.fallAsleep(); return run($0, 0.6) },
            { $0.fallAsleep(); return run($0, 7.3) },
            { $0.fallAsleep(); _ = run($0, 5); $0.wakeUp(); return run($0, 1.0) },
            { $0.poke(); return run($0, 0.07) },
            { $0.leap(for: 0.4, direction: 1); return run($0, 0.2) },
            { $0.perform(.stretch); return run($0, 0.7) },
            { brain in
                var pose = run(brain, 0.5)
                pose.eyeOpen = 0
                return pose
            },
            // Crouched mid-stalk, just before the pounce.
            { brain in
                brain.mayPlay = true
                var pose = PetPose()
                var last = CGPoint(x: 140, y: -60)
                for i in 0..<240 {
                    let point = CGPoint(x: 140 + sin(Double(i) / 60 * 2 * .pi * 2.2) * 60, y: -60)
                    brain.updateMouse(point, travel: abs(point.x - last.x), dt: 1.0 / 60)
                    last = point
                    pose = brain.tick(dt: 1.0 / 60)
                    if brain.isStalking, i > 200 { break }
                }
                return pose
            },
            { $0.hearsMusic = true; return run($0, 2.75) },
            { $0.energy = .empty; return run($0, 2) },
            { $0.recharged(); return run($0, 0.3) },
            { $0.ride = 900; return run($0, 0.6) },
        ]

        let columns = 5
        let rows = (scenes.count + columns - 1) / columns
        let cell = PetRenderer.canvas
        let backdrops: [UInt32] = [0xEEF1F4, 0x5B8DB8, 0x1C1F26]
        let ctx = makeContext(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows), density: 2)

        for (index, scene) in scenes.enumerated() {
            // Bitmap contexts count rows from the bottom.
            let row = index / columns
            let origin = CGPoint(x: CGFloat(index % columns) * cell.width, y: CGFloat(rows - 1 - row) * cell.height)
            let hex = backdrops[row % backdrops.count]
            ctx.setFillColor(CGColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            ))
            ctx.fill(CGRect(origin: origin, size: cell))
            draw(scene(PetBrain()), in: ctx, at: origin, scale: 1, density: 2)
        }
        write(ctx, to: path)
    }

    /// Every coat, bare and in each outfit, plus asleep in the nightcap.
    static func writeLooks(to path: String) {
        let outfits: [Outfit] = [.none, .santa, .witch, .newYear]
        let awake = run(PetBrain(), 1.0, cursor: CGPoint(x: 60, y: -150))
        let asleep: PetPose = {
            let brain = PetBrain()
            brain.fallAsleep()
            return run(brain, 7)
        }()
        let columns = outfits.count + 1
        let rows = Coat.allCases.count
        let cell = PetRenderer.canvas
        let ctx = makeContext(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows), density: 2)
        for (row, coat) in Coat.allCases.enumerated() {
            let shade: CGFloat = row.isMultiple(of: 2) ? 0.93 : 0.36
            for column in 0..<columns {
                let origin = CGPoint(x: CGFloat(column) * cell.width, y: CGFloat(rows - 1 - row) * cell.height)
                ctx.setFillColor(CGColor(gray: shade + (column.isMultiple(of: 2) ? 0 : 0.04), alpha: 1))
                ctx.fill(CGRect(origin: origin, size: cell))
                let look = PetLook(coat: coat, outfit: column < outfits.count ? outfits[column] : .none)
                draw(column < outfits.count ? awake : asleep, in: ctx, at: origin, scale: 1, density: 2, look: look)
            }
        }
        write(ctx, to: path)
    }

    /// Renders the icon at every size `iconutil` expects.
    static func writeIconSet(to directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var pose = run(PetBrain(), 0.5, cursor: CGPoint(x: 60, y: -120))
        pose.tail = -0.1

        for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
            let pixels = points * scale
            let side = CGFloat(pixels)
            let ctx = makeContext(width: side, height: side, density: 1)

            // The usual macOS tile: a rounded square inset from the canvas.
            let tile = CGRect(x: side * 0.1, y: side * 0.1, width: side * 0.8, height: side * 0.8)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: tile, cornerWidth: side * 0.18, cornerHeight: side * 0.18, transform: nil))
            ctx.clip()
            let sky = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [CGColor(srgbRed: 0.45, green: 0.86, blue: 0.80, alpha: 1), CGColor(srgbRed: 0.16, green: 0.62, blue: 0.66, alpha: 1)] as CFArray,
                locations: [0, 1]
            )!
            ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

            // Centre the whole cat, ears to paws and whiskers to tail, inside the tile.
            let zoom = side / 232
            let top = side * 0.53 - (PetRenderer.feet.y - 56.5) * zoom
            let origin = CGPoint(x: side / 2 - (PetRenderer.feet.x + 6.5) * zoom, y: side - top - PetRenderer.canvas.height * zoom)
            draw(pose, in: ctx, at: origin, scale: zoom, density: 1)
            ctx.restoreGState()

            let suffix = scale == 2 ? "@2x" : ""
            write(ctx, to: "\(directory)/icon_\(points)x\(points)\(suffix).png")
        }
    }

    /// Composites the pet's layers into `ctx`, with the canvas's bottom-left corner at `origin`.
    private static func draw(_ pose: PetPose, in ctx: CGContext, at origin: CGPoint, scale: CGFloat, density: CGFloat, look: PetLook = PetLook()) {
        let stage = PetStage()
        stage.configure(scale: scale, density: density, look: look)
        stage.show(pose)
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        stage.layer.render(in: ctx)
        ctx.restoreGState()
    }

    private static func run(_ brain: PetBrain, _ seconds: Double, cursor: CGPoint = CGPoint(x: 40, y: -160)) -> PetPose {
        var pose = PetPose()
        for _ in 0..<Int(seconds * 60) {
            brain.updateMouse(cursor, travel: 1, dt: 1.0 / 60)
            pose = brain.tick(dt: 1.0 / 60)
        }
        return pose
    }

    /// A bitmap context `density` pixels per point, y up.
    private static func makeContext(width: CGFloat, height: CGFloat, density: CGFloat) -> CGContext {
        let ctx = CGContext(
            data: nil,
            width: Int(width * density),
            height: Int(height * density),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: density, y: density)
        return ctx
    }

    private static func write(_ ctx: CGContext, to path: String) {
        guard let image = ctx.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

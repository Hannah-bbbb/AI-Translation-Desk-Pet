import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings

    @State private var test = TestState.idle
    @State private var testTask: Task<Void, Never>?
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private enum TestState: Equatable {
        case idle
        case running(since: Date)
        case passed(String)
        case failed(String)
    }

    var body: some View {
        TabView {
            translationTab.tabItem { Label("翻译", systemImage: "character.bubble") }
            companionTab.tabItem { Label("陪伴", systemImage: "heart") }
            petTab.tabItem { Label("桌宠", systemImage: "cat") }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onChange(of: settings.translatorConfig) {
            cancelTest()
            test = .idle
        }
        .onChange(of: settings.primary) {
            // The two directions must differ.
            if settings.secondary.family == settings.primary.family {
                settings.secondary = settings.primary == .english ? .chineseSimplified : .english
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            hasAccessibility = AXIsProcessTrusted()
        }
        .onDisappear {
            settings.saveKeyNow()
            cancelTest()
        }
    }

    private var translationTab: some View {
        Form {
            Section {
                Picker("AI 服务", selection: $settings.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.name).tag(provider)
                    }
                }
                SecureField("API Key", text: $settings.apiKey, prompt: Text("sk-…"))
                TextField("Base URL", text: $settings.baseURL, prompt: Text(settings.provider.defaultBaseURL))
                HStack {
                    TextField("模型", text: $settings.model)
                    Menu("预设") {
                        ForEach(settings.provider.modelPresets, id: \.self) { preset in
                            Button(preset) { settings.model = preset }
                        }
                    }
                    .fixedSize()
                }
                if settings.translatorConfig.supportsThinkingControl {
                    Toggle(isOn: $settings.thinking) {
                        Text("深度思考")
                        Text(settings.translatorConfig.usesKimiParameters && settings.translatorConfig.normalizedModel == "kimi-k3"
                             ? "K3 始终思考；关闭时使用低推理强度，开启时使用高强度"
                             : "译文更讲究，但每次要多等几秒")
                    }
                } else {
                    Text("此模型使用服务默认的思考设置")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    switch test {
                    case .running(let since):
                        Button("取消", action: cancelTest)
                        ProgressView().controlSize(.small)
                        // Counting up, so a slow service looks slow rather than frozen.
                        TimelineView(.periodic(from: since, by: 1)) { context in
                            Text("等待 \(settings.translatorConfig.provider) 回应… \(Int(context.date.timeIntervalSince(since))) 秒")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    default:
                        Button("测试连接", action: runTest)
                    }
                    switch test {
                    case .idle, .running:
                        EmptyView()
                    case .passed(let reply):
                        Label("通了：Hello → \(reply)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed(let reason):
                        Label(reason, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("AI 服务配置")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("各服务的配置独立保存，密钥存入系统钥匙串。切换后用于后续翻译和陪伴台词。")
                    Link("没有 Key？去 \(settings.provider.name) 开放平台创建", destination: settings.provider.keyURL)
                }
                .font(.footnote)
            }

            Section("翻译") {
                Picker("外语翻译成", selection: $settings.primary) {
                    ForEach(Language.allCases) { Text($0.name).tag($0) }
                }
                Toggle("选中\(settings.primary.name)时也翻译", isOn: $settings.translatesPrimary)
                if settings.translatesPrimary {
                    Picker("\(settings.primary.name)翻译成", selection: $settings.secondary) {
                        ForEach(Language.allCases.filter { $0.family != settings.primary.family }) { Text($0.name).tag($0) }
                    }
                }
            }

            Section("取词") {
                LabeledContent("辅助功能权限") {
                    if hasAccessibility {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("去授权…", action: Permissions.requestAccessibility)
                    }
                }
                Toggle(isOn: $settings.clipboardFallback) {
                    Text("兼容模式")
                    Text("Chrome、VS Code、微信等读不到选区的 App 里，替你按一下 ⌘C 取词，随后还原剪贴板")
                }
            }
        }
    }

    private var companionTab: some View {
        Form {
            Section {
                Toggle(isOn: $settings.speaksUp) {
                    Text("主动说话")
                    Text("他睡着时、你在全屏看片或演示时不会出声")
                }
            }

            Section("什么时候开口") {
                Toggle(isOn: $settings.greets) {
                    Text("见面打招呼")
                    Text("每天第一次见面，以及你离开半小时以上回来时")
                }
                Picker("久坐提醒", selection: $settings.breakMinutes) {
                    Text("不提醒").tag(0)
                    ForEach([30, 45, 50, 60, 90], id: \.self) { Text("连续用了 \($0) 分钟").tag($0) }
                }
                LabeledContent("下班提醒") {
                    DatePicker("", selection: time($settings.offWorkMinute), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!settings.remindsOffWork)
                    Toggle("", isOn: $settings.remindsOffWork).labelsHidden().toggleStyle(.switch)
                }
                LabeledContent("睡觉提醒") {
                    DatePicker("", selection: time($settings.bedtimeMinute), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!settings.remindsBedtime)
                    Toggle("", isOn: $settings.remindsBedtime).labelsHidden().toggleStyle(.switch)
                }
                Toggle(isOn: $settings.writesOwnLines) {
                    Text("台词现编")
                    Text("每次开口让模型按当时的情况写一句，花费极小；关掉就用内置台词")
                }
            }
            .disabled(!settings.speaksUp)

            Section("生词本") {
                Toggle(isOn: $settings.keepsVocabulary) {
                    Text("记下查过的词")
                    Text("选中单词或短语翻译后自动收录，在右键菜单的「生词本」里查看")
                }
                Toggle(isOn: $settings.quizzes) {
                    Text("到期了考我")
                    Text("隔 1、3、7、16、35 天各问一次，答错重来")
                }
                .disabled(!settings.keepsVocabulary || !settings.speaksUp)
            }
        }
    }

    private var petTab: some View {
        Form {
            Section {
                LabeledContent("大小") {
                    Slider(value: $settings.petScale, in: 0.6...1.8, step: 0.1)
                        .frame(width: 200)
                }
                Toggle(isOn: $settings.visitsSelection) {
                    Text("跳到选中的文字旁边")
                    Text("用鼠标选中文字时，他蹦过去把译文递到你眼前，说完再回原位")
                }
                Toggle(isOn: $settings.hidesForVideo) {
                    Text("看视频时躲到屏幕边缘")
                    Text("有视频在播放时他只露半张脸，停播后回来；点他一下可以叫出来")
                }
                Picker("没人理他时", selection: $settings.autoSleepMinutes) {
                    Text("一直醒着").tag(0)
                    ForEach([1, 3, 5, 10, 30], id: \.self) { Text("\($0) 分钟后睡着").tag($0) }
                }
                Toggle(isOn: Binding(get: { launchesAtLogin }, set: setLaunchAtLogin)) {
                    Text("开机时启动")
                    if let loginError { Text(loginError) }
                }
            }
        }
    }

    /// Bridges a time of day stored as minutes after midnight to a date picker.
    private func time(_ minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { minute.wrappedValue = Companion.minuteOfDay($0) }
        )
    }

    /// Runs a real translation of "Hello". The translator gives up on its own if the service
    /// stays silent, so this always ends; the cancel button is for not wanting to wait.
    private func runTest() {
        settings.saveKeyNow()
        testTask?.cancel()
        test = .running(since: Date())
        let config = settings.translatorConfig
        testTask = Task {
            do {
                var reply = ""
                for try await piece in Translator.stream("Hello", to: .chineseSimplified, otherwise: .english, config: config) {
                    reply += piece
                }
                guard !Task.isCancelled else { return }
                reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                test = reply.isEmpty ? .failed(Translator.describe(TranslatorError.emptyReply, provider: config.provider)) : .passed(reply)
            } catch {
                guard !Task.isCancelled else { return }
                test = .failed(Translator.describe(error, provider: config.provider))
            }
            testTask = nil
        }
    }

    private func cancelTest() {
        testTask?.cancel()
        testTask = nil
        if case .running = test { test = .idle }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "没设置成功：\(error.localizedDescription)"
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
}

enum Permissions {
    /// Shows the system prompt and opens the Accessibility list, where the user flips the switch.
    static func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        // A grant given to an earlier build can linger in the list, switched on but no longer
        // matching this one. Clearing our own entry makes the list show the truth again.
        if let bundleID = Bundle.main.bundleIdentifier {
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", "Accessibility", bundleID]
            reset.standardOutput = FileHandle.nullDevice
            if (try? reset.run()) != nil { reset.waitUntilExit() }
        }
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        if let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(pane)
        }
    }
}

@MainActor
final class SettingsWindow {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: .shared)))
            window.title = "译喵设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // An accessory app has to step forward itself or its window opens behind everything.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

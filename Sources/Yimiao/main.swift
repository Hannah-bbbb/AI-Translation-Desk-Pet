import AppKit

let arguments = CommandLine.arguments

// Developer switches: render the artwork offscreen instead of launching the pet.
if let flag = arguments.firstIndex(of: "--selection-layouts"), arguments.count > flag + 1 {
    MainActor.assumeIsolated { Snapshot.writeSelectionLayouts(to: arguments[flag + 1]) }
    exit(0)
}
if let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 {
    Snapshot.writeSheet(to: arguments[flag + 1])
    exit(0)
}
// One-time move of preferences and API keys from an earlier bundle identifier.
if let flag = arguments.firstIndex(of: "--import-from"), arguments.count > flag + 1 {
    print(MainActor.assumeIsolated { Migration.importSettings(from: arguments[flag + 1]) })
    exit(0)
}
if let flag = arguments.firstIndex(of: "--looks"), arguments.count > flag + 1 {
    Snapshot.writeLooks(to: arguments[flag + 1])
    exit(0)
}
if let flag = arguments.firstIndex(of: "--iconset"), arguments.count > flag + 1 {
    Snapshot.writeIconSet(to: arguments[flag + 1])
    exit(0)
}
if let flag = arguments.firstIndex(of: "--bubbles"), arguments.count > flag + 1 {
    MainActor.assumeIsolated { Snapshot.writeBubbles(to: arguments[flag + 1]) }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // No Dock icon and no menu bar takeover: he lives on the desktop and in the status bar.
    app.setActivationPolicy(.accessory)
    app.run()
}

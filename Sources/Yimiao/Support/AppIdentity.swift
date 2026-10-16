import Foundation

/// The app's bundle identifier. It also names the keychain items and the log subsystem, so a
/// fork that renames the app only has to change `Resources/Info.plist` and `Scripts/build.sh`.
enum AppIdentity {
    static let defaultBundleID = "io.github.hannah-bbbb.yimiao"

    /// Read from the app bundle. `swift run` and the tests have no app bundle and use the default.
    static let bundleID: String = {
        guard Bundle.main.bundleURL.pathExtension == "app", let id = Bundle.main.bundleIdentifier else {
            return defaultBundleID
        }
        return id
    }()
}

import AppKit
import CoreAudio
import IOKit.ps

/// Whether anything is playing through the speakers or headphones right now.
///
/// Asks Core Audio whether any process is running the default output device. That is true
/// while a song plays and for a moment after it stops; some apps keep the device open while
/// silent, which is why the controller wants a few seconds of it before he starts dancing.
enum AudioActivity {
    static func isOutputRunning() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}

/// The internal battery, if this Mac has one.
enum Battery {
    struct Reading: Equatable {
        var percent: Int
        var onBattery: Bool
    }

    static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return Reading(percent: current * 100 / maximum, onBattery: onBattery)
        }
        return nil
    }
}

/// Other apps' windows, for sitting on top of one.
///
/// Window positions and owners are public without any permission; titles are not, and are
/// never needed here.
enum WindowSeat {
    /// A window, in AppKit screen coordinates.
    struct Window: Equatable {
        let id: CGWindowID
        let pid: pid_t
        let frame: CGRect
    }

    /// Ordinary windows on screen, frontmost first, excluding this app's own.
    static func onScreenWindows() -> [Window] {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let window = window(from: info, primaryTop: primaryTop), window.pid != ownPID else { return nil }
            return window
        }
    }

    /// Where one window is now, or nil once it is closed, minimised, hidden or on another Space.
    static func frame(of id: CGWindowID) -> CGRect? {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
              info[kCGWindowIsOnscreen as String] as? Bool == true
        else { return nil }
        return window(from: info, primaryTop: primaryTop)?.frame
    }

    private static func window(from info: [String: Any], primaryTop: CGFloat) -> Window? {
        guard info[kCGWindowLayer as String] as? Int == 0,
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
              let id = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              let frame = SelectionPlacement.appKitRect(rect, primaryTop: primaryTop)
        else { return nil }
        return Window(id: id, pid: pid, frame: frame)
    }

    // MARK: - Geometry

    /// Where his feet go to sit on the top edge of `window`, `fraction` of the way across.
    /// Nil when the window is too narrow, or there is no room for him above it on screen.
    /// `screens` are visible frames; `halfWidth` and `height` are his size on screen.
    static func seat(on window: CGRect, fraction: CGFloat, halfWidth: CGFloat, height: CGFloat, screens: [CGRect]) -> CGPoint? {
        guard window.width >= halfWidth * 2 + 40, window.height >= 120 else { return nil }
        let y = window.maxY - 1
        let wanted = window.minX + window.width * fraction
        for screen in screens {
            // Both the window's edge and the screen must have room for all of him, side to side.
            let low = max(window.minX + halfWidth, screen.minX + halfWidth)
            let high = min(window.maxX - halfWidth, screen.maxX - halfWidth)
            guard low <= high, y >= screen.minY, y + height <= screen.maxY else { continue }
            let x = wanted.clamped(low...high)
            guard x >= screen.minX, x <= screen.maxX else { continue }
            return CGPoint(x: x, y: y)
        }
        return nil
    }

    /// The space he takes up sitting with his feet at `feet`.
    static func body(at feet: CGPoint, halfWidth: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: feet.x - halfWidth, y: feet.y - 4, width: halfWidth * 2, height: height + 4)
    }

    /// Whether a window in front would hide him, leaving him floating over it instead of sitting.
    static func isCovered(_ body: CGRect, by windowsInFront: [CGRect]) -> Bool {
        windowsInFront.contains { $0.intersection(body).width > 8 && $0.intersection(body).height > 8 }
    }
}

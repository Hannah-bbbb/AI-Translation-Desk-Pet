import Foundation
import IOKit.pwr_mgt

/// Tells whether something on this Mac is showing video right now.
///
/// Players, browsers and video calls all ask the system to keep the display awake while a
/// video is on screen, and drop the request when it pauses or ends. Those requests are public,
/// which makes them a far better signal than guessing from window titles. Music playing in the
/// background does not make one.
enum Playback {
    private static let displayTypes: Set<String> = [
        kIOPMAssertionTypePreventUserIdleDisplaySleep,
        kIOPMAssertionTypeNoDisplaySleep,
    ]

    /// Tools whose whole job is keeping the display awake. They say nothing about video.
    private static let keepAwakeTools: Set<String> = [
        "caffeinate", "Amphetamine", "KeepingYouAwake", "Lungo", "Caffeine", "Theine", "Jiggler",
    ]

    static func isVideoPlaying() -> Bool {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return false }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return byProcess.contains { pid, assertions in
            pid.int32Value != ownPID && assertions.contains { assertion in
                guard let type = assertion[kIOPMAssertionTypeKey] as? String, displayTypes.contains(type),
                      assertion[kIOPMAssertionLevelKey] as? Int == Int(kIOPMAssertionLevelOn)
                else { return false }
                return !keepAwakeTools.contains(assertion["Process Name"] as? String ?? "")
            }
        }
    }
}

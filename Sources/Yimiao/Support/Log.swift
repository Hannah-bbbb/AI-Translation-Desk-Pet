import os

/// Diagnostics for "why didn't he translate that?". Lengths and app names only, never the text itself.
///
///     /usr/bin/log stream --predicate 'subsystem == "io.github.hannah-bbbb.yimiao"'
enum Log {
    static let selection = Logger(subsystem: AppIdentity.bundleID, category: "selection")
    static let translation = Logger(subsystem: AppIdentity.bundleID, category: "translation")
    static let companion = Logger(subsystem: AppIdentity.bundleID, category: "companion")
}

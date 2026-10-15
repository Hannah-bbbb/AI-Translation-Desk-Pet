import os

/// Diagnostics for "why didn't he translate that?". Lengths and app names only, never the text itself.
///
///     log stream --predicate 'subsystem == "io.github.hannah-bbbb.yimiao"'
enum Log {
    static let selection = Logger(subsystem: "io.github.hannah-bbbb.yimiao", category: "selection")
    static let translation = Logger(subsystem: "io.github.hannah-bbbb.yimiao", category: "translation")
    static let companion = Logger(subsystem: "io.github.hannah-bbbb.yimiao", category: "companion")
}

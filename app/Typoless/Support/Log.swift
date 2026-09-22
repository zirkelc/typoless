import OSLog

/**
 Shared loggers, one per subsystem area.

 Nothing here may ever receive the contents of a user's text field. Correction
 work logs shapes and counts (character length, number of edits, elapsed time),
 never the text itself. Opt-in diagnostic logging of real text is a settings
 feature and must go through a separate, clearly labelled path.
 */
enum Log {
    private static let subsystem = "dev.zirkelc.typoless"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
}

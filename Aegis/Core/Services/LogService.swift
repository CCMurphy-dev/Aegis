import Foundation

/// Simple logging service with file output and automatic rotation
final class LogService {
    static let shared = LogService()

    enum Level: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        var prefix: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARN"
            case .error: return "ERROR"
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private let logDirectory: URL
    private let logFile: URL
    private let maxFileSize: UInt64 = 5 * 1024 * 1024  // 5MB
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.aegis.log", qos: .utility)
    private var fileHandle: FileHandle?

    /// Minimum level to log (can be changed at runtime)
    var minimumLevel: Level = .info

    private init() {
        // Use ~/Library/Logs/Aegis/ as the standard macOS location
        let libraryLogs = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("Aegis")
        self.logDirectory = libraryLogs
        self.logFile = libraryLogs.appendingPathComponent("aegis.log")

        setupLogFile()
    }

    private func setupLogFile() {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Create directory if needed
            try? self.fileManager.createDirectory(at: self.logDirectory, withIntermediateDirectories: true)

            // Create file if needed
            if !self.fileManager.fileExists(atPath: self.logFile.path) {
                self.fileManager.createFile(atPath: self.logFile.path, contents: nil)
            }

            // Open file handle for appending
            self.fileHandle = try? FileHandle(forWritingTo: self.logFile)
            self.fileHandle?.seekToEndOfFile()

            // Log startup
            self.writeEntry(level: .info, message: "=== Aegis Log Started ===", file: #file, function: #function, line: #line)
        }
    }

    // MARK: - Public Logging Methods

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }

    // MARK: - Core Logging

    private func log(level: Level, message: String, file: String, function: String, line: Int) {
        guard level >= minimumLevel else { return }

        queue.async { [weak self] in
            self?.writeEntry(level: level, message: message, file: file, function: function, line: line)
        }

        // Also print to console in debug builds
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        print("[\(level.prefix)] \(filename):\(line) - \(message)")
        #endif
    }

    private func writeEntry(level: Level, message: String, file: String, function: String, line: Int) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = (file as NSString).lastPathComponent
        let entry = "[\(timestamp)] [\(level.prefix)] \(filename):\(line) \(message)\n"

        guard let data = entry.data(using: .utf8) else { return }

        // Check for rotation before writing
        rotateIfNeeded()

        fileHandle?.write(data)
        try? fileHandle?.synchronize()
    }

    // MARK: - Log Rotation

    private func rotateIfNeeded() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logFile.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize > maxFileSize else {
            return
        }

        // Close current handle
        try? fileHandle?.close()

        // Rename current log to .old
        let oldLog = logDirectory.appendingPathComponent("aegis.log.old")
        try? fileManager.removeItem(at: oldLog)
        try? fileManager.moveItem(at: logFile, to: oldLog)

        // Create new log file
        fileManager.createFile(atPath: logFile.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logFile)

        writeEntry(level: .info, message: "Log rotated (previous log saved as aegis.log.old)", file: #file, function: #function, line: #line)
    }

    // MARK: - Utilities

    /// Get the path to the log file (for sharing/viewing)
    var logFilePath: String {
        logFile.path
    }

    /// Get the log directory path
    var logDirectoryPath: String {
        logDirectory.path
    }

    /// Clear the current log file
    func clearLog() {
        queue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileHandle?.close()
            try? self.fileManager.removeItem(at: self.logFile)
            self.fileManager.createFile(atPath: self.logFile.path, contents: nil)
            self.fileHandle = try? FileHandle(forWritingTo: self.logFile)
            self.writeEntry(level: .info, message: "Log cleared", file: #file, function: #function, line: #line)
        }
    }

    deinit {
        try? fileHandle?.close()
    }
}

// MARK: - Convenience Global Functions

/// Log a debug message
func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    LogService.shared.debug(message, file: file, function: function, line: line)
}

/// Log an info message
func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    LogService.shared.info(message, file: file, function: function, line: line)
}

/// Log a warning message
func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    LogService.shared.warning(message, file: file, function: function, line: line)
}

/// Log an error message
func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    LogService.shared.error(message, file: file, function: function, line: line)
}

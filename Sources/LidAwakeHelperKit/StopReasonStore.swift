import Foundation
import LidAwakeShared

/// Keeps why the helper last ended a session, until the app has shown it.
public protocol StopReasonStore {
    func read() -> StopRecord?
    func write(_ record: StopRecord) throws
    func clear() throws
}

public struct FileStopReasonStore: StopReasonStore {
    private let directory: URL
    private let file: URL

    public init(directory: URL = FileOwnershipMarker.defaultDirectory) {
        self.directory = directory
        self.file = directory.appendingPathComponent("last-stop-reason")
    }

    public func read() -> StopRecord? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(StopRecord.self, from: data)
    }

    public func write(_ record: StopRecord) throws {
        try prepareSupportDirectory(directory)
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}

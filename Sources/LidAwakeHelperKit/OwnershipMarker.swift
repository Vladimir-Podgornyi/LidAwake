import Foundation

/// Records that LidAwake set SleepDisabled, so a flag set by another program is never cleared.
public protocol OwnershipMarker {
    var isSet: Bool { get }
    func set() throws
    func clear() throws
}

public struct FileOwnershipMarker: OwnershipMarker {
    public static let defaultDirectory = URL(
        fileURLWithPath: "/Library/Application Support/com.vladimirpodgornyi.LidAwake",
        isDirectory: true
    )

    private let directory: URL
    private let file: URL

    public init(directory: URL = FileOwnershipMarker.defaultDirectory) {
        self.directory = directory
        self.file = directory.appendingPathComponent("sleep-disabled-by-lidawake")
    }

    public var isSet: Bool {
        FileManager.default.fileExists(atPath: file.path)
    }

    public func set() throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        if getuid() == 0 {
            // The directory may predate the helper; only root may write to it.
            try manager.setAttributes(
                [.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o755],
                ofItemAtPath: directory.path
            )
        }
        guard manager.createFile(atPath: file.path, contents: Data(), attributes: [.posixPermissions: 0o644]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }
    }

    public func clear() throws {
        guard isSet else { return }
        try FileManager.default.removeItem(at: file)
    }
}

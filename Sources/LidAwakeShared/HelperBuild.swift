import Foundation
import MachO

/// Tells helper builds apart by the UUID the linker writes into the executable's Mach-O header.
/// The linker derives it from the linked code, so any change to the helper gives a new one;
/// signing leaves it untouched.
public enum HelperBuild {
    public static func executableURL(inBundle bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/MacOS/LidAwakeHelper")
    }

    /// Reads the header the running image was loaded from, so a file replaced on disk later does not count.
    public static func identifier(ofImage header: UnsafeRawPointer) -> String? {
        let start = UnsafeRawBufferPointer(start: header, count: MemoryLayout<mach_header_64>.size)
        guard let commandsSize = commandsSize(in: start) else { return nil }
        return identifier(in: UnsafeRawBufferPointer(start: header, count: start.count + commandsSize))
    }

    public static func identifier(ofFile url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return data.withUnsafeBytes { identifier(in: $0) }
    }

    /// A thin 64-bit Mach-O image or file; anything else has no identifier.
    static func identifier(in bytes: UnsafeRawBufferPointer) -> String? {
        guard let commandsSize = commandsSize(in: bytes) else { return nil }
        let headerSize = MemoryLayout<mach_header_64>.size
        let end = headerSize + commandsSize
        guard bytes.count >= end else { return nil }
        let count = bytes.loadUnaligned(fromByteOffset: 16, as: UInt32.self)
        var offset = headerSize
        for _ in 0..<count {
            guard offset + 8 <= end else { return nil }
            let command = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            let size = Int(bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
            guard size >= 8, offset + size <= end else { return nil }
            if command == UInt32(LC_UUID) {
                guard size >= MemoryLayout<uuid_command>.size else { return nil }
                let uuid = bytes.loadUnaligned(fromByteOffset: offset + 8, as: uuid_t.self)
                return UUID(uuid: uuid).uuidString
            }
            offset += size
        }
        return nil
    }

    private static func commandsSize(in bytes: UnsafeRawBufferPointer) -> Int? {
        guard bytes.count >= MemoryLayout<mach_header_64>.size,
              bytes.loadUnaligned(as: UInt32.self) == MH_MAGIC_64 else { return nil }
        return Int(bytes.loadUnaligned(fromByteOffset: 20, as: UInt32.self))
    }
}

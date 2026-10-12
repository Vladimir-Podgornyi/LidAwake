import MachO
import XCTest
@testable import LidAwakeShared

final class HelperBuildTests: XCTestCase {
    private let uuid = UUID(uuidString: "F4D918E0-19F0-37D9-98D2-48832296B323")!

    private func image(commands: [(UInt32, [UInt8])], magic: UInt32 = MH_MAGIC_64) -> [UInt8] {
        var body: [UInt8] = []
        for (command, payload) in commands {
            body += le(command) + le(UInt32(8 + payload.count)) + payload
        }
        let header = le(magic) + le(UInt32(0)) + le(UInt32(0)) + le(UInt32(MH_EXECUTE))
            + le(UInt32(commands.count)) + le(UInt32(body.count)) + le(UInt32(0)) + le(UInt32(0))
        return header + body
    }

    private func le(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }

    private var uuidPayload: [UInt8] {
        withUnsafeBytes(of: uuid.uuid, Array.init)
    }

    private func identifier(_ bytes: [UInt8]) -> String? {
        bytes.withUnsafeBytes { HelperBuild.identifier(in: $0) }
    }

    func testReadsTheUUIDAfterOtherCommands() {
        let bytes = image(commands: [(UInt32(LC_SYMTAB), Array(repeating: 0, count: 16)), (UInt32(LC_UUID), uuidPayload)])
        XCTAssertEqual(identifier(bytes), uuid.uuidString)
    }

    func testNoUUIDCommand() {
        XCTAssertNil(identifier(image(commands: [(UInt32(LC_SYMTAB), Array(repeating: 0, count: 16))])))
    }

    func testOnlyThin64BitImages() {
        XCTAssertNil(identifier(image(commands: [(UInt32(LC_UUID), uuidPayload)], magic: FAT_CIGAM)))
        XCTAssertNil(identifier(Array("#!/bin/sh\necho not a binary\n".utf8)))
        XCTAssertNil(identifier([]))
    }

    func testTruncatedCommands() {
        let bytes = image(commands: [(UInt32(LC_UUID), uuidPayload)])
        XCTAssertNil(identifier(Array(bytes.dropLast(4))))
    }

    func testMissingFile() {
        XCTAssertNil(HelperBuild.identifier(ofFile: URL(fileURLWithPath: "/nonexistent/LidAwakeHelper")))
    }

    func testRunningImageMatchesItsFile() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).executableURL)
        let running = HelperBuild.identifier(ofImage: #dsohandle)
        XCTAssertNotNil(running)
        XCTAssertEqual(running, HelperBuild.identifier(ofFile: file))
    }

    func testExecutableURL() {
        XCTAssertEqual(
            HelperBuild.executableURL(inBundle: URL(fileURLWithPath: "/Applications/LidAwake.app")).path,
            "/Applications/LidAwake.app/Contents/MacOS/LidAwakeHelper"
        )
    }
}

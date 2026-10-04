import XCTest
import LidAwakeShared

final class RequirementTests: XCTestCase {
    private let developerID = [
        "anchor apple generic",
        "certificate 1[field.1.2.840.113635.100.6.2.6]",
        "certificate leaf[field.1.2.840.113635.100.6.1.13]",
        "certificate leaf[subject.OU] = \"ZW984867UC\"",
    ]

    func testAppRequirement() {
        let requirement = HelperConstants.appRequirement
        XCTAssertTrue(requirement.contains("identifier \"com.vladimirpodgornyi.LidAwake\" "))
        for clause in developerID {
            XCTAssertTrue(requirement.contains(clause), clause)
        }
    }

    func testHelperRequirement() {
        let requirement = HelperConstants.helperRequirement
        XCTAssertTrue(requirement.contains("identifier \"com.vladimirpodgornyi.LidAwake.helper\" "))
        for clause in developerID {
            XCTAssertTrue(requirement.contains(clause), clause)
        }
    }

    func testRequirementsCompile() {
        for text in [HelperConstants.appRequirement, HelperConstants.helperRequirement] {
            var requirement: SecRequirement?
            XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess, text)
        }
    }

    func testIdentifiers() {
        XCTAssertEqual(HelperConstants.machServiceName, "com.vladimirpodgornyi.LidAwake.helper")
        XCTAssertEqual(HelperConstants.plistName, "com.vladimirpodgornyi.LidAwake.helper.plist")
        XCTAssertEqual(HelperConstants.protocolVersion, 6)
    }
}

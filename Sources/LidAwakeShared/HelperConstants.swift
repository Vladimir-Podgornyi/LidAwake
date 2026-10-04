public enum HelperConstants {
    public static let appBundleIdentifier = "com.vladimirpodgornyi.LidAwake"
    public static let helperIdentifier = "com.vladimirpodgornyi.LidAwake.helper"
    public static let machServiceName = helperIdentifier
    public static let plistName = "\(helperIdentifier).plist"
    public static let teamIdentifier = "ZW984867UC"
    public static let protocolVersion = 3

    // Kept as single literals so the build script can read them back from the
    // compiled binaries and check the signatures against what is enforced.
    public static let appRequirement = "anchor apple generic and identifier \"com.vladimirpodgornyi.LidAwake\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"ZW984867UC\""
    public static let helperRequirement = "anchor apple generic and identifier \"com.vladimirpodgornyi.LidAwake.helper\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"ZW984867UC\""
}

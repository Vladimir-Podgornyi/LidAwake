#!/bin/bash
set -euo pipefail

# Checks that every localizable string in Sources/ has an entry in each
# Resources/<language>.lproj/Localizable.strings, and that no entry is stale.
# The compiler lists the strings, so implicit LocalizedStringKey and
# String.LocalizationValue literals are found the same way as at run time.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

STRINGS_DIR="$(mktemp -d)"
trap 'rm -rf "$STRINGS_DIR"' EXIT

swift build --scratch-path .build/localizations --product LidAwake \
    -Xswiftc -emit-localized-strings \
    -Xswiftc -emit-localized-strings-path -Xswiftc "$STRINGS_DIR" >/dev/null

for TABLE in Resources/*.lproj/Localizable.strings; do
    plutil -lint -s "$TABLE"
done

swift - "$STRINGS_DIR" Resources/*.lproj/Localizable.strings <<'EOF'
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let stringsDir = URL(fileURLWithPath: arguments.first!)

var sourceKeys = Set<String>()
for file in try FileManager.default.contentsOfDirectory(at: stringsDir, includingPropertiesForKeys: nil)
where file.pathExtension == "stringsdata" {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    let tables = json["tables"] as? [String: [[String: Any]]] ?? [:]
    for (name, entries) in tables {
        guard name == "Localizable" else {
            print("ERROR: \(file.lastPathComponent) uses table \(name)")
            exit(1)
        }
        sourceKeys.formUnion(entries.compactMap { $0["key"] as? String })
    }
}
guard !sourceKeys.isEmpty else {
    print("ERROR: the compiler reported no localizable strings")
    exit(1)
}

var failed = false
for path in arguments.dropFirst() {
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil)
    let keys = Set((plist as! [String: String]).keys)
    for key in sourceKeys.subtracting(keys).sorted() {
        print("MISSING in \(path): \(key)")
        failed = true
    }
    for key in keys.subtracting(sourceKeys).sorted() {
        print("STALE in \(path): \(key)")
        failed = true
    }
}
if failed { exit(1) }
print("\(sourceKeys.count) localizable strings in Sources/, all present in \(arguments.count - 1) tables")
EOF

import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let languages = ["en", "de", "ru"]

    private func table(_ language: String) throws -> [String: String] {
        let url = Self.root.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String], "\(language) is not a strings table")
    }

    /// Format specifiers in order, `%%` included, so a lost percent sign counts as a mismatch.
    private func placeholders(_ text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: "%(?:\\d+\\$)?[-+ #0]*\\d*(?:\\.\\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA%]")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            String(text[Range($0.range, in: text)!])
        }
    }

    func testEnglishValuesAreTheirKeys() throws {
        for (key, value) in try table("en") {
            XCTAssertEqual(value, key)
        }
    }

    func testEveryLanguageHasTheSameKeys() throws {
        let english = Set(try table("en").keys)
        XCTAssertFalse(english.isEmpty)
        for language in Self.languages {
            XCTAssertEqual(Set(try table(language).keys), english, language)
        }
    }

    func testNoValueIsEmpty() throws {
        for language in Self.languages {
            for (key, value) in try table(language) {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language): \(key)")
            }
        }
    }

    func testTranslationsKeepThePlaceholders() throws {
        for language in Self.languages {
            for (key, value) in try table(language) {
                XCTAssertEqual(try placeholders(value), try placeholders(key), "\(language): \(key)")
            }
        }
    }

    func testFormattedValuesUseANoBreakSpaceBeforePercentAndUnits() throws {
        XCTAssertEqual(String(format: try table("en")["Battery %lld%%"]!, 82), "Battery 82%")
        XCTAssertEqual(String(format: try table("de")["Battery %lld%%"]!, 82), "Akku 82\u{00A0}%")
        XCTAssertEqual(String(format: try table("ru")["Battery %lld%%"]!, 82), "Батарея 82\u{00A0}%")
        XCTAssertEqual(String(format: try table("de")["%lld%%"]!, 20), "20\u{00A0}%")
        XCTAssertEqual(String(format: try table("ru")["%lld%%"]!, 20), "20\u{00A0}%")
        XCTAssertEqual(String(format: try table("de")["%lld h %lld min"]!, 1, 20), "1\u{00A0}Std. 20\u{00A0}Min.")
        XCTAssertEqual(String(format: try table("ru")["%lld h %lld min"]!, 1, 20), "1\u{00A0}ч 20\u{00A0}мин")
        XCTAssertEqual(String(format: try table("de")["%@ left"]!, "45\u{00A0}Min."), "noch 45\u{00A0}Min.")
        XCTAssertEqual(String(format: try table("ru")["%@ left"]!, "45\u{00A0}мин"), "осталось 45\u{00A0}мин")
    }

    func testNumbersAreNotSplitFromPercentOrUnits() throws {
        let ordinarySpace = try NSRegularExpression(
            pattern: "(%lld|\\d) (%|Min\\.|Std\\.|Stunden?|мин|ч|час|часа|часов)(?!\\p{L})"
        )
        for language in ["de", "ru"] {
            for (key, value) in try table(language) {
                let range = NSRange(value.startIndex..., in: value)
                XCTAssertNil(ordinarySpace.firstMatch(in: value, range: range), "\(language): \(key)")
            }
        }
    }

    func testGlossaryTerms() throws {
        let glossary: [(String, String, String)] = [
            ("Off", "Aus", "Выкл."),
            ("Keep Screen On", "Bildschirm anlassen", "Не гасить экран"),
            ("Run with Lid Closed", "Mit geschlossenem Deckel", "С закрытой крышкой"),
            ("Safety", "Schutz", "Защита"),
            ("Timer", "Timer", "Таймер"),
            ("Safety · lid closed only", "Schutz · nur bei geschlossenem Deckel", "Защита · только с закрытой крышкой"),
            ("Stop when the Mac gets hot", "Bei Überhitzung beenden", "Стоп при перегреве"),
            ("Ends the session under thermal pressure", "Wenn der Mac zu heiß wird", "Если Mac перегрелся"),
            ("Stop on low battery", "Bei schwachem Akku beenden", "Стоп при низком заряде"),
            ("When the charge drops below the limit", "Unter der eingestellten Grenze", "Когда заряд ниже порога"),
            ("Pauses on battery, resumes on power", "Pause im Akkubetrieb, weiter am Netzteil", "Пауза на батарее, работа от сети"),
            ("Counts from the moment you switch on", "Ab dem Einschalten", "Отсчёт с момента включения"),
            ("Only while charging", "Nur am Netzteil", "Только от зарядки"),
            ("Turn off after", "Ausschalten nach", "Выключить через"),
            ("Lock screen when the lid closes", "Beim Zuklappen sperren", "Блокировать при закрытии крышки"),
            ("Launch at login", "Bei der Anmeldung öffnen", "Запускать при входе"),
            ("Appearance", "Erscheinungsbild", "Оформление"),
            ("Glass", "Glas", "Стекло"),
            ("Solid", "Deckend", "Плотный"),
            ("Accent", "Akzent", "Акцент"),
            ("Blue", "Blau", "Синий"),
            ("Amber", "Bernstein", "Янтарный"),
            ("Quit LidAwake", "LidAwake beenden", "Завершить LidAwake"),
            ("Permission needed", "Erlaubnis erforderlich", "Нужно разрешение"),
            ("Open System Settings", "Systemeinstellungen öffnen", "Открыть «Системные настройки»"),
            ("Try Again", "Erneut versuchen", "Повторить"),
            ("LidAwake turned off", "LidAwake wurde ausgeschaltet", "LidAwake выключился"),
            ("LidAwake paused", "LidAwake pausiert", "LidAwake на паузе"),
            ("30 min", "30\u{00A0}Min.", "30\u{00A0}мин"),
            ("1 hour", "1\u{00A0}Stunde", "1\u{00A0}час"),
            ("2 hours", "2\u{00A0}Stunden", "2\u{00A0}часа"),
            ("4 hours", "4\u{00A0}Stunden", "4\u{00A0}часа"),
            ("8 hours", "8\u{00A0}Stunden", "8\u{00A0}часов"),
        ]
        let german = try table("de")
        let russian = try table("ru")
        for (key, de, ru) in glossary {
            XCTAssertEqual(german[key], de, key)
            XCTAssertEqual(russian[key], ru, key)
        }
    }

    func testSettingsPathUsesTheSystemNames() throws {
        let english = "System Settings > General > Login Items & Extensions"
        let paths = [
            "de": "Systemeinstellungen > Allgemein > Anmeldeobjekte & Erweiterungen",
            "ru": "«Системные настройки» > «Основные» > «Объекты входа и расширения»",
        ]
        for (language, path) in paths {
            for (key, value) in try table(language) where key.contains(english) {
                XCTAssertTrue(value.contains(path), "\(language): \(key)")
            }
        }
    }

    func testInfoPlistDeclaresTheLanguages() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleDevelopmentRegion"] as? String, "en")
        XCTAssertEqual(plist["CFBundleLocalizations"] as? [String], Self.languages)
    }
}

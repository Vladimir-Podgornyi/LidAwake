import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let languages = ["en", "de", "ru", "zh-Hans"]

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

    func testBatteryRefusalTakesThePercentAndTheLimit() throws {
        let key = "The battery is at %lld%%, at or below the %lld%% limit."
        XCTAssertEqual(String(format: try table("en")[key]!, 18, 30), "The battery is at 18%, at or below the 30% limit.")
        XCTAssertEqual(
            String(format: try table("de")[key]!, 18, 30),
            "Der Akkustand liegt bei 18\u{00A0}% und damit an oder unter der Grenze von 30\u{00A0}%."
        )
        XCTAssertEqual(String(format: try table("ru")[key]!, 18, 30), "Заряд 18\u{00A0}% — на пороге 30\u{00A0}% или ниже.")
        XCTAssertEqual(String(format: try table("zh-Hans")[key]!, 18, 30), "电量为 18%，已达到或低于 30% 的下限。")
    }

    func testAutoLogoutTextTakesTheDuration() throws {
        let key = "Automatic logout after %@ of inactivity is on. The mode ends when macOS logs you out."
        XCTAssertEqual(
            String(format: try table("de")[key]!, "1\u{00A0}Std."),
            "Die automatische Abmeldung nach 1\u{00A0}Std. Inaktivität ist aktiviert. Der Modus endet, sobald macOS dich abmeldet."
        )
        XCTAssertEqual(
            String(format: try table("ru")[key]!, "1\u{00A0}ч"),
            "Включён автоматический выход через 1\u{00A0}ч бездействия. Когда macOS выйдет из учётной записи, режим закончится."
        )
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
            ("System", "System", "Система"),
            ("Amber", "Bernstein", "Amber"),
            ("Settings", "Einstellungen", "Настройки"),
            ("Quit LidAwake", "LidAwake beenden", "Завершить LidAwake"),
            ("Permission needed", "Erlaubnis erforderlich", "Нужно разрешение"),
            ("Open System Settings", "Systemeinstellungen öffnen", "Открыть «Системные настройки»"),
            ("Try Again", "Erneut versuchen", "Повторить"),
            ("Dismiss", "Ausblenden", "Скрыть"),
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

    func testSleepWhenIdleStrings() throws {
        let expected: [String: [String: String]] = [
            "Sleep when idle": [
                "de": "Ruhezustand bei Leerlauf",
                "ru": "Сон после простоя",
                "zh-Hans": "空闲时睡眠",
            ],
            "After the work is done": [
                "de": "Wenn die Arbeit erledigt ist",
                "ru": "Когда работа закончена",
                "zh-Hans": "任务完成后",
            ],
            "Kept awake by %@": [
                "de": "Wach gehalten von %@",
                "ru": "Не даёт уснуть: %@",
                "zh-Hans": "%@ 正在阻止睡眠",
            ],
            "Kept awake by CPU load": [
                "de": "Wach gehalten durch CPU-Last",
                "ru": "Не даёт уснуть: нагрузка процессора",
                "zh-Hans": "CPU 负载正在阻止睡眠",
            ],
            "Kept awake by keyboard or mouse": [
                "de": "Wach gehalten durch Tastatur oder Maus",
                "ru": "Не даёт уснуть: клавиатура или мышь",
                "zh-Hans": "键盘或鼠标操作正在阻止睡眠",
            ],
            "Idle for %lld of %lld min": [
                "de": "Leerlauf: %lld von %lld\u{00A0}Min.",
                "ru": "Простой: %lld из %lld\u{00A0}мин",
                "zh-Hans": "已空闲 %lld / %lld 分钟",
            ],
        ]
        let english = try table("en")
        for (key, translations) in expected {
            XCTAssertEqual(english[key], key)
            for (language, value) in translations {
                XCTAssertEqual(try table(language)[key], value, "\(language): \(key)")
            }
        }
    }

    func testWatchedAppStrings() throws {
        let key = "Started programs are working"
        let expected = [
            "en": "Started programs are working",
            "de": "Gestartete Programme arbeiten",
            "ru": "Запущенные программы работают",
            "zh-Hans": "已启动的程序正在运行",
        ]
        for (language, value) in expected {
            XCTAssertEqual(try table(language)[key], value, language)
        }
    }

    func testActivityLogStrings() throws {
        let expected: [String: [String: String]] = [
            "Activity log": ["de": "Aktivitätsprotokoll", "ru": "Журнал событий", "zh-Hans": "活动日志"],
            "Activity Log": ["de": "Aktivitätsprotokoll", "ru": "Журнал событий", "zh-Hans": "活动日志"],
            "Today": ["de": "Heute", "ru": "Сегодня", "zh-Hans": "今天"],
            "Yesterday": ["de": "Gestern", "ru": "Вчера", "zh-Hans": "昨天"],
            "Last 200 events · kept only on this Mac": [
                "de": "Die letzten 200 Ereignisse · nur auf diesem Mac",
                "ru": "Последние 200 событий · только на этом Mac",
                "zh-Hans": "最近 200 条记录 · 仅保存在这台 Mac 上",
            ],
            "Clear": ["de": "Löschen", "ru": "Очистить", "zh-Hans": "清除"],
            "No events yet": ["de": "Noch keine Ereignisse", "ru": "Событий пока нет", "zh-Hans": "暂无记录"],
            "Run with Lid Closed turned on": [
                "de": "„Mit geschlossenem Deckel“ eingeschaltet",
                "ru": "Режим «С закрытой крышкой» включён",
                "zh-Hans": "已开启“合盖运行”",
            ],
            "Run with Lid Closed turned off": [
                "de": "„Mit geschlossenem Deckel“ ausgeschaltet",
                "ru": "Режим «С закрытой крышкой» выключен",
                "zh-Hans": "已关闭“合盖运行”",
            ],
            "Keep Screen On turned on": [
                "de": "„Bildschirm anlassen“ eingeschaltet",
                "ru": "Режим «Не гасить экран» включён",
                "zh-Hans": "已开启“保持屏幕常亮”",
            ],
            "Keep Screen On turned off": [
                "de": "„Bildschirm anlassen“ ausgeschaltet",
                "ru": "Режим «Не гасить экран» выключен",
                "zh-Hans": "已关闭“保持屏幕常亮”",
            ],
            "Paused": ["de": "Pausiert", "ru": "Пауза", "zh-Hans": "已暂停"],
            "Resumed": ["de": "Fortgesetzt", "ru": "Режим продолжен", "zh-Hans": "已恢复"],
            "Idle": ["de": "Leerlauf", "ru": "Простой", "zh-Hans": "空闲"],
            "Mac went to sleep": ["de": "Mac im Ruhezustand", "ru": "Mac уснул", "zh-Hans": "Mac 已进入睡眠"],
            "Mac woke up": ["de": "Mac aufgewacht", "ru": "Mac проснулся", "zh-Hans": "Mac 已唤醒"],
            "By you": ["de": "Manuell", "ru": "Вручную", "zh-Hans": "手动"],
            "The timer ended after %@.": [
                "de": "Der Timer ist nach %@ abgelaufen.",
                "ru": "Таймер сработал через %@.",
                "zh-Hans": "定时器在 %@后结束。",
            ],
            "Running on battery": ["de": "Akkubetrieb", "ru": "Mac работает от батареи", "zh-Hans": "使用电池供电"],
            "Power connected": ["de": "Netzteil angeschlossen", "ru": "Питание подключено", "zh-Hans": "已接通电源"],
            "The app asked macOS not to sleep.": [
                "de": "Die App bat macOS, wach zu bleiben.",
                "ru": "Программа попросила macOS не засыпать.",
                "zh-Hans": "该应用请求 macOS 不要进入睡眠。",
            ],
            "Busiest app: %@": ["de": "Aktivste App: %@", "ru": "Больше всего грузит: %@", "zh-Hans": "占用最高：%@"],
            "No work detected, counting %lld minutes": [
                "de": "Keine Arbeit erkannt, es werden %lld\u{00A0}Minuten gezählt",
                "ru": "Работы не видно, отсчёт %lld\u{00A0}мин",
                "zh-Hans": "未检测到任务，开始计时 %lld 分钟",
            ],
            "LidAwake was restarted.": [
                "de": "LidAwake wurde neu gestartet.",
                "ru": "LidAwake перезапустился.",
                "zh-Hans": "LidAwake 已重新启动。",
            ],
        ]
        XCTAssertEqual(expected.count, 24)
        let english = try table("en")
        for (key, translations) in expected {
            XCTAssertEqual(english[key], key)
            XCTAssertEqual(Set(translations.keys), ["de", "ru", "zh-Hans"], key)
            for (language, value) in translations {
                XCTAssertEqual(try table(language)[key], value, "\(language): \(key)")
            }
        }
    }

    func testBatteryLimitNoticeWithOnlyWhileCharging() throws {
        let key = "Not used with Only while charging"
        let expected = [
            "en": key,
            "de": "Ohne Wirkung bei „Nur am Netzteil“",
            "ru": "Не действует при «Только от зарядки»",
            "zh-Hans": "开启“仅在接通电源时运行”后不生效",
        ]
        for language in Self.languages {
            XCTAssertEqual(try table(language)[key], expected[language], language)
        }
    }

    func testIdleStopNoticeInEveryLanguage() throws {
        let withMinutes = [
            "en": "Nothing was working for %lld minutes.",
            "de": "Seit %lld\u{00A0}Minuten lief nichts mehr.",
            "ru": "%lld\u{00A0}мин ничего не работало.",
            "zh-Hans": "已有 %lld 分钟没有任务在运行。",
        ]
        let withoutMinutes = [
            "en": "Nothing was working for a while.",
            "de": "Es lief längere Zeit nichts mehr.",
            "ru": "Какое-то время ничего не работало.",
            "zh-Hans": "已有一段时间没有任务在运行。",
        ]
        for language in Self.languages {
            let table = try self.table(language)
            XCTAssertEqual(table["Nothing was working for %lld minutes."], withMinutes[language], language)
            XCTAssertEqual(table["Nothing was working for a while."], withoutMinutes[language], language)
        }
    }

    /// Copied from SecurityPrivacyExtension.appex on macOS 26.6.2: InfoPlist.loctable
    /// CFBundleDisplayName, Localizable.loctable "Advanced…" and
    /// "Log out automatically after inactivity", no-break spaces included.
    func testAutoLogoutHintUsesTheSystemLabels() throws {
        let key = "Privacy & Security > Advanced… > Log out automatically after inactivity"
        XCTAssertEqual(try table("en")[key], key)
        XCTAssertEqual(
            try table("de")[key],
            "Datenschutz & Sicherheit > Weitere Optionen\u{00A0}… > Nach Inaktivität automatisch abmelden"
        )
        XCTAssertEqual(
            try table("ru")[key],
            "«Конфиденциальность и безопасность» > «Дополнительно…» > «Автоматически выходить из\u{00A0}системы после бездействия»"
        )
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

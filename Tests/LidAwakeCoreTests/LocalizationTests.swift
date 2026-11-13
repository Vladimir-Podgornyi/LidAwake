import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let languages = ["en", "de", "ru", "zh-Hans", "ja", "fr", "es", "pt-BR", "ko", "it"]

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

    /// The plural forms of `key` in `language`, resolved the way the app resolves them.
    private func plural(_ key: String, _ language: String, _ count: Int) throws -> String {
        let folder = Self.root.appendingPathComponent("Resources/\(language).lproj")
        let bundle = try XCTUnwrap(Bundle(url: folder), language)
        let format = bundle.localizedString(forKey: key, value: "", table: nil)
        return String(format: format, locale: Locale(identifier: language), count)
    }

    private func pluralTable(_ language: String) throws -> [String: [String: Any]] {
        let url = Self.root.appendingPathComponent("Resources/\(language).lproj/Localizable.stringsdict")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(plist as? [String: [String: Any]], "\(language) is not a plural table")
    }

    func testEveryLanguageHasThePluralsOfTheStringsTable() throws {
        let english = try pluralTable("en")
        XCTAssertFalse(english.isEmpty)
        for language in Self.languages {
            let plurals = try pluralTable(language)
            XCTAssertEqual(Set(plurals.keys), Set(english.keys), language)
            let strings = try table(language)
            for (key, entry) in plurals {
                XCTAssertNotNil(strings[key], "\(language): \(key) has no fallback in the strings table")
                let rule = try XCTUnwrap(entry["updates"] as? [String: String], "\(language): \(key)")
                XCTAssertNotNil(rule["other"], "\(language): \(key)")
                for (category, value) in rule where !category.hasPrefix("NSString") {
                    XCTAssertEqual(try placeholders(value), try placeholders(key), "\(language): \(key) \(category)")
                }
            }
        }
    }

    func testEarlierUpdatesLine() throws {
        let key = "and %lld earlier updates"
        let expected: [String: [Int: String]] = [
            "en": [1: "and 1 earlier update", 2: "and 2 earlier updates", 5: "and 5 earlier updates"],
            "de": [1: "und 1 früheres Update", 2: "und 2 frühere Updates", 5: "und 5 frühere Updates"],
            "ru": [1: "и ещё 1 обновление", 2: "и ещё 2 обновления", 5: "и ещё 5 обновлений", 21: "и ещё 21 обновление"],
            "zh-Hans": [1: "以及另外 1 次更新", 2: "以及另外 2 次更新", 5: "以及另外 5 次更新"],
            "ja": [1: "ほか以前のアップデート1件", 2: "ほか以前のアップデート2件"],
            "fr": [1: "et 1 mise à jour précédente", 2: "et 2 mises à jour précédentes"],
            "es": [1: "y 1 actualización anterior", 2: "y 2 actualizaciones anteriores"],
            "pt-BR": [1: "e 1 atualização anterior", 2: "e 2 atualizações anteriores"],
            "ko": [1: "이전 업데이트 1개 더", 2: "이전 업데이트 2개 더"],
            "it": [1: "e 1 aggiornamento precedente", 2: "e 2 aggiornamenti precedenti"],
        ]
        XCTAssertEqual(Set(expected.keys), Set(Self.languages))
        for (language, forms) in expected {
            for (count, text) in forms {
                XCTAssertEqual(try plural(key, language, count), text, "\(language): \(count)")
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
        // Italian and Brazilian Portuguese write the percent sign without a space.
        let units = [
            "de": "%|Min\\.|Std\\.|Stunden?",
            "ru": "%|мин|ч|час|часа|часов",
            "fr": "%|min|h|heures?|minutes?",
            "es": "%|min|h|horas?|minutos?",
            "it": "min|h|ore|ora|minuti",
            "pt-BR": "min|h|horas?|minutos?",
        ]
        for (language, unit) in units {
            let ordinarySpace = try NSRegularExpression(pattern: "(%lld|\\d) (\(unit))(?!\\p{L})")
            for (key, value) in try table(language) {
                let range = NSRange(value.startIndex..., in: value)
                XCTAssertNil(ordinarySpace.firstMatch(in: value, range: range), "\(language): \(key)")
            }
        }
        XCTAssertEqual(String(format: try table("fr")["Battery %lld%%"]!, 82), "Batterie 82\u{00A0}%")
        XCTAssertEqual(String(format: try table("es")["Battery %lld%%"]!, 82), "Batería 82\u{00A0}%")
        XCTAssertEqual(String(format: try table("it")["Battery %lld%%"]!, 82), "Batteria 82%")
        XCTAssertEqual(String(format: try table("pt-BR")["Battery %lld%%"]!, 82), "Bateria 82%")
        XCTAssertEqual(String(format: try table("ja")["%lld h %lld min"]!, 1, 20), "1時間20分")
        XCTAssertEqual(String(format: try table("ko")["%lld h %lld min"]!, 1, 20), "1시간 20분")
    }

    func testFrenchSpacesBeforeHighPunctuationAndInsideQuotes() throws {
        let ordinarySpace = try NSRegularExpression(pattern: "( [:;!?»])|(« )")
        let missingSpace = try NSRegularExpression(pattern: "([^\\u00A0][:;!?»])|(«[^\\u00A0])")
        for (key, value) in try table("fr") {
            let range = NSRange(value.startIndex..., in: value)
            XCTAssertNil(ordinarySpace.firstMatch(in: value, range: range), "fr: \(key)")
            XCTAssertNil(missingSpace.firstMatch(in: value, range: range), "fr: \(key)")
        }
    }

    func testEachLanguageUsesItsOwnQuotes() throws {
        let foreign: [String: String] = [
            "fr": "[\"“”„]", "es": "[\"“”„]", "it": "[\"“”„]",
            "pt-BR": "[\"«»„]", "ja": "[\"“”«»]", "ko": "[\"«»„「」]",
        ]
        for (language, pattern) in foreign {
            let regex = try NSRegularExpression(pattern: pattern)
            for (key, value) in try table(language) {
                let range = NSRange(value.startIndex..., in: value)
                XCTAssertNil(regex.firstMatch(in: value, range: range), "\(language): \(key)")
                XCTAssertFalse(value.contains("'"), "\(language): \(key)")
            }
        }
    }

    func testJapaneseUsesFullWidthPunctuation() throws {
        let halfWidth = try NSRegularExpression(pattern: "[,.:;!?()]|[^ -~] >|> [^ -~]")
        for (key, value) in try table("ja") {
            let range = NSRange(value.startIndex..., in: value)
            XCTAssertNil(halfWidth.firstMatch(in: value, range: range), "ja: \(key)")
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
            "After the work is done · for one session": [
                "de": "Wenn die Arbeit erledigt ist · für eine Sitzung",
                "ru": "Когда работа закончена · на один сеанс",
                "zh-Hans": "任务完成后 · 仅限一次会话",
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

    func testSettingNoticeStrings() throws {
        let expected: [String: [String: String]] = [
            "Works only with Sleep when idle in Run with Lid Closed.": [
                "de": "Wirkt nur mit „Ruhezustand bei Leerlauf“ in „Mit geschlossenem Deckel“.",
                "ru": "Действует только при «Сон после простоя» в режиме «С закрытой крышкой».",
                "zh-Hans": "仅在“合盖运行”中开启“空闲时睡眠”时生效。",
            ],
            "The Mac is on battery, so the wake will not turn the mode on.": [
                "de": "Der Mac läuft mit Akku, daher schaltet das Aufwachen den Modus nicht ein.",
                "ru": "Mac работает от батареи, поэтому пробуждение не включит режим.",
                "zh-Hans": "Mac 正在使用电池，唤醒后不会开启该模式。",
            ],
            "If the Mac is asleep, every day, on power only": [
                "de": "Wenn der Mac schläft, täglich, nur am Netzteil",
                "ru": "Если Mac спит, каждый день, только от сети",
                "zh-Hans": "如果 Mac 处于睡眠，每天，仅在接通电源时",
            ],
            "On for this session, turned on by Wake at.": [
                "de": "Für diese Sitzung an, eingeschaltet durch „Aufwachen um“.",
                "ru": "Включён на этот сеанс через «Проснуться в».",
                "zh-Hans": "已由“唤醒时间”为本次会话开启。",
            ],
            "%@ The timer keeps counting.": [
                "de": "%@ Der Timer läuft weiter.",
                "ru": "%@ Таймер продолжает считать.",
                "zh-Hans": "%@计时器会继续计时。",
            ],
            "Set to 4 hours for watched apps.": [
                "de": "Für beobachtete Apps auf 4\u{00A0}Stunden gestellt.",
                "ru": "Стоит на 4\u{00A0}часа для программ под наблюдением.",
                "zh-Hans": "已因监视的应用设为 4 小时。",
            ],
            "Will be set to 4 hours for watched apps when the mode ends.": [
                "de": "Wird für beobachtete Apps auf 4\u{00A0}Stunden gestellt, wenn der Modus endet.",
                "ru": "Встанет на 4\u{00A0}часа для программ под наблюдением, когда режим выключится.",
                "zh-Hans": "模式结束后，将因监视的应用设为 4 小时。",
            ],
            "This Mac has no battery.": [
                "de": "Dieser Mac hat keinen Akku.",
                "ru": "У этого Mac нет батареи.",
                "zh-Hans": "此 Mac 没有电池。",
            ],
        ]
        let english = try table("en")
        for (key, translations) in expected {
            XCTAssertEqual(english[key], key)
            for (language, value) in translations {
                XCTAssertEqual(try table(language)[key], value, "\(language): \(key)")
            }
        }
        XCTAssertNil(english["Every day, on power only"])
        XCTAssertNil(english["After the work is done"])
    }

    func testBatteryLimitNoticeWithOnlyWhileCharging() throws {
        let key = "Not used with Only while charging"
        let expected = [
            "en": key,
            "de": "Ohne Wirkung bei „Nur am Netzteil“",
            "ru": "Не действует при «Только от зарядки»",
            "zh-Hans": "开启“仅在接通电源时运行”后不生效",
            "ja": "「電源接続時のみ」がオンのときは無効",
            "fr": "Sans effet avec «\u{00A0}Sur secteur uniquement\u{00A0}»",
            "es": "Sin efecto con «Solo con corriente»",
            "pt-BR": "Sem efeito com “Só na tomada”",
            "ko": "‘전원 연결 시에만’이 켜져 있으면 사용되지 않음",
            "it": "Senza effetto con «Solo con alimentatore»",
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
            "ja": "%lld分間、何も動作していませんでした。",
            "fr": "Rien n’a fonctionné pendant %lld\u{00A0}minutes.",
            "es": "No hubo actividad durante %lld\u{00A0}minutos.",
            "pt-BR": "Nada estava em execução por %lld\u{00A0}minutos.",
            "ko": "%lld분 동안 아무 작업도 없었습니다.",
            "it": "Nessuna attività per %lld\u{00A0}minuti.",
        ]
        let withoutMinutes = [
            "en": "Nothing was working for a while.",
            "de": "Es lief längere Zeit nichts mehr.",
            "ru": "Какое-то время ничего не работало.",
            "zh-Hans": "已有一段时间没有任务在运行。",
            "ja": "しばらく何も動作していませんでした。",
            "fr": "Rien n’a fonctionné depuis un moment.",
            "es": "No hubo actividad durante un rato.",
            "pt-BR": "Nada estava em execução por um tempo.",
            "ko": "한동안 아무 작업도 없었습니다.",
            "it": "Nessuna attività da un po’.",
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
        let hints = [
            "ja": "「プライバシーとセキュリティ」＞「詳細…」＞「操作がなければ自動的にログアウト」",
            "fr": "Confidentialité et sécurité > Avancé… > Fermer automatiquement la session en cas d’inactivité",
            "es": "Privacidad y seguridad > Avanzado… > Cerrar sesión automáticamente tras un tiempo de inactividad",
            "pt-BR": "Privacidade e Segurança > Avançado… > Finalizar sessão automaticamente após inatividade",
            "ko": "개인정보 보호 및 보안 > 고급… > 비활성 상태 후 자동으로 로그아웃",
            "it": "Privacy e sicurezza > Avanzate… > Esegui il logout automaticamente dopo l’inattività",
        ]
        for (language, hint) in hints {
            XCTAssertEqual(try table(language)[key], hint, language)
        }
    }

    /// Mode names and the main settings in the languages added with 1.2. Login Items, General,
    /// System Settings, Appearance and Open at Login are the names System Settings uses.
    func testGlossaryTermsInTheNewLanguages() throws {
        let glossary: [String: [String]] = [
            //                       ja, fr, es, pt-BR, ko, it
            "Off": ["オフ", "Désactivé", "Desactivado", "Desativado", "끔", "Disattivato"],
            "Keep Screen On": [
                "画面を消さない", "Garder l’écran allumé", "Mantener la pantalla encendida",
                "Manter a tela ligada", "화면 켜두기", "Schermo sempre acceso",
            ],
            "Run with Lid Closed": [
                "蓋を閉じたまま", "Capot fermé", "Con la tapa cerrada", "Com a tampa fechada", "덮개 닫고 실행", "A\u{00A0}coperchio chiuso",
            ],
            "Movie on a TV": ["テレビで映画", "Film sur la télé", "Película en la tele", "Filme na TV", "TV로 영화 보기", "Film sulla TV"],
            "In a Bag": ["バッグの中", "Dans un sac", "En la mochila", "Na mochila", "가방 속", "In borsa"],
            "Safety": ["保護", "Protections", "Protecciones", "Proteções", "보호", "Protezioni"],
            "Timer": ["タイマー", "Minuteur", "Temporizador", "Timer", "타이머", "Timer"],
            "Sleep and wake": [
                "スリープとスリープ解除", "Suspension et réactivation", "Reposo y activación", "Repouso e despertar",
                "잠자기 및 깨우기", "Standby e riattivazione",
            ],
            "General": ["一般", "Général", "General", "Geral", "일반", "Generali"],
            "Only while charging": [
                "電源接続時のみ", "Sur secteur uniquement", "Solo con corriente", "Só na tomada", "전원 연결 시에만", "Solo con alimentatore",
            ],
            "Turn off after": ["自動オフ", "Désactiver après", "Desactivar tras", "Desativar após", "자동 끄기", "Disattiva dopo"],
            "Sleep when idle": [
                "アイドル時にスリープ", "Suspendre si inactif", "Reposo por inactividad", "Repousar se ocioso", "유휴 시 잠자기", "Standby se inattivo",
            ],
            "Wake at": ["スリープ解除時刻", "Réactiver à", "Activar a las", "Despertar às", "깨우기 시각", "Riattiva alle"],
            "Launch at login": [
                "ログイン時に開く", "Ouvrir avec la session", "Abrir al iniciar sesión", "Abrir no início da sessão",
                "로그인 시 열기", "Apri al login",
            ],
            "Appearance": ["外観", "Apparence", "Aspecto", "Aparência", "화면 모드", "Aspetto"],
            "Settings": ["設定", "Réglages", "Ajustes", "Ajustes", "설정", "Impostazioni"],
            "Watched apps": ["監視するアプリ", "Apps surveillées", "Apps vigiladas", "Apps monitorados", "지켜보는 앱", "App monitorate"],
            "Activity log": ["アクティビティログ", "Journal d’activité", "Registro de actividad", "Registro de atividades", "활동 기록", "Registro attività"],
            "Quit LidAwake": ["LidAwakeを終了", "Quitter LidAwake", "Salir de LidAwake", "Encerrar LidAwake", "LidAwake 종료", "Esci da LidAwake"],
        ]
        let languages = ["ja", "fr", "es", "pt-BR", "ko", "it"]
        let tables = try languages.map(table)
        for (key, terms) in glossary {
            XCTAssertEqual(terms.count, languages.count, key)
            for (index, term) in terms.enumerated() {
                XCTAssertEqual(tables[index][key], term, "\(languages[index]): \(key)")
            }
        }
    }

    func testSettingsPathUsesTheSystemNames() throws {
        let english = "System Settings > General > Login Items & Extensions"
        let paths = [
            "de": "Systemeinstellungen > Allgemein > Anmeldeobjekte & Erweiterungen",
            "ru": "«Системные настройки» > «Основные» > «Объекты входа и расширения»",
            "ja": "「システム設定」＞「一般」＞「ログイン項目と機能拡張」",
            "fr": "Réglages Système > Général > Ouverture et extensions",
            "es": "Ajustes del Sistema > General > Ítems de inicio y extensiones",
            "pt-BR": "Ajustes do Sistema > Geral > Itens de Início de Sessão e Extensões",
            "ko": "시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램",
            "it": "Impostazioni di Sistema > Generali > Elementi login ed estensioni",
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

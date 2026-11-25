import AppKit
import CoreGraphics

/// Что делает кнопка.
enum KeydeckAction {
    case none
    case paste(String)
    case type(String)
    case say(String)
    case shell(String)

    static func from(_ binding: KeyBinding) -> KeydeckAction {
        switch (binding.action ?? "none").lowercased() {
        case "paste": return .paste(binding.text ?? "")
        case "type": return .type(binding.text ?? "")
        case "say": return .say(binding.text ?? "")
        case "shell": return .shell(binding.command ?? "")
        default: return .none
        }
    }

    var isNone: Bool {
        if case .none = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .none: return "none"
        case .paste(let t): return "paste \(t.prefix(40))"
        case .type(let t): return "type \(t.prefix(40))"
        case .say(let t): return "say \(t.prefix(40))"
        case .shell(let c): return "shell \(c.prefix(40))"
        }
    }
}

/// Клавиша, которую можно нажать после действия.
/// Виртуальные коды macOS (не HID usage).
enum KeydeckKey: String, CaseIterable {
    case returnKey = "return"
    case tab
    case escape
    case space
    case down
    case up

    var keyCode: CGKeyCode {
        switch self {
        case .returnKey: return 36
        case .tab: return 48
        case .escape: return 53
        case .space: return 49
        case .down: return 125
        case .up: return 126
        }
    }

    var title: String {
        switch self {
        case .returnKey: return "Enter"
        case .tab: return "Tab"
        case .escape: return "Escape"
        case .space: return Lang.shared.t("Пробел", "空格", "Space")
        case .down: return Lang.shared.t("Стрелка вниз", "下箭头", "Down")
        case .up: return Lang.shared.t("Стрелка вверх", "上箭头", "Up")
        }
    }

    /// Короткий знак для клавиши на карточке подтверждения.
    var glyph: String {
        switch self {
        case .returnKey: return "⏎"
        case .tab: return "⇥"
        case .escape: return "esc"
        case .space: return "␣"
        case .down: return "↓"
        case .up: return "↑"
        }
    }

    static func from(_ raw: String?) -> KeydeckKey? {
        guard let raw, !raw.isEmpty else { return nil }
        return KeydeckKey(rawValue: raw.lowercased())
    }

    /// Варианты для выпадающего списка: пустая строка = не нажимать ничего.
    static var pickerOptions: [(String, String)] {
        [("", "ничего")] + KeydeckKey.allCases.map { ($0.rawValue, $0.title) }
    }
}

/// Что показать на карточке подтверждения.
struct ConfirmPreview: Equatable {
    /// Крупный текст: подпись или само действие.
    var headline: String
    /// Динамик стоит у крупного текста: действие кнопки — произнести эту фразу.
    var headlineIsVoice: Bool
    /// Подпись над мелкой строкой («команда», «вставит»).
    var detailCaption: String?
    /// Мелкий текст, чтобы сверить команду или содержимое.
    var detail: String?
    /// Фраза, которую скажет после действия. Отдельная строка с динамиком.
    var voice: String?
    var press: KeydeckKey?

    static let empty = ConfirmPreview(
        headline: "",
        headlineIsVoice: false,
        detailCaption: nil,
        detail: nil,
        voice: nil,
        press: nil
    )
}

private func trimmed(_ value: String?) -> String? {
    let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? nil : text
}

/// Собирает карточку: крупно — что делает кнопка, мелко — команда для сверки,
/// Enter и голос — отдельной строкой.
func confirmPreview(for binding: KeyBinding) -> ConfirmPreview {
    let caption = trimmed(binding.description)
    let followUp = trimmed(binding.say)
    let press = KeydeckKey.from(binding.press)

    switch binding.kind {
    case .none:
        return ConfirmPreview(
            headline: caption ?? "У кнопки нет действия",
            headlineIsVoice: false,
            detailCaption: nil,
            detail: nil,
            voice: followUp,
            press: press
        )
    case .paste(let text):
        return textPreview(caption: caption, body: text, detailCaption: "paste",
                           voice: followUp, press: press)
    case .type(let text):
        return textPreview(caption: caption, body: text, detailCaption: "type",
                           voice: followUp, press: press)
    case .say(let text):
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let caption {
            return ConfirmPreview(
                headline: caption,
                headlineIsVoice: false,
                detailCaption: nil,
                detail: nil,
                voice: spoken.isEmpty ? followUp : spoken,
                press: press
            )
        }
        return ConfirmPreview(
            headline: spoken.isEmpty ? "Пустая фраза" : spoken,
            headlineIsVoice: true,
            detailCaption: nil,
            detail: nil,
            voice: (followUp != nil && followUp != spoken) ? followUp : nil,
            press: press
        )
    case .shell(let command):
        let body = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConfirmPreview(
            headline: caption ?? "Команда",
            headlineIsVoice: false,
            detailCaption: "command",
            detail: body.isEmpty ? "пустая команда" : body,
            voice: followUp,
            press: press
        )
    }
}

/// Крупно подпись, если она задана, а сам текст — мелко под ней. Без подписи
/// крупно выводится текст действия.
private func textPreview(caption: String?,
                         body: String,
                         detailCaption: String,
                         voice: String?,
                         press: KeydeckKey?) -> ConfirmPreview {
    let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if let caption {
        return ConfirmPreview(
            headline: caption,
            headlineIsVoice: false,
            detailCaption: detailCaption,
            detail: text.isEmpty ? "пустой текст" : text,
            voice: voice,
            press: press
        )
    }
    return ConfirmPreview(
        headline: text.isEmpty ? "Пустой текст" : text,
        headlineIsVoice: false,
        detailCaption: nil,
        detail: nil,
        voice: voice,
        press: press
    )
}

/// Выполняет действия. Вызывается из главного потока.
enum ActionRunner {
    /// kVK_ANSI_V — вставка.
    private static let keyV: CGKeyCode = 9

    /// Задержка перед нажатием клавиши по умолчанию, мс. Приложение-получатель
    /// должно успеть обработать вставку текста: иначе Enter уходит в пустое поле
    /// и «отправить» не срабатывает (так ведёт себя, например, Telegram).
    static let defaultFollowUpDelayMS = 250

    /// Выполняет действие, затем нажимает заданную клавишу и произносит текст.
    /// Для `shell` и клавиша, и озвучка срабатывают только при успешном
    /// завершении команды: нажимать Enter после упавшей команды не надо.
    static func run(_ action: KeydeckAction,
                    pressKey: String? = nil,
                    sayAfter: String? = nil,
                    delayMS: Int? = nil) {
        let key = KeydeckKey.from(pressKey)
        let announce = (sayAfter?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? sayAfter
            : nil

        // Клавиша и озвучка идут с задержкой: кнопка нажимается быстрее, чем
        // приложение успевает увидеть вставленный текст.
        func followUp() {
            guard key != nil || announce != nil else { return }
            let delay = Double(delayMS ?? defaultFollowUpDelayMS) / 1000.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let key { press(key) }
                if let announce { say(announce) }
            }
        }

        switch action {
        case .none:
            followUp()
        case .paste(let text):
            paste(text)
            followUp()
        case .type(let text):
            type(text)
            followUp()
        case .say(let text):
            say(text)
            followUp()
        case .shell(let command):
            shell(command) { succeeded in
                if succeeded { followUp() }
            }
        }
    }

    // MARK: - Вставить текст через буфер обмена

    private static func paste(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        usleep(30_000)  // дать буферу примениться
        postKey(keyV, flags: .maskCommand)

        // Буфер обмена — общий ресурс, возвращаем прежнее содержимое.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            restorePasteboard(pasteboard, snapshot)
        }
    }

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard,
                                          _ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        pasteboard.clearContents()
        let items = snapshot.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    // MARK: - Напечатать текст напрямую

    /// Печатает через `keyboardSetUnicodeString`: буфер обмена не трогается.
    /// За один эвент можно передать не больше 20 UTF-16 единиц.
    private static func type(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 20, units.count)])
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                chunk.withUnsafeBufferPointer { buffer in
                    down.keyboardSetUnicodeString(stringLength: buffer.count,
                                                  unicodeString: buffer.baseAddress)
                }
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.post(tap: .cghidEventTap)
            }
            index += chunk.count
            usleep(10_000)
        }
    }

    // MARK: - Произнести текст

    /// Системный `say`. Текст передаётся аргументом, а не через шелл, поэтому
    /// кавычки и прочие спецсимволы в нём безопасны.
    private static func say(_ text: String) {
        guard !text.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [text]
        do {
            try process.run()
        } catch {
            Log.shared.write("say не запустился: \(error)")
        }
    }

    // MARK: - Выполнить команду

    private static func shell(_ command: String, completion: @escaping (Bool) -> Void) {
        guard !command.isEmpty else {
            completion(false)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // -l: логин-шелл, иначе у приложения-агента пустой PATH.
        process.arguments = ["-lc", command]

        // Вывод команды забираем себе. Иначе он уходит в стандартный вывод
        // приложения (а у автозапуска это лог LaunchAgent'а), где его никто не
        // видит. Читаем потоком, а не после завершения: большой вывод заполнил бы
        // буфер канала и команда зависла бы навсегда.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                Log.shared.write("[вывод] \(line)")
            }
        }

        process.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let succeeded = finished.terminationStatus == 0
            if !succeeded {
                Log.shared.write("команда завершилась с кодом \(finished.terminationStatus): \(command)")
            }
            DispatchQueue.main.async { completion(succeeded) }
        }
        do {
            try process.run()
        } catch {
            Log.shared.write("команда не запустилась: \(error)")
            completion(false)
        }
    }

    // MARK: - Нажать клавишу после действия

    /// Enter, Tab и прочее — тем же синтезом, что и Cmd+V при вставке.
    private static func press(_ key: KeydeckKey) {
        postKey(key.keyCode)
    }

    // MARK: - Синтез клавиш

    private static func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            usleep(8_000)
        }
    }
}

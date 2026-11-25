import Foundation

/// Одна привязка кнопки. Поля зависят от `action`:
///   paste / type / say -> text
///   shell              -> command
///   say                -> что произнести после выполнения действия (необязательно)
///   description        -> крупная подпись на карточке подтверждения
///   press              -> какую клавишу нажать после действия (return, tab, …)
///   delay              -> пауза перед этой клавишей в мс (по умолчанию 250)
///   confirm            -> спрашивать подтверждение перед выполнением
struct KeyBinding: Decodable {
    let action: String?
    let text: String?
    let command: String?
    let say: String?
    let description: String?
    let press: String?
    let delay: Int?
    let confirm: Bool?

    init(action: String?,
         text: String?,
         command: String?,
         say: String? = nil,
         description: String? = nil,
         press: String? = nil,
         delay: Int? = nil,
         confirm: Bool? = nil) {
        self.action = action
        self.text = text
        self.command = command
        self.say = say
        self.description = description
        self.press = press
        self.delay = delay
        self.confirm = confirm
    }

    var kind: KeydeckAction { KeydeckAction.from(self) }
}

/// Файл привязок лежит в Application Support: `bindings.json`.
/// Индекс в массиве = кнопка keydeck: 0 — верхняя левая (F13), 7 — нижняя правая (F20).
struct Config: Decodable {
    let bindings: [KeyBinding]?

    /// Сколько кнопок у устройства.
    static let buttonCount = 8

    /// Подписи позиций на корпусе — те же, что в README прошивки.
    static let buttonTitles = [
        "Кнопка 1 (F13) — верхний ряд, 1-я",
        "Кнопка 2 (F14) — верхний ряд, 2-я",
        "Кнопка 3 (F15) — верхний ряд, 3-я",
        "Кнопка 4 (F16) — верхний ряд, 4-я",
        "Кнопка 5 (F17) — нижний ряд, 1-я",
        "Кнопка 6 (F18) — нижний ряд, 2-я",
        "Кнопка 7 (F19) — нижний ряд, 3-я",
        "Кнопка 8 (F20) — нижний ряд, 4-я",
    ]

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/keydeck", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("bindings.json") }

    private static let comment = """
    Привязки кнопок keydeck. Индекс = кнопка: 0 — верхняя левая (F13), 7 — нижняя правая (F20). \
    action: paste (вставить текст через буфер обмена) | type (напечатать текст напрямую) | \
    say (произнести текст) | shell (выполнить команду) | none. \
    Поля: text для paste/type/say, command для shell, \
    say — что произнести после выполнения действия (для shell — только при успехе), \
    description — крупная подпись на карточке подтверждения (команда под ней мелкая), \
    press — какую клавишу нажать после (return, tab, escape, space, down, up), \
    delay — пауза перед этой клавишей в мс (по умолчанию 250), \
    confirm — true, чтобы перед выполнением спросить подтверждение (той же кнопкой).
    """

    static let defaultJSON = """
    {
      "_comment": "\(comment)",
      "bindings": [
        { "action": "paste", "text": "keydeck: кнопка 1 (F13)" },
        { "action": "paste", "text": "keydeck: кнопка 2 (F14)" },
        { "action": "paste", "text": "keydeck: кнопка 3 (F15)" },
        { "action": "paste", "text": "keydeck: кнопка 4 (F16)" },
        { "action": "paste", "text": "keydeck: кнопка 5 (F17)" },
        { "action": "paste", "text": "keydeck: кнопка 6 (F18)" },
        { "action": "paste", "text": "keydeck: кнопка 7 (F19)" },
        { "action": "say", "text": "Кнопка восемь. Задача выполнена." }
      ]
    }
    """

    /// Создаёт файл с демо-привязками, если его ещё нет.
    static func ensureDefaultExists() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        do {
            try defaultJSON.write(to: fileURL, atomically: true, encoding: .utf8)
            Log.shared.write("создан конфиг по умолчанию: \(fileURL.path)")
        } catch {
            Log.shared.write("не удалось создать конфиг: \(error)")
        }
    }

    static func load() -> Config {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            Log.shared.write("конфиг не прочитан (\(error)); беру пустой")
            return Config(bindings: [])
        }
    }

    /// Действие для кнопки: всё, что вне массива или с неизвестным action, — none.
    func action(forButton index: Int) -> KeydeckAction {
        guard let bindings, index >= 0, index < bindings.count else { return .none }
        return bindings[index].kind
    }

    /// Что произнести после действия этой кнопки (nil — ничего).
    func say(forButton index: Int) -> String? {
        guard let bindings, index >= 0, index < bindings.count else { return nil }
        let value = bindings[index].say?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// Какую клавишу нажать после действия (nil — никакую).
    func press(forButton index: Int) -> String? {
        guard let bindings, index >= 0, index < bindings.count else { return nil }
        return KeydeckKey.from(bindings[index].press)?.rawValue
    }

    /// Пауза перед нажатием клавиши, мс (nil — значение по умолчанию).
    func delay(forButton index: Int) -> Int? {
        guard let bindings, index >= 0, index < bindings.count else { return nil }
        guard let value = bindings[index].delay, value >= 0 else { return nil }
        return value
    }

    /// Спрашивать ли подтверждение перед выполнением.
    func confirm(forButton index: Int) -> Bool {
        guard let bindings, index >= 0, index < bindings.count else { return false }
        return bindings[index].confirm ?? false
    }

    /// Привязка кнопки (для описания в окне подтверждения).
    func binding(forButton index: Int) -> KeyBinding? {
        guard let bindings, index >= 0, index < bindings.count else { return nil }
        return bindings[index]
    }

    /// Ровно `buttonCount` привязок: недостающие добираются как none, чтобы
    /// в окне настроек всегда было видно все кнопки.
    func paddedBindings() -> [KeyBinding] {
        let existing = bindings ?? []
        return (0..<Config.buttonCount).map { index in
            index < existing.count ? existing[index] : KeyBinding(action: "none", text: nil, command: nil)
        }
    }

    /// Перезаписывает файл привязок (вызывается из окна настроек).
    static func save(_ bindings: [KeyBinding]) throws {
        // [String: Any], а не [String: String]: delay должен уйти числом, иначе
        // при следующем чтении Int? его не разберёт.
        let items: [[String: Any]] = bindings.map { binding in
            var item: [String: Any] = ["action": binding.action ?? "none"]
            if let text = binding.text { item["text"] = text }
            if let command = binding.command { item["command"] = command }
            if let say = binding.say, !say.isEmpty { item["say"] = say }
            if let description = binding.description, !description.isEmpty {
                item["description"] = description
            }
            if let press = binding.press, !press.isEmpty { item["press"] = press }
            if let delay = binding.delay { item["delay"] = delay }
            if binding.confirm == true { item["confirm"] = true }
            return item
        }
        let root: [String: Any] = ["_comment": comment, "bindings": items]
        let data = try JSONSerialization.data(withJSONObject: root,
                                             options: [.prettyPrinted, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

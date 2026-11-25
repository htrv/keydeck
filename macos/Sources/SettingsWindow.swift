import AppKit
import SwiftUI

/// Черновик привязки для окна настроек.
struct BindingDraft: Identifiable {
    let id: Int
    var action: String
    var text: String
    var command: String
    var say: String
    var description: String
    var press: String
    /// Пауза перед клавишей в мс; пусто — значение по умолчанию.
    var delay: String
    var confirm: Bool

    init(id: Int, binding: KeyBinding) {
        self.id = id
        self.action = binding.action ?? "none"
        self.text = binding.text ?? ""
        self.command = binding.command ?? ""
        self.say = binding.say ?? ""
        self.description = binding.description ?? ""
        self.press = KeydeckKey.from(binding.press)?.rawValue ?? ""
        self.delay = binding.delay.map(String.init) ?? ""
        self.confirm = binding.confirm ?? false
    }

    private var sayValue: String? {
        let trimmed = say.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var descriptionValue: String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var pressValue: String? { press.isEmpty ? nil : press }

    private var delayValue: Int? {
        let trimmed = delay.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }

    /// В файл пишем только те поля, которые относятся к выбранному действию.
    var binding: KeyBinding {
        let confirmValue: Bool? = confirm ? true : nil
        switch action {
        case "paste", "type", "say":
            return KeyBinding(action: action, text: text, command: nil,
                              say: sayValue, description: descriptionValue,
                              press: pressValue, delay: delayValue,
                              confirm: confirmValue)
        case "shell":
            return KeyBinding(action: action, text: nil, command: command,
                              say: sayValue, description: descriptionValue,
                              press: pressValue, delay: delayValue,
                              confirm: confirmValue)
        default:
            return KeyBinding(action: "none", text: nil, command: nil,
                              say: sayValue, description: descriptionValue,
                              press: pressValue, delay: delayValue,
                              confirm: confirmValue)
        }
    }

    /// Короткая подпись для плитки в сетке.
    var summary: String {
        var base: String
        switch action {
        case "paste": base = Lang.shared.t("Вставить: \(text)", "粘贴：\(text)", "Paste: \(text)")
        case "type": base = Lang.shared.t("Напечатать: \(text)", "键入：\(text)", "Type: \(text)")
        case "say": base = Lang.shared.t("Проговорить: \(text)", "朗读：\(text)", "Speak: \(text)")
        case "shell": base = Lang.shared.t("Команда: \(descriptionValue ?? command)",
                                           "命令：\(descriptionValue ?? command)",
                                           "Command: \(descriptionValue ?? command)")
        default: base = Lang.shared.t("действия нет", "无动作", "no action")
        }
        if let key = KeydeckKey.from(press) { base += " → \(key.title)" }
        if let sayValue {
            base += Lang.shared.t(" → сказать: \(sayValue)", " → 朗读：\(sayValue)", " → say: \(sayValue)")
        }
        if confirm { base = Lang.shared.t("подтверждать: ", "需确认：", "confirm: ") + base }
        return base
    }
}

private func actionOptions() -> [(String, String)] {
    [
        ("none", Lang.shared.t("Ничего", "无", "Nothing")),
        ("paste", Lang.shared.t("Вставить текст (через буфер обмена)", "粘贴文本（经剪贴板）", "Paste text (via clipboard)")),
        ("type", Lang.shared.t("Напечатать текст", "直接键入文本", "Type text")),
        ("say", Lang.shared.t("Произнести текст", "朗读文本", "Speak text")),
        ("shell", Lang.shared.t("Выполнить команду", "运行命令", "Run a command")),
    ]
}

struct SettingsView: View {
    @State var drafts: [BindingDraft]
    let onSave: ([KeyBinding]) -> Void
    let onClose: () -> Void

    /// Пример команды для кнопки «Подставить пример».
    static let deployExample = #"say \"Готово\""#

    @State private var selected = 0
    @State private var message = ""

    @ObservedObject private var highlight = PressHighlight.shared
    @ObservedObject private var lang = Lang.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(lang.t("Язык", "语言", "Language"), selection: $lang.current) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360, alignment: .leading)
                Text(lang.t("Кнопки расположены как на корпусе: 2 ряда по 4, слева направо.",
                            "按键布局与外壳一致：两行各四个，从左到右。",
                            "Buttons match the case: 2 rows of 4, left to right."))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                    Text(lang.t("Пока это окно открыто, кнопки только подсвечиваются — действия не выполняются.",
                                "设置窗口打开时，按键只高亮，不执行动作。",
                                "While this window is open, buttons only highlight — actions do not run."))
                    Spacer(minLength: 0)
                    if let last = highlight.last {
                        Text(lang.t("нажата: \(last + 1)", "已按下：\(last + 1)", "pressed: \(last + 1)"))
                            .foregroundColor(.accentColor)
                    }
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                buttonGrid
                Divider()
                editor
            }
            .padding(16)

            Divider()
            Text(lang.t("Благодарность: \(Support.bitcoinAddress)",
                        "感谢：\(Support.bitcoinAddress)",
                        "Tips: \(Support.bitcoinAddress)"))
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            HStack(spacing: 10) {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer()
                Button(lang.t("Отмена", "取消", "Cancel")) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button(lang.t("Сохранить и закрыть", "保存并关闭", "Save and close")) { saveAndClose() }
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 600)
        // Нажатие физической кнопки не только подсвечивает плитку, но и выбирает
        // её — чтобы сразу править привязку этой кнопки.
        .onChange(of: highlight.last) { _, newValue in
            if let index = newValue, drafts.indices.contains(index) {
                selected = index
            }
        }
    }

    // MARK: - Сетка кнопок

    private var buttonGrid: some View {
        HStack {
            Spacer(minLength: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(132), spacing: 10), count: 4),
                      spacing: 10) {
                ForEach(drafts.indices, id: \.self) { index in
                    tile(index)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func tile(_ index: Int) -> some View {
        let draft = drafts[index]
        let isSelected = index == selected
        let isPressed = highlight.pressed == index
        return Button {
            selected = index
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("F\(13 + index)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(draft.summary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 132, height: 72, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPressed
                          ? Color.accentColor.opacity(0.35)
                          : (isSelected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.10)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isPressed || isSelected ? Color.accentColor : Color.gray.opacity(0.28),
                            lineWidth: isPressed ? 3 : (isSelected ? 2 : 1))
            )
        }
        .buttonStyle(.plain)
        .help(Config.buttonTitle(for: index))
    }

    // MARK: - Редактор выбранной кнопки

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(Config.buttonTitle(for: selected))
                    .font(.headline)

                Picker(lang.t("Действие", "动作", "Action"), selection: $drafts[selected].action) {
                    ForEach(actionOptions(), id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .frame(maxWidth: 400, alignment: .leading)

                switch drafts[selected].action {
                case "shell":
                    fieldLabel(lang.t("Подпись на карточке — крупно", "确认卡片上的大字标题", "Card title — large"))
                    TextField(lang.t("например: Деплой на прод", "例如：发布到生产", "for example: Deploy to production"),
                              text: $drafts[selected].description)
                        .textFieldStyle(.roundedBorder)
                    Text(lang.t("На подтверждении эта строка крупная, команда под ней — мелкая, чтобы сверить.",
                                "确认时这行字很大，命令在下面用小字，便于核对。",
                                "On the confirm card this line is large; the command stays small underneath so you can check it."))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    fieldLabel(lang.t("Команда (выполняется через /bin/sh -lc)",
                                       "命令（通过 /bin/sh -lc 执行）",
                                       "Command (run via /bin/sh -lc)"))
                    editorField(text: $drafts[selected].command, monospaced: true)
                    deployExample
                case "none":
                    Text(lang.t("Само по себе действие не выполняется.",
                                "本身不执行任何动作。",
                                "No action runs by itself."))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                default:
                    fieldLabel(lang.t("Текст", "文本", "Text"))
                    editorField(text: $drafts[selected].text, monospaced: false)
                }

                Divider().padding(.vertical, 2)

                fieldLabel(lang.t("После действия нажать клавишу", "动作之后按键", "Key to press after the action"))
                Picker("", selection: $drafts[selected].press) {
                    ForEach(KeydeckKey.pickerOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)

                HStack(spacing: 8) {
                    Text(lang.t("Пауза перед клавишей, мс:", "按键前的停顿，毫秒：", "Pause before the key, ms:"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("\(ActionRunner.defaultFollowUpDelayMS)",
                              text: $drafts[selected].delay)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text(lang.t("пусто — \(ActionRunner.defaultFollowUpDelayMS)",
                                "留空 — \(ActionRunner.defaultFollowUpDelayMS)",
                                "empty — \(ActionRunner.defaultFollowUpDelayMS)"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(lang.t(
                    "Пауза нужна, чтобы приложение успело увидеть вставленный текст. "
                        + "Без неё Enter уходит в пустое поле — так ведёт себя Telegram. "
                        + "Для «напечатать» паузу стоит увеличить.",
                    "停顿是为了让目标程序看到刚插入的文字。没有停顿时，Enter 会打进空输入框，Telegram 就是这样。直接键入时建议把停顿加长。",
                    "The pause lets the target app see the inserted text. Without it, Enter lands in an empty field — Telegram does this. Increase the pause when typing."
                ))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider().padding(.vertical, 2)

                Toggle(lang.t("Спрашивать подтверждение перед выполнением",
                               "执行前要求确认",
                               "Ask for confirmation before running"),
                       isOn: $drafts[selected].confirm)
                    .toggleStyle(.checkbox)
                Text(lang.t("Покажется карточка с описанием действия: нажатие той же кнопки — выполнить, любой другой — отмена.",
                            "会弹出动作说明：再按同一键执行，按其他键取消。",
                            "A card describes the action: the same button runs it, any other button cancels."))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider().padding(.vertical, 2)

                fieldLabel(lang.t("Произнести после выполнения — необязательно",
                                  "执行后朗读 — 可选",
                                  "Speak after running — optional"))
                TextField(lang.t("например: Готово", "例如：完成", "for example: Done"),
                          text: $drafts[selected].say)
                    .textFieldStyle(.roundedBorder)
                Text(drafts[selected].action == "shell"
                     ? lang.t("Для команды и клавиша, и озвучка срабатывают только если она завершилась успешно.",
                              "命令只有成功结束后才会按键和朗读。",
                              "For a command, the key and the voice run only if it succeeds.")
                     : lang.t("Клавиша и озвучка срабатывают сразу после действия.",
                              "按键和朗读在动作之后立刻发生。",
                              "The key and the voice run right after the action."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Пример команды — и кнопка, чтобы подставить его одним нажатием.
    private var deployExample: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(lang.t("Пример: произнести «Готово»", "示例：朗读「完成」", "Example: say “Done”"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                Button(lang.t("Подставить пример", "填入示例", "Insert example")) {
                    drafts[selected].command = lang.t(#"say \"Готово\""#, #"say \"完成\""#, #"say \"Done\""#)
                }
                .controlSize(.small)
            }
            Text(lang.t(#"say \"Готово\""#, #"say \"完成\""#, #"say \"Done\""#))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
            Text(lang.t("Это обычная команда оболочки. Можно дописать что угодно ещё.",
                        "这是普通的 shell 命令，后面可以再写别的。",
                        "This is an ordinary shell command. You can add anything else."))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private func editorField(text: Binding<String>, monospaced: Bool) -> some View {
        TextEditor(text: text)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .frame(minHeight: 96)
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.35), lineWidth: 1)
            )
    }

    // MARK: - Действия

    /// Сохраняем и закрываем. Если запись не удалась — окно остаётся открытым,
    /// чтобы правки не потерялись молча.
    private func saveAndClose() {
        do {
            try Config.save(drafts.map { $0.binding })
            onSave(drafts.map { $0.binding })
            onClose()
        } catch {
            message = Lang.shared.t("Не удалось сохранить: \(error.localizedDescription)",
                                     "保存失败：\(error.localizedDescription)",
                                     "Could not save: \(error.localizedDescription)")
        }
    }
}

/// Окно настроек. Пересоздаёт содержимое при каждом показе, чтобы в нём всегда
/// были актуальные привязки (их могли поменять в файле).
final class SettingsWindowController {
    private var window: NSWindow?
    private let onSave: ([KeyBinding]) -> Void
    private let onReload: () -> [KeyBinding]

    init(onSave: @escaping ([KeyBinding]) -> Void, onReload: @escaping () -> [KeyBinding]) {
        self.onSave = onSave
        self.onReload = onReload
    }

    /// Пока окно на экране, приложение не выполняет действия — только подсвечивает.
    var isVisible: Bool { window?.isVisible ?? false }

    /// Каждый показ окна заново читает файл привязок: правки могли сделать
    /// снаружи, да и после закрытия через «Отмена» черновик не должен остаться.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.contentView = NSHostingView(rootView: SettingsView(
            drafts: drafts(),
            onSave: onSave,
            onClose: { [weak window] in window?.close() }
        ))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func drafts() -> [BindingDraft] {
        onReload().enumerated().map { BindingDraft(id: $0.offset, binding: $0.element) }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = Lang.shared.t("keydeck — привязки кнопок",
                                      "keydeck — 按键绑定",
                                      "keydeck — button bindings")
        NotificationCenter.default.addObserver(forName: Lang.changed, object: nil, queue: .main) { [weak window] _ in
            window?.title = Lang.shared.t("keydeck — привязки кнопок",
                                           "keydeck — 按键绑定",
                                           "keydeck — button bindings")
        }
        window.isReleasedWhenClosed = false
        window.center()
        // Сбрасываем подсветку, чтобы при следующем открытии не осталось
        // «залипшего» нажатия.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: window,
                                               queue: .main) { _ in
            PressHighlight.shared.clear()
        }
        return window
    }
}

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
        case "paste": base = "Вставить: \(text)"
        case "type": base = "Напечатать: \(text)"
        case "say": base = "Проговорить: \(text)"
        case "shell": base = "Команда: \(descriptionValue ?? command)"
        default: base = "действия нет"
        }
        if let key = KeydeckKey.from(press) { base += " → \(key.title)" }
        if let sayValue { base += " → сказать: \(sayValue)" }
        if confirm { base = "подтверждать: " + base }
        return base
    }
}

private let actionOptions: [(String, String)] = [
    ("none", "Ничего"),
    ("paste", "Вставить текст (через буфер обмена)"),
    ("type", "Напечатать текст"),
    ("say", "Произнести текст"),
    ("shell", "Выполнить команду"),
]

struct SettingsView: View {
    @State var drafts: [BindingDraft]
    let onSave: ([KeyBinding]) -> Void
    let onClose: () -> Void

    /// Пример команды для кнопки «Подставить пример».
    static let deployExample = #"say \"Готово\""#

    @State private var selected = 0
    @State private var message = ""

    @ObservedObject private var highlight = PressHighlight.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Кнопки расположены как на корпусе: 2 ряда по 4, слева направо.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                    Text("Пока это окно открыто, кнопки только подсвечиваются — действия не выполняются.")
                    Spacer(minLength: 0)
                    if let last = highlight.last {
                        Text("нажата: \(last + 1)")
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
            Text("Благодарность: \(Support.bitcoinAddress)")
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
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить и закрыть") { saveAndClose() }
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
        .help(Config.buttonTitles[index])
    }

    // MARK: - Редактор выбранной кнопки

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(Config.buttonTitles[selected])
                    .font(.headline)

                Picker("Действие", selection: $drafts[selected].action) {
                    ForEach(actionOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .frame(maxWidth: 400, alignment: .leading)

                switch drafts[selected].action {
                case "shell":
                    fieldLabel("Подпись на карточке — крупно")
                    TextField("например: Деплой на прод", text: $drafts[selected].description)
                        .textFieldStyle(.roundedBorder)
                    Text("На подтверждении эта строка крупная, команда под ней — мелкая, чтобы сверить.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    fieldLabel("Команда (выполняется через /bin/sh -lc)")
                    editorField(text: $drafts[selected].command, monospaced: true)
                    deployExample
                case "none":
                    Text("Само по себе действие не выполняется.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                default:
                    fieldLabel("Текст")
                    editorField(text: $drafts[selected].text, monospaced: false)
                }

                Divider().padding(.vertical, 2)

                fieldLabel("После действия нажать клавишу")
                Picker("", selection: $drafts[selected].press) {
                    ForEach(KeydeckKey.pickerOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)

                HStack(spacing: 8) {
                    Text("Пауза перед клавишей, мс:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("\(ActionRunner.defaultFollowUpDelayMS)",
                              text: $drafts[selected].delay)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("пусто — \(ActionRunner.defaultFollowUpDelayMS)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("Пауза нужна, чтобы приложение успело увидеть вставленный текст. "
                     + "Без неё Enter уходит в пустое поле — так ведёт себя Telegram. "
                     + "Для «напечатать» паузу стоит увеличить.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider().padding(.vertical, 2)

                Toggle("Спрашивать подтверждение перед выполнением", isOn: $drafts[selected].confirm)
                    .toggleStyle(.checkbox)
                Text("Покажется карточка с описанием действия: нажатие той же кнопки — выполнить, любой другой — отмена.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider().padding(.vertical, 2)

                fieldLabel("Произнести после выполнения — необязательно")
                TextField("например: Готово", text: $drafts[selected].say)
                    .textFieldStyle(.roundedBorder)
                Text(drafts[selected].action == "shell"
                     ? "Для команды и клавиша, и озвучка срабатывают только если она завершилась успешно."
                     : "Клавиша и озвучка срабатывают сразу после действия.")
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
                Text("Пример: произнести «Готово»")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                Button("Подставить пример") {
                    drafts[selected].command = SettingsView.deployExample
                }
                .controlSize(.small)
            }
            Text(SettingsView.deployExample)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
            Text("Это обычная команда оболочки. Можно дописать что угодно ещё.")
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
            message = "Не удалось сохранить: \(error.localizedDescription)"
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
        window.title = "keydeck — привязки кнопок"
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

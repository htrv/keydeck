import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var tap: EventTap?
    private var config = Config(bindings: [])
    private var tapRunning = false

    private lazy var confirmPanel = ConfirmPanel()
    private var pendingConfirmButton: Int?
    private var confirmTimer: DispatchSourceTimer?
    private var confirmSecondsLeft = 0
    /// Поднимает CGEventTap, если система выключила его по таймауту, а
    /// уведомление tapDisabled* до колбэка не дошло — иначе все кнопки «мертвы».
    private var tapWatchdog: Timer?

    private lazy var settingsWindow = SettingsWindowController(
        onSave: { [weak self] _ in self?.reloadConfig() },
        onReload: { Config.load().paddedBindings() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Автозапуск при логине и ручной запуск могут дать два экземпляра, а два
        // перехватчика на одни и те же клавиши — двойные срабатывания.
        let bundleID = Bundle.main.bundleIdentifier ?? "ru.evgeniy.keydeck"
        let duplicates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !duplicates.isEmpty {
            Log.shared.write("keydeck уже запущен (pid \(duplicates.map(\.processIdentifier))), выходим")
            exit(0)
        }

        Log.shared.write("=== keydeck запущен (\(Bundle.main.bundlePath)) ===")

        setupMainMenu()
        Config.ensureDefaultExists()
        setupStatusItem()
        reloadConfig()

        if !accessibilityGranted() {
            Log.shared.write("нет разрешения Accessibility — прошу выдать")
            promptForAccessibility()
        }
        startTap()
        observeScreenLock()
    }

    /// Пока экран/сессия заблокированы — макросы не выполняем (безопасность).
    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cancelPendingConfirmation(reason: "экран заблокирован")
            Log.shared.write("экран заблокирован — макросы выключены")
        }
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { _ in
            Log.shared.write("экран разблокирован — макросы снова активны")
        }
    }

    /// true, если экран блокировки / loginwindow.
    private func isScreenLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        if let locked = info["CGSSessionScreenIsLocked"] as? Bool {
            return locked
        }
        return false
    }

    // MARK: - Главное меню

    /// Скрытое главное меню. У приложения-агента его не видно, но без него в
    /// текстовых полях не работают ⌘C / ⌘V / ⌘X / ⌘A: эти сочетания обрабатываются
    /// пунктами меню «Правка», а не самими полями. Заодно появляется ⌘, для
    /// открытия настроек.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Открыть настройки",
                                  action: #selector(openSettings),
                                  keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть keydeck",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(withTitle: "Выйти",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Правка")
        // target не задаём: вызовы уходят по цепочке респондеров в активное поле.
        editMenu.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Перехват

    private func startTap() {
        tapWatchdog?.invalidate()
        tapWatchdog = nil
        tap = nil
        tapRunning = false
        do {
            tap = try EventTap { [weak self] button, isDown in
                guard let self else { return false }
                return self.handle(button: button, isDown: isDown)
            }
            tapRunning = true
            Log.shared.write("перехват F13..F20 запущен")
            // Если колбэк тапа завис на UI (карточка подтверждения), macOS глушит
            // тап — и повторное нажатие «не доходит». Watchdog поднимает его обратно.
            let watchdog = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self, self.tapRunning else { return }
                if self.tap?.ensureEnabled() == true {
                    Log.shared.write("тап был выключен — включил обратно (watchdog)")
                }
            }
            // common: тикает и во время трекинга мыши / модальных циклов.
            RunLoop.main.add(watchdog, forMode: .common)
            tapWatchdog = watchdog
        } catch {
            Log.shared.write("перехват не запустился: нет разрешения Accessibility")
        }
        rebuildMenu()
    }

    private func handle(button: Int, isDown: Bool) -> Bool {
        // Заблокированный Mac: не вставляем текст и не гоняем shell.
        // Событие глотаем, чтобы F13..F20 не уходили «в никуда».
        if isScreenLocked() {
            if isDown {
                cancelPendingConfirmation(reason: "экран заблокирован")
                Log.shared.write("кнопка \(button + 1) (F\(13 + button)): экран заблокирован, игнор")
            }
            return true
        }

        // Пока открыто окно настроек — ничего не выполняем, только подсвечиваем,
        // чтобы можно было спокойно назначать привязки.
        if settingsWindow.isVisible {
            if isDown {
                cancelPendingConfirmation(reason: "открыты настройки")
                PressHighlight.shared.press(button)
                Log.shared.write("кнопка \(button + 1) (F\(13 + button)): настройки открыты, действие не выполняю")
            } else {
                PressHighlight.shared.release(button)
            }
            return true
        }

        // Уже ждём подтверждения: та же кнопка — выполняем, любая другая — отмена.
        if let pending = pendingConfirmButton {
            guard isDown else { return true }  // keyUp тоже поглощаем
            if button == pending {
                clearPendingConfirmation()
                Log.shared.write("кнопка \(button + 1): подтверждено, выполняю")
                executeAction(for: button)
            } else {
                cancelPendingConfirmation(reason: "нажата кнопка \(button + 1) (F\(13 + button))")
            }
            return true
        }

        let action = config.action(forButton: button)
        guard isDown else { return !action.isNone }  // keyUp глушим только для привязанных

        if action.isNone {
            Log.shared.write("кнопка \(button + 1) (F\(13 + button)): привязки нет")
            return false
        }

        // Кнопка с подтверждением: сначала показываем, что именно произойдёт.
        if config.confirm(forButton: button) {
            requestConfirmation(for: button)
            return true
        }

        executeAction(for: button)
        return true
    }

    /// Выполняет привязку кнопки (без проверок подтверждения).
    private func executeAction(for button: Int) {
        let action = config.action(forButton: button)
        let announce = config.say(forButton: button)
        let press = config.press(forButton: button)
        let delay = config.delay(forButton: button)
        var line = "кнопка \(button + 1) (F\(13 + button)) -> \(action.description)"
        if let press, let key = KeydeckKey.from(press) {
            line += ", затем \(key.title) через \(delay ?? ActionRunner.defaultFollowUpDelayMS) мс"
        }
        if let announce { line += ", затем сказать «\(announce)»" }
        Log.shared.write(line)
        // Действие выполняется на главном потоке: тап должен отвечать мгновенно,
        // а AppKit и синтез событий требуют главного потока.
        DispatchQueue.main.async {
            ActionRunner.run(action, pressKey: press, sayAfter: announce, delayMS: delay)
        }
    }

    // MARK: - Подтверждение

    /// Сколько секунд ждём подтверждения, прежде чем отменить его сами.
    private static let confirmTimeoutSeconds = 30

    private func requestConfirmation(for button: Int) {
        guard let binding = config.binding(forButton: button) else { return }
        // Состояние подтверждения ставим сразу (синхронно): следующий keyDown
        // той же кнопки должен увидеть pending, даже если карточка ещё не нарисована.
        pendingConfirmButton = button
        confirmSecondsLeft = Self.confirmTimeoutSeconds
        Log.shared.write("кнопка \(button + 1) (F\(13 + button)): жду подтверждения той же кнопкой")

        // Обратный отсчёт для карточки и страховочный таймаут: забытое
        // подтверждение не должно сработать от случайного нажатия через час.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.confirmSecondsLeft -= 1
            if self.confirmSecondsLeft <= 0 {
                self.cancelPendingConfirmation(reason: "истекло время ожидания")
            } else {
                self.confirmPanel.updateSecondsLeft(self.confirmSecondsLeft)
            }
        }
        confirmTimer = timer
        timer.resume()

        // Карточку рисуем на следующем витке runloop. Если делать это внутри
        // колбэка CGEventTap (layout SwiftUI + orderFront), колбэк не успевает
        // вернуться → macOS отключает тап → повторное нажатие для подтверждения
        // и остальные кнопки перестают доходить. На кнопке 4 текст команды длинный,
        // layout тяжелее — там это проявлялось чаще всего.
        let preview = confirmPreview(for: binding)
        let seconds = confirmSecondsLeft
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingConfirmButton == button else { return }
            self.confirmPanel.show(buttonIndex: button,
                                   preview: preview,
                                   secondsLeft: seconds) { [weak self] in
                self?.cancelPendingConfirmation(reason: "нажата кнопка «Отмена» в карточке")
            }
        }
    }

    private func clearPendingConfirmation() {
        confirmTimer?.cancel()
        confirmTimer = nil
        pendingConfirmButton = nil
        // orderOut лёгкий — можно сразу; async здесь опасен: успеет закрыть
        // уже новую карточку, если пользователь сразу нажал кнопку снова.
        confirmPanel.hide()
    }

    private func cancelPendingConfirmation(reason: String) {
        guard pendingConfirmButton != nil else { return }
        let button = pendingConfirmButton!
        clearPendingConfirmation()
        Log.shared.write("кнопка \(button + 1) (F\(13 + button)): отменено — \(reason)")
    }

    // MARK: - Разрешение

    private func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    @objc private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        Log.shared.write("показан системный запрос разрешения Accessibility")
        rebuildMenu()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Статус-бар

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌨"
        rebuildMenu()
    }

    private func rebuildMenu() {
        // Меню перестраивается и до создания статус-бара (например, из reloadConfig).
        guard let statusItem else { return }
        let menu = NSMenu()
        let trusted = accessibilityGranted()

        menu.addItem(disabledItem(trusted
            ? "Разрешение Accessibility: выдано"
            : "Разрешение Accessibility: НЕ выдано"))

        if trusted {
            menu.addItem(disabledItem(tapRunning ? "Перехват: работает" : "Перехват: не запущен"))
        } else {
            menu.addItem(item("Выдать разрешение…", #selector(promptForAccessibility)))
            menu.addItem(item("Открыть настройки приватности", #selector(openAccessibilitySettings)))
        }

        menu.addItem(.separator())
        let settings = item("Настройки…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(item("Открыть конфиг", #selector(openConfig)))
        menu.addItem(item("Перечитать конфиг", #selector(reloadConfig)))
        menu.addItem(item("Открыть лог", #selector(openLog)))
        menu.addItem(item("Благодарность: скопировать адрес", #selector(copyThanks)))
        menu.addItem(.separator())

        if !trusted || !tapRunning {
            menu.addItem(item("Перезапустить перехват", #selector(restartTap)))
        }

        let quit = NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func item(_ title: String, _ selector: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    // MARK: - Пункты меню

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func openConfig() {
        Config.ensureDefaultExists()
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func reloadConfig() {
        // Привязки могли измениться — висящее подтверждение больше не актуально.
        cancelPendingConfirmation(reason: "конфиг перечитан")
        config = Config.load()
        let count = (config.bindings ?? []).count
        Log.shared.write("конфиг перечитан: привязок \(count) (\(Config.fileURL.path))")
        rebuildMenu()
    }

    @objc private func copyThanks() {
        Support.copyBitcoinAddress()
        Log.shared.write("адрес благодарности скопирован")
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.fileURL)
    }

    @objc private func restartTap() {
        Log.shared.write("перезапуск перехвата")
        startTap()
    }
}

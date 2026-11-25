import AppKit

// Точка входа. Приложение-агент: живёт в статус-баре, окна и иконки в Dock нет.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

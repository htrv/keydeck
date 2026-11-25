import CoreGraphics
import Foundation

/// Глобальный перехват F13..F20 через CGEventTap.
///
/// Требует разрешения Accessibility: без него `CGEvent.tapCreate` вернёт nil.
/// Тап активный (`.defaultTap`), поэтому нажатие можно «проглотить» — тогда
/// клавиша не уйдёт в приложение под курсором.
final class EventTap {
    /// true — проглотить событие, false — пропустить дальше.
    typealias Handler = (_ buttonIndex: Int, _ isDown: Bool) -> Bool

    enum TapError: Error {
        case notPermitted
    }

    /// Виртуальные коды macOS для F13..F20 -> индекс кнопки keydeck.
    /// Внимание: это НЕ HID usage (F13 = HID 0x68, а тут 105).
    static let keycodeToButton: [Int64: Int] = [
        105: 0,  // F13
        107: 1,  // F14
        113: 2,  // F15
        106: 3,  // F16
        64: 4,   // F17
        79: 5,   // F18
        80: 6,   // F19
        90: 7,   // F20
    ]

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: Handler

    init(handler: @escaping Handler) throws {
        self.handler = handler

        // tapDisabled* в маску не кладём: у них rawValue ≈ 0xFFFFFFFE, сдвиг
        // в CGEventMask ломается. Система и так доставляет их в колбэк; плюс
        // watchdog в AppDelegate поднимает тап, если уведомление потерялось.
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw TapError.notPermitted
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Включить тап обратно, если система его выключила (timeout / user input).
    /// Возвращает true, если пришлось включать — для лога.
    @discardableResult
    func ensureEnabled() -> Bool {
        guard let tap else { return false }
        if CGEvent.tapIsEnabled(tap: tap) { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Система может отключить тап (таймаут или ввод пользователя) — включаем обратно.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.shared.write("тап перезапущен системой (\(type == .tapDisabledByTimeout ? "timeout" : "user input"))")
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard let button = EventTap.keycodeToButton[code] else {
            return Unmanaged.passUnretained(event)
        }

        // Автоповтор удерживаемой кнопки: своё событие, но действие не выполняем.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        let isDown = (type == .keyDown)
        return handler(button, isDown) ? nil : Unmanaged.passUnretained(event)
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}

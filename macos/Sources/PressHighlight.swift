import Combine
import Foundation

/// Состояние нажатий для окна настроек.
///
/// Пока окно настроек открыто, приложение **не выполняет** действия: кнопки
/// только подсвечиваются, чтобы можно было спокойно назначать привязки и видеть,
/// какая кнопка чему соответствует.
final class PressHighlight: ObservableObject {
    static let shared = PressHighlight()

    /// Кнопка, которая нажата прямо сейчас (для подсветки плитки).
    @Published private(set) var pressed: Int?

    /// Последняя нажатая кнопка (чтобы было видно, что нажатие вообще дошло).
    @Published private(set) var last: Int?

    private init() {}

    func press(_ index: Int) {
        pressed = index
        last = index
    }

    func release(_ index: Int) {
        if pressed == index { pressed = nil }
    }

    func clear() {
        pressed = nil
        last = nil
    }
}

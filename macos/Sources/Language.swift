import Foundation

/// Язык интерфейса. Порядок везде: русский, китайский, английский.
enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, zh, en

    var id: String { rawValue }

    /// Название на самом этом языке.
    var title: String {
        switch self {
        case .ru: return "Русский"
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

/// Текущий язык. Живёт в UserDefaults, экраны читают его и перерисовываются.
final class Lang: ObservableObject {
    static let shared = Lang()
    static let changed = Notification.Name("keydeck.language")

    private static let storageKey = "keydeck.language"

    @Published var current: AppLanguage {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.storageKey)
            NotificationCenter.default.post(name: Self.changed, object: current)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.ru.rawValue
        current = AppLanguage(rawValue: raw) ?? .ru
    }

    func t(_ ru: String, _ zh: String, _ en: String) -> String {
        switch current {
        case .ru: return ru
        case .zh: return zh
        case .en: return en
        }
    }
}

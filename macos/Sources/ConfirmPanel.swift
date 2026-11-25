import AppKit
import SwiftUI

/// Состояние карточки подтверждения. Живёт между показами, чтобы при отсчёте
/// секунд не пересоздавать SwiftUI-иерархию (иначе карточка дёргалась бы).
final class ConfirmState: ObservableObject {
    @Published var buttonIndex = 0
    @Published var preview = ConfirmPreview.empty
    @Published var secondsLeft = 0
}

/// Карточка подтверждения: всплывает поверх других окон, но НЕ забирает фокус —
/// подтверждать надо кнопкой keydeck, а не мышью, чтобы не переключать окна.
final class ConfirmPanel {
    private var panel: NSPanel?
    private let state = ConfirmState()
    private var hosting: NSHostingView<ConfirmCard>?
    private var onCancelHandler: (() -> Void)?

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // Показывать и поверх полноэкранных приложений, и на всех пространствах.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    func show(buttonIndex: Int,
              preview: ConfirmPreview,
              secondsLeft: Int,
              onCancel: @escaping () -> Void) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        onCancelHandler = onCancel

        if hosting == nil {
            let view = ConfirmCard(state: state) { [weak self] in self?.onCancelHandler?() }
            let hosting = NSHostingView(rootView: view)
            self.hosting = hosting
            panel.contentView = hosting
        }

        state.buttonIndex = buttonIndex
        state.preview = preview
        state.secondsLeft = secondsLeft

        // Высоту берём из содержимого: команда под подписью бывает длинной.
        hosting?.layoutSubtreeIfNeeded()
        let fitting = hosting?.fittingSize ?? NSSize(width: 560, height: 200)
        let size = NSSize(width: 560, height: max(150, fitting.height))
        panel.setContentSize(size)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                         y: visible.maxY - size.height - 40))
        } else {
            panel.center()
        }
        // orderFrontRegardless: показать, не активируя приложение и не забирая фокус.
        panel.orderFrontRegardless()
    }

    /// Обновляет только число в отсчёте, не перестраивая карточку.
    func updateSecondsLeft(_ value: Int) {
        state.secondsLeft = value
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private struct ConfirmCard: View {
    @ObservedObject var state: ConfirmState
    @ObservedObject private var lang = Lang.shared
    let onCancel: () -> Void

    private func captionTitle(_ raw: String) -> String {
        switch raw {
        case "paste": return lang.t("вставит", "将粘贴", "will paste")
        case "type": return lang.t("напечатает", "将键入", "will type")
        case "command": return lang.t("команда", "命令", "command")
        default: return raw
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(lang.t("Подтверждение: кнопка \(state.buttonIndex + 1) (F\(13 + state.buttonIndex))",
                            "确认：按键 \(state.buttonIndex + 1)（F\(13 + state.buttonIndex)）",
                            "Confirm: button \(state.buttonIndex + 1) (F\(13 + state.buttonIndex))"))
                    .font(.headline)
                Spacer(minLength: 0)
                Button(lang.t("Отмена", "取消", "Cancel")) { onCancel() }
                    .controlSize(.small)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if state.preview.headlineIsVoice {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                }
                Text(state.preview.headline)
                    .font(.system(size: 26, weight: .semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let detail = state.preview.detail {
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = state.preview.detailCaption {
                        Text(captionTitle(caption))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if state.preview.press != nil || state.preview.voice != nil {
                HStack(alignment: .center, spacing: 12) {
                    if let key = state.preview.press {
                        Keycap(key: key)
                    }
                    if let voice = state.preview.voice {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.orange)
                            Text(voice)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 6) {
                Text(lang.t("Нажми ту же кнопку — выполнить. Любая другая — отмена.",
                            "再按同一键执行。按其他键取消。",
                            "Press the same button to run. Any other button cancels."))
                    .font(.footnote)
                Spacer(minLength: 0)
                if state.secondsLeft > 0 {
                    Text(lang.t("само отменится через \(state.secondsLeft) с",
                                "\(state.secondsLeft) 秒后自动取消",
                                "cancels in \(state.secondsLeft) s"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange, lineWidth: 2)
        )
        .padding(6)
    }
}

/// Клавиша, которую кнопка нажмёт после действия. Знак вместо фразы «затем нажмёт».
private struct Keycap: View {
    let key: KeydeckKey

    var body: some View {
        Text(key.glyph)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .frame(minWidth: 36, minHeight: 30)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
            )
            .help(key.title)
    }
}

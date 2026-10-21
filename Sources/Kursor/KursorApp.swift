import AppKit
import KursorCore
import SwiftUI

@main
struct KursorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            MenuBarLabel()
                .environmentObject(model)
        }

        Window("Kursor", id: WindowID.settings) {
            SettingsView()
                .environmentObject(model)
        }
        .defaultSize(width: 920, height: 700)
    }
}

enum WindowID {
    static let settings = "settings"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.bootstrap()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.shutdown()
        }
    }
}

/// The status-item label is rendered at launch, so it is the earliest place with access
/// to `openWindow` (used to show settings on first run or with `--settings`).
struct MenuBarLabel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.config.enabled && model.engineRunning ? "cursorarrow.rays" : "cursorarrow.slash")
            // Either order of "label rendered" and "request made" opens the window.
            .onAppear { if model.settingsRequest > 0 { showSettings() } }
            .onChange(of: model.settingsRequest) { showSettings() }
    }

    private func showSettings() {
        DispatchQueue.main.async {
            openWindow(id: WindowID.settings)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Kursor включён", isOn: $model.config.enabled)

        if let device = model.effectiveDevice {
            Text("Мышь: \(device.name)")
        }

        if !model.hasAccessibility {
            Button("⚠️ Нужен доступ «Универсальный доступ»…") { open(.general) }
        } else if !model.engineRunning {
            Text("⚠️ Перехват событий не запущен")
        }
        if model.linearMouseRunning {
            Button("⚠️ Закрыть LinearMouse (конфликтует)") { model.quitLinearMouse() }
        }

        Divider()
        Button("Настройки…") { open(nil) }
            .keyboardShortcut(",")
        Button("Диагностика кликов…") { open(.diagnostics) }
        Divider()
        Button("Выйти из Kursor") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open(_ page: SettingsPage?) {
        if let page { model.page = page }
        openWindow(id: WindowID.settings)
        NSApp.activate(ignoringOtherApps: true)
    }
}

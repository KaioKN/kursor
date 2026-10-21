import AppKit
import KursorCore
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, devices
    case click, pointer, scroll, buttons
    case zoom, focus
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Общие"
        case .devices: return "Устройства"
        case .click: return "Клик"
        case .pointer: return "Указатель"
        case .scroll: return "Скролл"
        case .buttons: return "Кнопки и жесты"
        case .zoom: return "Зум и поворот"
        case .focus: return "Окна и фокус"
        case .diagnostics: return "Диагностика кликов"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .devices: return "computermouse.fill"
        case .click: return "cursorarrow.click.2"
        case .pointer: return "cursorarrow.motionlines"
        case .scroll: return "arrow.up.and.down"
        case .buttons: return "hand.point.up.left.fill"
        case .zoom: return "plus.magnifyingglass"
        case .focus: return "macwindow.on.rectangle"
        case .diagnostics: return "waveform.path.ecg"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .devices: return .indigo
        case .click: return .blue
        case .pointer: return .teal
        case .scroll: return .green
        case .buttons: return .orange
        case .zoom: return .purple
        case .focus: return .pink
        case .diagnostics: return .red
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsPage?>(
                get: { model.page },
                set: { if let page = $0 { model.page = page } }
            )) {
                Section {
                    row(.general)
                    row(.devices)
                }
                Section("Профиль «\(model.selectedProfile.wrappedValue.name)»") {
                    row(.click)
                    row(.pointer)
                    row(.scroll)
                    row(.buttons)
                }
                Section("Для всех устройств") {
                    row(.zoom)
                    row(.focus)
                }
                Section("Инструменты") {
                    row(.diagnostics)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail(model.page)
                .navigationTitle(model.page.title)
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    private func row(_ page: SettingsPage) -> some View {
        Label {
            Text(page.title)
        } icon: {
            Image(systemName: page.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(page.color.gradient, in: RoundedRectangle(cornerRadius: 6))
        }
        .tag(page)
    }

    @ViewBuilder
    private func detail(_ page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralPage()
        case .devices: DevicesPage()
        case .click: ClickPage()
        case .pointer: PointerPage()
        case .scroll: ScrollPage()
        case .buttons: ButtonsPage()
        case .zoom: ZoomPage()
        case .focus: FocusPage()
        case .diagnostics: DiagnosticsView()
        }
    }
}

// MARK: - General

struct GeneralPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Kursor включён", isOn: $model.config.enabled)
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }
                ))
            }

            if model.offerLinearMouseImport {
                Section("Найден LinearMouse") {
                    Hint("Перенести скорость указателя, скролл и действия кнопок для всех ваших мышей?")
                    HStack {
                        Button("Импортировать") { model.importLinearMouse() }
                            .buttonStyle(.borderedProminent)
                        Button("Не надо") { model.offerLinearMouseImport = false }
                    }
                }
            }

            if model.linearMouseRunning {
                Section {
                    Label("LinearMouse запущен и перехватывает те же события", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Закрыть LinearMouse") { model.quitLinearMouse() }
                    Hint("Уберите его и из автозапуска: Системные настройки → Основные → Объекты входа.")
                }
            }

            Section("Разрешения") {
                PermissionRow(
                    title: "Универсальный доступ",
                    detail: "Обязательно: перехват кликов и колеса",
                    granted: model.hasAccessibility,
                    action: model.openAccessibilitySettings
                )
                PermissionRow(
                    title: "Мониторинг ввода",
                    detail: "Чтобы знать, какая мышь активна (профили по устройствам)",
                    granted: model.hasInputMonitoring,
                    action: model.openInputMonitoringSettings
                )
                LabeledContent("Перехват событий") {
                    Text(model.engineRunning ? "работает" : "не запущен")
                        .foregroundStyle(model.engineRunning ? .green : .orange)
                }
            }

            Section("Файлы") {
                Button("Показать config.json в Finder") { model.revealConfig() }
                if let message = model.importMessage {
                    Hint(message)
                }
            }

            Section("Совет") {
                Hint("Игровые мыши с высоким DPI сильнее «дрожат» при клике. Если в утилите производителя мыши выставить 800–1600 DPI и добавить скорость во вкладке «Указатель», клики станут стабильнее даже без Kursor.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Click

struct ClickPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let p = model.selectedProfile
        Form {
            ProfileSection()

            Section("Точность клика") {
                Toggle("Стабилизация клика", isOn: p.click.stabilize)
                Hint("Пока кнопка зажата, мелкие сдвиги мыши игнорируются: клик не превращается в перетаскивание. Если сдвинуть дальше допуска или держать дольше окна, перетаскивание работает как обычно.")
                if p.wrappedValue.click.stabilize {
                    SliderRow("Допуск сдвига", value: p.click.radius, in: 1...15, step: 0.5, format: "%.1f px")
                    SliderRow("Окно времени", value: p.click.maxDurationMs, in: 50...500, step: 10, format: "%.0f мс")
                    LabeledContent("Кнопки") {
                        HStack {
                            Toggle("Левая", isOn: p.click.buttons.contains(0))
                            Toggle("Правая", isOn: p.click.buttons.contains(1))
                            Toggle("Средняя", isOn: p.click.buttons.contains(2))
                        }
                    }
                    Toggle("Держать курсор на месте (экспериментально)", isOn: p.click.freezeCursor)
                }
            }

            Section("Надёжность") {
                Toggle("Фильтр дребезга кнопок", isOn: p.click.debounce)
                if p.wrappedValue.click.debounce {
                    SliderRow("Окно дребезга", value: p.click.debounceMs, in: 5...80, step: 1, format: "%.0f мс")
                    Hint("Нажатие, пришедшее быстрее этого после отпускания, считается дребезгом свитча.")
                }
                Toggle("Отпускать «залипшие» кнопки", isOn: p.click.stuckGuard)
                Hint("Если система считает кнопку зажатой, а мышь говорит, что она отпущена, Kursor досылает отпускание.")
            }

            Section {
                Button("Открыть диагностику кликов") { model.page = .diagnostics }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pointer

struct PointerPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let p = model.selectedProfile
        Form {
            ProfileSection()

            Section("Скорость и ускорение") {
                Picker("Режим", selection: p.pointer.mode) {
                    ForEach(PointerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                switch p.wrappedValue.pointer.mode {
                case .system:
                    Hint("Скорость берётся из Системных настроек → Мышь.")
                case .custom:
                    SliderRow("Скорость", value: p.pointer.speed, in: 0...1, format: "%.3f")
                    SliderRow("Ускорение", value: p.pointer.acceleration, in: 0...3, format: "%.2f")
                    Hint("0 = почти без ускорения, 0.69 = как в macOS по умолчанию.")
                case .linear:
                    SliderRow("Скорость", value: p.pointer.speed, in: 0...1, format: "%.3f")
                    Hint("Курсор движется ровно пропорционально руке.")
                }
            }

            Section("Снайперский режим") {
                SliderRow("Замедление", value: p.pointer.precisionFactor, in: 1.5...8, step: 0.5, format: "×%.1f")
                Hint("Назначьте «Снайперский режим» на кнопку во вкладке «Кнопки»: пока она зажата, курсор движется медленнее.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scroll

struct ScrollPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let p = model.selectedProfile
        Form {
            ProfileSection()

            Section("Колесо") {
                Toggle("Плавный скролл с инерцией", isOn: p.scroll.smooth)
                if p.wrappedValue.scroll.smooth {
                    SliderRow("Скорость", value: p.scroll.speed, in: 10...160, step: 1, format: "%.0f px")
                    SliderRow("Ускорение", value: p.scroll.acceleration, in: 0...3, format: "%.2f")
                    SliderRow("Инерция", value: p.scroll.inertiaMs, in: 30...300, step: 5, format: "%.0f мс")
                    Hint("Скорость — пикселей на один щелчок колеса. Ускорение добавляет дистанцию при быстрой прокрутке.")
                }
            }

            Section("Направление") {
                Toggle("Обратить вертикальный скролл", isOn: p.scroll.reverseVertical)
                Toggle("Обратить горизонтальный скролл", isOn: p.scroll.reverseHorizontal)
                Hint("Задаётся отдельно для каждого профиля: у трекпада может остаться «естественное» направление, а у мыши — обычное.")
            }

            Section("Средняя кнопка") {
                Picker("Режим", selection: p.scroll.middleButton) {
                    ForEach(MiddleButtonMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if p.wrappedValue.scroll.middleButton == .pan {
                    SliderRow("Скорость прокрутки", value: p.scroll.panSpeed, in: 0.5...4, step: 0.1, format: "×%.1f")
                    Hint("Короткое нажатие без движения остаётся обычным средним кликом (открыть ссылку во вкладке).")
                }
                if p.wrappedValue.scroll.middleButton == .autoscroll {
                    Hint("Средний клик включает автоскролл: чем дальше курсор от точки клика, тем быстрее прокрутка. Любой клик выключает.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Zoom

struct ZoomPage: View {
    @EnvironmentObject private var model: AppModel
    @State private var countdown: String?

    var body: some View {
        Form {
            Section("Зум как щипок на тачпаде") {
                Toggle("Включить", isOn: $model.config.zoom.enabled)
                ModifierPicker(title: "Модификатор + колесо", modifiers: $model.config.zoom.modifiers)
                SliderRow("Чувствительность", value: $model.config.zoom.sensitivity, in: 0.25...3, format: "×%.2f")
                Toggle("Обратное направление", isOn: $model.config.zoom.invert)
                Hint("Приложения получают настоящий жест «щипок»: Safari, Chrome, Preview, Фото, Карты, Figma зумят плавно, как с трекпада.")
            }

            Section("Приложения без поддержки щипка") {
                Hint("Для них Kursor нажимает ⌘= / ⌘− вместо жеста.")
                ForEach(model.config.zoom.keyFallbackApps, id: \.self) { bundleID in
                    HStack {
                        Text(Self.appName(bundleID))
                        Spacer()
                        Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        Button {
                            model.config.zoom.keyFallbackApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Добавить приложение…") { addFallbackApp() }
            }

            Section("Поворот") {
                Toggle("Модификатор + колесо → поворот", isOn: $model.config.rotate.enabled)
                ModifierPicker(title: "Модификатор", modifiers: $model.config.rotate.modifiers)
                SliderRow("Градусов за щелчок", value: $model.config.rotate.degreesPerLine, in: 1...15, step: 0.5, format: "%.1f°")
            }

            Section("Проверка") {
                Hint("Нажмите кнопку и за 2 секунды наведите курсор на окно Safari, Preview или Карт.")
                HStack {
                    Button("Щипок +") { delayed { model.engine.testPinch(zoomIn: true) } }
                    Button("Щипок −") { delayed { model.engine.testPinch(zoomIn: false) } }
                    Button("Smart zoom") { delayed { model.engine.testSmartZoom() } }
                    Button("Рабочий стол →") { delayed { model.engine.testSpaceSwitch(right: true) } }
                }
                if let countdown { Text(countdown).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private func delayed(_ action: @escaping () -> Void) {
        countdown = "Через 2 секунды…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            action()
            countdown = nil
        }
    }

    private func addFallbackApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !model.config.zoom.keyFallbackApps.contains(id) {
                model.config.zoom.keyFallbackApps.append(id)
            }
        }
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

// MARK: - Buttons

struct ButtonsPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let p = model.selectedProfile
        Form {
            ProfileSection()

            Section("Действия кнопок") {
                ForEach([2, 3, 4, 5, 6], id: \.self) { button in
                    Picker(buttonTitle(button), selection: Binding(
                        get: { p.wrappedValue.buttons.action(for: button) },
                        set: { p.wrappedValue.buttons.setAction($0, for: button) }
                    )) {
                        ForEach(ButtonAction.forButtons, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Hint("«Обычное поведение» передаёт кнопку приложениям как есть (Chrome и Finder понимают боковые кнопки сами). Для средней кнопки при этом работает режим из вкладки «Скролл».")
            }

            if p.wrappedValue.buttons.mappings.contains(where: { $0.action == .gesture }) {
                Section("Кнопка-жест") {
                    SliderRow("Порог движения", value: p.buttons.gesture.threshold, in: 20...200, step: 5, format: "%.0f px")
                    directionPicker("← Влево", p.buttons.gesture.left)
                    directionPicker("→ Вправо", p.buttons.gesture.right)
                    directionPicker("↑ Вверх", p.buttons.gesture.up)
                    directionPicker("↓ Вниз", p.buttons.gesture.down)
                    Picker("Нажатие без движения", selection: p.buttons.gesture.click) {
                        ForEach(ButtonAction.directional, id: \.self) { action in
                            Text(action == .none ? "Обычный клик этой кнопки" : action.title).tag(action)
                        }
                    }
                    Hint("Удерживайте кнопку и ведите мышь. Влево/вправо можно повторять, не отпуская кнопку, чтобы пролистать несколько рабочих столов.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func directionPicker(_ title: String, _ binding: Binding<ButtonAction>) -> some View {
        Picker(title, selection: binding) {
            ForEach(ButtonAction.directional, id: \.self) { Text($0 == .none ? "Ничего" : $0.title).tag($0) }
        }
    }
}

// MARK: - Focus

struct FocusPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Активировать окно под курсором") {
                Picker("Когда", selection: $model.config.focus.mode) {
                    ForEach(FocusMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                switch model.config.focus.mode {
                case .off:
                    Hint("Как в macOS по умолчанию: первый клик по неактивному окну только активирует его.")
                case .displayChange:
                    Hint("Перевели курсор на другой монитор и остановились — окно под курсором становится активным, первый клик сразу срабатывает.")
                case .always:
                    Hint("Окно под курсором активируется везде, как только курсор остановится над ним. Удобно, но окна будут подниматься при каждом наведении.")
                }
                if model.config.focus.mode != .off {
                    SliderRow("Задержка", value: $model.config.focus.delayMs, in: 0...600, step: 10, format: "%.0f мс")
                    Hint("Сколько курсор должен постоять на месте. Меньше — быстрее, но выше шанс активировать окно, над которым курсор только пролетал.")
                }
            }

            Section("Когда не срабатывает") {
                Hint("Во время перетаскивания (окна между мониторами переносятся как обычно), над строкой меню, Dock, открытыми меню и всплывающими окнами, в Mission Control, а также над рабочим столом без окон.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Devices

struct DevicesPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Подключённые устройства") {
                if model.devices.isEmpty {
                    Hint(model.engineRunning ? "Устройства не найдены." : "Список появится после запуска перехвата событий.")
                }
                ForEach(model.devices) { device in
                    HStack {
                        Image(systemName: device.category == .trackpad ? "rectangle.and.hand.point.up.left" : "computermouse")
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(device.name)
                                if device == model.effectiveDevice {
                                    Text("активна").font(.caption).padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(.green.opacity(0.2), in: Capsule())
                                }
                            }
                            Text("\(device.idString) · \(device.transport) · профиль «\(model.profile(for: device).name)»")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.category == .mouse, !model.hasOwnProfile(device) {
                            Button("Свой профиль") { model.createProfile(for: device) }
                        }
                    }
                }
                if !model.hasInputMonitoring {
                    Hint("Без «Мониторинга ввода» Kursor не видит, какая мышь активна, и применяет профиль по умолчанию (или профиль единственной подключённой мыши).")
                }
            }

            Section("Профили") {
                ForEach(model.config.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                            Text(Self.describe(profile.match)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Настроить") { model.selectedProfileID = profile.id }
                            .controlSize(.small)
                        if profile.id != "default", profile.id != "trackpad" {
                            Button(role: .destructive) { model.deleteProfile(id: profile.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                if let index = model.config.profiles.firstIndex(where: { $0.id == model.selectedProfileID }) {
                    TextField("Название выбранного профиля", text: $model.config.profiles[index].name)
                }
            }

            Section("LinearMouse") {
                Button("Импортировать настройки из LinearMouse") { model.importLinearMouse() }
                if let message = model.importMessage { Hint(message) }
            }
        }
        .formStyle(.grouped)
    }

    static func describe(_ match: DeviceMatch?) -> String {
        guard let match else { return "все остальные мыши" }
        if let v = match.vendorID, let p = match.productID { return String(format: "устройство %04X:%04X", v, p) }
        if match.category == .trackpad { return "трекпады" }
        return "—"
    }
}

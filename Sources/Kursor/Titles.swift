import KursorCore

extension ButtonAction {
    var title: String {
        switch self {
        case .none: return "Обычное поведение"
        case .back: return "Назад (⌘[)"
        case .forward: return "Вперёд (⌘])"
        case .spaceLeft: return "Рабочий стол слева"
        case .spaceRight: return "Рабочий стол справа"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Показать рабочий стол"
        case .launchpad: return "Launchpad / Приложения"
        case .smartZoom: return "Smart zoom (двойной тап)"
        case .precision: return "Снайперский режим (удерживать)"
        case .nextDisplay: return "Курсор на следующий монитор"
        case .gesture: return "Кнопка-жест (удерживать и вести)"
        case .middleClick: return "Средний клик"
        }
    }

    /// Actions offered for a mouse button (left/right are never remapped).
    static let forButtons: [ButtonAction] = [
        .none, .gesture, .back, .forward, .spaceLeft, .spaceRight, .missionControl, .appExpose,
        .showDesktop, .launchpad, .smartZoom, .precision, .nextDisplay, .middleClick,
    ]
}

extension PointerMode {
    var title: String {
        switch self {
        case .system: return "Как в macOS"
        case .custom: return "Своя скорость"
        case .linear: return "Без ускорения"
        }
    }
}

extension MiddleButtonMode {
    var title: String {
        switch self {
        case .normal: return "Обычный средний клик"
        case .pan: return "Зажать и тянуть — прокрутка"
        case .autoscroll: return "Автоскролл (как в Windows)"
        }
    }
}

extension ClickStabilizer.Outcome {
    var title: String {
        switch self {
        case .clean: return "Чистый клик"
        case .stabilized: return "Спасён"
        case .drag: return "Перетаскивание"
        case .microDrag: return "Микро-драг"
        }
    }
}

func buttonTitle(_ button: ButtonNumber) -> String {
    switch button {
    case 0: return "Левая"
    case 1: return "Правая"
    case 2: return "Средняя (колесо)"
    case 3: return "Боковая «назад» (4)"
    case 4: return "Боковая «вперёд» (5)"
    default: return "Кнопка \(button + 1)"
    }
}

extension DeviceInfo {
    var idString: String { String(format: "%04X:%04X", vendorID, productID) }
}

extension FocusMode {
    var title: String {
        switch self {
        case .off: return "Никогда"
        case .displayChange: return "При переходе на другой монитор"
        case .always: return "Всегда (фокус следует за курсором)"
        }
    }
}

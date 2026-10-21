import AppKit
import Combine
import KursorCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let engine = KursorEngine.shared
    private let store = ConfigStore()

    @Published var config = KursorConfig() {
        didSet {
            guard config != oldValue, loaded else { return }
            engine.update(config: config)
            scheduleSave()
        }
    }

    @Published private(set) var devices: [DeviceInfo] = [] {
        didSet { followEffectiveDevice() }
    }
    @Published private(set) var activeDevice: DeviceInfo? {
        didSet { followEffectiveDevice() }
    }
    private var followedDeviceID: String?

    /// The mouse in use: the one that sent input last, or the only connected mouse.
    var effectiveDevice: DeviceInfo? { activeDevice ?? devices.soleMouse }
    @Published private(set) var hasAccessibility = false
    @Published private(set) var hasInputMonitoring = false
    @Published private(set) var engineRunning = false
    @Published private(set) var linearMouseRunning = false
    @Published var selectedProfileID = "default"
    @Published var importMessage: String?
    @Published var offerLinearMouseImport = false
    /// Incremented to ask the menu bar label (which has `openWindow`) to show settings.
    @Published private(set) var settingsRequest = 0
    @Published var page = SettingsPage(rawValue: UserDefaults.standard.string(forKey: "settingsPage") ?? "") ?? .general {
        didSet { UserDefaults.standard.set(page.rawValue, forKey: "settingsPage") }
    }

    private var loaded = false
    private var saveWork: DispatchWorkItem?
    private var pollTimer: Timer?

    // MARK: - Lifecycle

    func bootstrap() {
        let firstRun = !store.exists
        config = store.load()
        loaded = true
        followEffectiveDevice()
        offerLinearMouseImport = firstRun && FileManager.default.fileExists(atPath: LinearMouseImporter.defaultURL.path)

        engine.onDevicesChanged = { [weak self] list in self?.devices = list }
        engine.onActiveDeviceChanged = { [weak self] info in self?.activeDevice = info }

        refreshStatus()
        startEngineIfPossible()
        if !hasAccessibility {
            KursorEngine.promptAccessibility()
            page = .general
        }
        if !hasAccessibility || CommandLine.arguments.contains("--settings") {
            settingsRequest += 1
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func shutdown() {
        saveNow()
        engine.stop()
    }

    private func poll() {
        let hadInput = hasInputMonitoring
        refreshStatus()
        if !engineRunning { startEngineIfPossible() }
        if hasInputMonitoring, !hadInput { engine.restartDeviceMonitor() }
    }

    private func refreshStatus() {
        hasAccessibility = KursorEngine.hasAccessibility
        hasInputMonitoring = KursorEngine.hasInputMonitoring
        linearMouseRunning = !KursorEngine.linearMouseRunning.isEmpty
        engineRunning = engine.isRunning
    }

    private func startEngineIfPossible() {
        guard hasAccessibility, !engine.isRunning else { return }
        engineRunning = engine.start(config: config)
        devices = engine.devices
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        try? store.save(config)
    }

    func revealConfig() {
        saveNow()
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    // MARK: - Profiles

    var selectedProfileIndex: Int {
        config.profiles.firstIndex { $0.id == selectedProfileID } ?? 0
    }

    var selectedProfile: Binding<DeviceProfile> {
        Binding(
            get: { self.config.profiles[self.selectedProfileIndex] },
            set: { self.config.profiles[self.selectedProfileIndex] = $0 }
        )
    }

    /// Profile pages edit the profile of the mouse in use; follow it when the mouse changes
    /// (a manual pick stays until another mouse becomes active).
    private func followEffectiveDevice() {
        guard loaded, let device = effectiveDevice, device.id != followedDeviceID else { return }
        followedDeviceID = device.id
        selectedProfileID = config.profile(for: device).id
    }

    func profile(for device: DeviceInfo) -> DeviceProfile {
        config.profile(for: device)
    }

    func hasOwnProfile(_ device: DeviceInfo) -> Bool {
        config.profiles.contains { $0.match?.vendorID == device.vendorID && $0.match?.productID == device.productID }
    }

    /// Creates a device profile starting from the settings it currently uses.
    func createProfile(for device: DeviceInfo) {
        var profile = config.profile(for: device)
        profile.id = UUID().uuidString
        profile.name = device.name
        profile.match = DeviceMatch(vendorID: device.vendorID, productID: device.productID, name: device.name)
        config.profiles.append(profile)
        selectedProfileID = profile.id
    }

    func deleteProfile(id: String) {
        guard id != "default" else { return }
        config.profiles.removeAll { $0.id == id }
        if selectedProfileID == id { selectedProfileID = "default" }
    }

    // MARK: - LinearMouse

    func importLinearMouse() {
        do {
            let result = try LinearMouseImporter.importConfig(into: config)
            config = result.config
            importMessage = "Импортировано: " + (result.importedDevices.isEmpty ? "ничего" : result.importedDevices.joined(separator: ", "))
            if let device = effectiveDevice {
                selectedProfileID = config.profile(for: device).id
            }
        } catch {
            importMessage = "Не удалось прочитать конфиг LinearMouse"
        }
        offerLinearMouseImport = false
    }

    func quitLinearMouse() {
        KursorEngine.linearMouseRunning.forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshStatus() }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    // MARK: - Permissions

    func openAccessibilitySettings() {
        KursorEngine.promptAccessibility()
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        KursorEngine.requestInputMonitoring()
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

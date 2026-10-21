import KursorCore
import SwiftUI

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil, format: String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
                Text(String(format: format, value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)
            }
        }
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Picker of the profile edited by the per-device tabs.
struct ProfileSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            Picker("Профиль", selection: $model.selectedProfileID) {
                ForEach(model.config.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            if let device = model.effectiveDevice {
                let applied = model.profile(for: device)
                if applied.id == model.selectedProfileID {
                    Label("Действует на «\(device.name)» — мышь, которой вы сейчас пользуетесь", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Эти настройки не действуют на «\(device.name)»: для неё используется профиль «\(applied.name)».", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Перейти к профилю «\(applied.name)»") {
                            model.selectedProfileID = applied.id
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

struct ModifierPicker: View {
    let title: String
    @Binding var modifiers: Modifiers

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                toggle("⌃", .control)
                toggle("⌥", .option)
                toggle("⇧", .shift)
                toggle("⌘", .command)
            }
        }
    }

    private func toggle(_ symbol: String, _ flag: Modifiers) -> some View {
        Toggle(symbol, isOn: Binding(
            get: { modifiers.contains(flag) },
            set: { on in
                if on { modifiers.insert(flag) } else { modifiers.remove(flag) }
            }
        ))
        .toggleStyle(.button)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Открыть настройки", action: action)
            }
        }
    }
}

extension Binding where Value == [ButtonNumber] {
    func contains(_ button: ButtonNumber) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.contains(button) },
            set: { on in
                var list = wrappedValue.filter { $0 != button }
                if on { list.append(button) }
                wrappedValue = list.sorted()
            }
        )
    }
}

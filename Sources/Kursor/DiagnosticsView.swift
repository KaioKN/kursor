import KursorCore
import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var entries: [Diagnostics.ClickEntry] = []
    @State private var counters = Diagnostics.Counters()
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Кликайте как обычно — каждая строка показывает, насколько мышь сдвинулась между нажатием и отпусканием и что с этим сделал Kursor.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                stat("Кликов", entries.count)
                stat("Спасено", count(.stabilized), tint: .green)
                stat("Микро-драг без защиты", count(.microDrag), tint: .orange)
                stat("Перетаскиваний", count(.drag))
            }

            if let line = distanceSummary {
                Text(line).monospacedDigit()
            }

            if let radius = entries.suggestedRadius() {
                HStack {
                    Text("Рекомендуемый допуск сдвига: \(Int(radius)) px")
                    Button("Применить к профилю «\(model.selectedProfile.wrappedValue.name)»") {
                        model.selectedProfile.wrappedValue.click.radius = radius
                    }
                }
            }

            Table(entries.reversed()) {
                TableColumn("Время") { Text($0.date, format: .dateTime.hour().minute().second()) }
                    .width(70)
                TableColumn("Мышь") { Text($0.device).lineLimit(1) }
                TableColumn("Кнопка") { Text(buttonTitle($0.record.button)) }
                    .width(80)
                TableColumn("Нажатие") { Text("\(Int($0.record.duration * 1000)) мс").monospacedDigit() }
                    .width(70)
                TableColumn("Сдвиг") { Text(String(format: "%.1f px", $0.record.maxDistance)).monospacedDigit() }
                    .width(70)
                TableColumn("Drag-событий") { Text("\($0.record.dragEvents)").monospacedDigit() }
                    .width(90)
                TableColumn("Итог") { entry in
                    Text(entry.record.outcome.title)
                        .foregroundStyle(color(entry.record.outcome))
                }
                .width(110)
            }

            HStack(spacing: 16) {
                Text("Событий: \(counters.events)")
                Text("Перезапусков перехвата: \(counters.tapReenabled)")
                Text("Отпущено залипших: \(counters.stuckReleases)")
                Text("Дребезг: \(counters.bouncesFiltered)")
                Spacer()
                Button("Очистить") {
                    model.engine.diagnostics.clear()
                    refresh()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !counters.inputMonitoring {
                Text("«Мониторинг ввода» не выдан: колонка «Мышь» может быть пустой.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        let snapshot = model.engine.diagnostics.snapshot()
        if snapshot.entries != entries { entries = snapshot.entries }
        if snapshot.counters != counters { counters = snapshot.counters }
    }

    private func count(_ outcome: ClickStabilizer.Outcome) -> Int {
        entries.filter { $0.record.outcome == outcome }.count
    }

    private var distanceSummary: String? {
        let d = entries.filter { $0.record.outcome != .drag }.map(\.record.maxDistance).sorted()
        guard !d.isEmpty else { return nil }
        let median = d[d.count / 2]
        let p95 = d[min(d.count - 1, Int(Double(d.count) * 0.95))]
        let moved = d.filter { $0 > 0 }.count
        return String(format: "Сдвиг при клике: медиана %.1f px · p95 %.1f px · со сдвигом %d из %d", median, p95, moved, d.count)
    }

    private func stat(_ title: String, _ value: Int, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title2.monospacedDigit()).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 120, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func color(_ outcome: ClickStabilizer.Outcome) -> Color {
        switch outcome {
        case .clean: return .secondary
        case .stabilized: return .green
        case .microDrag: return .orange
        case .drag: return .blue
        }
    }
}

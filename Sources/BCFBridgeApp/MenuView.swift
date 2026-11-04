import AppKit
import BridgeCore
import BridgeEngine
import SwiftUI

struct StatusRow: View {
    let title: String
    let ok: Bool
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            Text(title).fontWeight(.medium)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var model: AppModel

    private var settings: BridgeSettings { model.status.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BCF Bridge").font(.headline)
                Spacer()
                Text("versie \(bridgeVersion)").font(.caption).foregroundStyle(.secondary)
            }

            if let err = model.startError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(err).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Button("Opnieuw proberen") { model.start() }
                }
            }

            VStack(spacing: 6) {
                StatusRow(title: "BCF2000", ok: model.bcfConnected,
                          detail: model.bcfConnected ? (model.status.bcfIn ?? "") : "niet gevonden")
                StatusRow(title: "Logic", ok: model.status.logicOnline,
                          detail: model.status.logicOnline ? "verbonden als Mackie Control" : "wacht op Logic")
            }

            Divider()

            if let prompt = model.status.learnPrompt {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Leren").font(.subheadline).fontWeight(.semibold)
                    Text(prompt).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Overslaan") { model.engine.learnSkip() }
                        Button("Stoppen") { model.engine.learnStop() }
                    }
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Bovenste knoprij")
                    Picker("", selection: Binding(get: { settings.topRowFunction }, set: { model.setTopRow($0) })) {
                        ForEach(ButtonFunction.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                GridRow {
                    Text("Onderste knoprij")
                    Picker("", selection: Binding(get: { settings.bottomRowFunction }, set: { model.setBottomRow($0) })) {
                        ForEach(ButtonFunction.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                GridRow {
                    Text("Fader loslaten na")
                    Stepper("\(settings.touchReleaseMs) ms",
                            value: Binding(get: { settings.touchReleaseMs }, set: { model.setReleaseMs($0) }),
                            in: 100...2000, step: 50)
                }
            }

            if let saved = model.savedMessage {
                Label(saved, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Alles leren") { model.engine.learnAll() }
                    .disabled(model.status.learnPrompt != nil)
                Button("Exporteren") { model.exportMapping() }
                Button("Importeren") { model.importMapping() }
            }
            HStack {
                Button("Mapping bekijken") { model.showMappingWindow() }
                Button("Standaardmapping herstellen") { model.confirmReset() }
            }

            Toggle("Starten bij inloggen", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))

            Divider()

            HStack {
                Button("Log tonen") { model.showLogWindow() }
                Spacer()
                Button("BCF Bridge afsluiten") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

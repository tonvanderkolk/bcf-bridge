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
                Text(tr("version", "versie") + " \(bridgeVersion)").font(.caption).foregroundStyle(.secondary)
            }

            if let err = model.startError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(err).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Button(tr("Try again", "Opnieuw proberen")) { model.start() }
                }
            }

            VStack(spacing: 6) {
                StatusRow(title: "BCF2000", ok: model.bcfConnected,
                          detail: model.bcfConnected ? (model.status.bcfIn ?? "") : tr("not found", "niet gevonden"))
                StatusRow(title: "Logic", ok: model.status.logicOnline,
                          detail: model.status.logicOnline ? tr("connected as Mackie Control", "verbonden als Mackie Control") : tr("waiting for Logic", "wacht op Logic"))
            }

            Divider()

            if let prompt = model.status.learnPrompt {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Learning", "Leren")).font(.subheadline).fontWeight(.semibold)
                    Text(prompt).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(tr("Skip", "Overslaan")) { model.engine.learnSkip() }
                        Button(tr("Stop", "Stoppen")) { model.engine.learnStop() }
                    }
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text(tr("Top button row", "Bovenste knoprij"))
                    Picker("", selection: Binding(get: { settings.topRowFunction }, set: { model.setTopRow($0) })) {
                        ForEach(ButtonFunction.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                GridRow {
                    Text(tr("Bottom button row", "Onderste knoprij"))
                    Picker("", selection: Binding(get: { settings.bottomRowFunction }, set: { model.setBottomRow($0) })) {
                        ForEach(ButtonFunction.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                GridRow {
                    Text(tr("Release fader after", "Fader loslaten na"))
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
                Button(tr("Learn all", "Alles leren")) { model.engine.learnAll() }
                    .disabled(model.status.learnPrompt != nil)
                Button(tr("Export", "Exporteren")) { model.exportMapping() }
                Button(tr("Import", "Importeren")) { model.importMapping() }
            }
            HStack {
                Button(tr("Show mapping", "Mapping bekijken")) { model.showMappingWindow() }
                Button(tr("Reset to default", "Standaardmapping herstellen")) { model.confirmReset() }
            }

            Toggle(tr("Launch at login", "Starten bij inloggen"), isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Toggle(isOn: Binding(get: { settings.hideModelFromLogic }, set: { model.engine.setHideModelFromLogic($0) })) {
                Text(tr("Keep Logic from adding the BCF2000 as an extra control surface",
                        "Voorkom dat Logic de BCF2000 als extra control surface toevoegt"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button(tr("Show log", "Log tonen")) { model.showLogWindow() }
                Spacer()
                Button(tr("Quit BCF Bridge", "BCF Bridge afsluiten")) { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

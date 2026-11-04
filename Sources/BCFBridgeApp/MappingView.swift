import BridgeCore
import SwiftUI

/// Overzicht van alle koppelingen, met per element opnieuw leren of wissen.
struct MappingView: View {
    @EnvironmentObject var model: AppModel

    private var settings: BridgeSettings { model.status.settings }
    private var learning: Bool { model.status.learnPrompt != nil }

    private var sections: [(String, [LearnTarget])] {
        [
            ("Faders", (0..<8).map { .fader($0) }),
            (tr("Encoders turn (pan)", "Encoders draaien (panning)"), (0..<8).map { .encoder($0) }),
            (tr("Top button row", "Bovenste knoprij") + " (\(settings.topRowFunction.label))", (0..<8).map { .top($0) }),
            (tr("Bottom button row", "Onderste knoprij") + " (\(settings.bottomRowFunction.label))", (0..<8).map { .bottom($0) }),
            (tr("Bank and channel", "Bank en kanaal"), NavButton.allCases.map { .nav($0) }),
            (tr("Encoders push", "Encoders indrukken"), (0..<8).map { .push($0) }),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let prompt = model.status.learnPrompt {
                HStack(spacing: 10) {
                    Image(systemName: "hand.point.right.fill").foregroundStyle(Color.accentColor)
                    Text(prompt).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(tr("Stop", "Stoppen")) { model.engine.learnStop() }
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.12))
            } else {
                HStack {
                    Text(tr("Click Learn, then operate the element on the BCF2000.", "Klik op Leren en bedien daarna het element op de BCF2000."))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let saved = model.savedMessage {
                        Label(saved, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                }
                .padding(10)
            }
            Divider()
            List {
                ForEach(sections, id: \.0) { title, targets in
                    Section(title) {
                        ForEach(targets, id: \.self) { t in row(t) }
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    @ViewBuilder
    private func row(_ t: LearnTarget) -> some View {
        let m = settings.mapping(for: t)
        HStack {
            Text(name(t))
            Spacer()
            Text(m?.short ?? tr("not mapped", "niet gekoppeld"))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(m == nil ? .tertiary : .secondary)
            Button(tr("Learn", "Leren")) { model.engine.learn(t) }
                .disabled(learning)
            Button {
                model.engine.clearMapping(t)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(tr("Remove mapping", "Koppeling wissen"))
            .disabled(learning || m == nil)
        }
    }

    /// Korte naam binnen een sectie
    private func name(_ t: LearnTarget) -> String {
        switch t {
        case .fader(let i): return "Fader \(i + 1)"
        case .encoder(let i), .push(let i): return "Encoder \(i + 1)"
        case .top(let i), .bottom(let i): return tr("Button \(i + 1)", "Knop \(i + 1)")
        case .nav(let n): return n.label
        case .transport(let x): return x.label
        }
    }
}

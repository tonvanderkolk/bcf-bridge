import BridgeCore
import SwiftUI

struct LogView: View {
    @EnvironmentObject var model: AppModel
    @State private var autoScroll = true
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(tr("\(model.lines.count) lines (last 3000)", "\(model.lines.count) regels (laatste 3000)"))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(tr("Auto-scroll", "Automatisch scrollen"), isOn: $autoScroll)
                Button(copied ? tr("Copied", "Gekopieerd") : tr("Copy log", "Kopieer log")) {
                    model.copyLog()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                Button(tr("Show log file in Finder", "Logbestand in Finder")) { model.revealLogFile() }
            }
            .padding(10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.lines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.lines.last?.id) { id in
                    guard autoScroll, let id else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 300)
    }
}

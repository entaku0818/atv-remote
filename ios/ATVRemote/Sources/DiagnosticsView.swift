#if DEBUG
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject private var logStore = LogStore.shared
    @State private var logCopied = false

    var body: some View {
        DisclosureGroup("ログ（\(logStore.lines.count)）") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = logStore.allText
                        logCopied = true
                    } label: {
                        Label(logCopied ? "コピーしました" : "全部コピー", systemImage: logCopied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(logStore.lines.isEmpty)
                    ShareLink(item: logStore.allText) {
                        Label("共有", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button("クリア", role: .destructive) { logStore.clear() }
                }
                .font(.caption)
                ForEach(logStore.lines.reversed()) { line in
                    Text(line.text)
                        .font(.caption2.monospaced())
                        .foregroundStyle(line.entry.level == .error ? Color.red : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 8)
        }
        .font(.callout)
        .onChange(of: logStore.lines.count) { logCopied = false }
    }

}
#endif

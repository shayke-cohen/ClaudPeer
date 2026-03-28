import SwiftUI
import MarkdownUI
import WebKit

struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration
    @AppStorage(AppSettings.renderMermaidKey, store: AppSettings.store) private var renderMermaid = true
    @Environment(\.appTextScale) private var appTextScale
    @State private var isCopied = false
    @State private var showMermaidSource = false
    @State private var mermaidHeight: CGFloat = 150

    private var isMermaid: Bool {
        configuration.language?.lowercased() == "mermaid" && renderMermaid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)
            if isMermaid && !showMermaidSource {
                MermaidDiagramView(source: configuration.content, measuredHeight: $mermaidHeight)
                    .frame(height: min(mermaidHeight, 500))
            } else {
                codeContent
            }
        }
        .background(Color(.textBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            if let language = configuration.language, !language.isEmpty {
                Text(language)
                    .font(.system(size: 11 * appTextScale, weight: .medium))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.lowercase)
                    .xrayId("codeBlock.languageLabel")
            }

            Spacer()

            if isMermaid {
                Button {
                    showMermaidSource.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: showMermaidSource ? "wand.and.stars" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 11 * appTextScale))
                        Text(showMermaidSource ? "Diagram" : "Source")
                            .font(.system(size: 11 * appTextScale))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(showMermaidSource ? "Show diagram" : "Show source")
                .xrayId("codeBlock.mermaidToggle")
            }

            Button {
                copyToClipboard()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11 * appTextScale))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.system(size: 11 * appTextScale))
                }
                .foregroundStyle(isCopied ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Copy code to clipboard")
            .xrayId("codeBlock.copyButton")
            .accessibilityLabel("Copy code")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var codeContent: some View {
        let trimmed = configuration.content.trimmingCharacters(in: .whitespacesAndNewlines)
        HighlightedCodeView(
            code: trimmed,
            language: configuration.language,
            showLineNumbers: false
        )
        .frame(minHeight: 40, maxHeight: 400)
        .xrayId("codeBlock.codeScrollView")
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            configuration.content.trimmingCharacters(in: .whitespacesAndNewlines),
            forType: .string
        )
        withAnimation {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

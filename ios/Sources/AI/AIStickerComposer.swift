import SwiftUI

private enum StickerInputMode: String, CaseIterable, Identifiable {
    case artwork = "Artwork"
    case write = "AI text"
    case text = "Text"

    var id: String { rawValue }
}

struct AIStickerComposer: View {
    @StateObject private var client = OpenAIStickerClient()
    @AppStorage("s1-ai-prompt") private var prompt = ""
    @AppStorage("s1-input-mode") private var modeRaw = StickerInputMode.artwork.rawValue
    @State private var setup = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var preview: StickerAIResult?
    @State private var previewInput = ""
    @FocusState private var promptFocused: Bool
    let printerBusy: Bool
    let printerChoice: String
    let onBusyChange: (Bool) -> Void
    let onPrint: () -> Void
    let onResult: (StickerAIResult, Bool) -> Void

    private var mode: StickerInputMode { StickerInputMode(rawValue: modeRaw) ?? .artwork }
    private var inputID: String { printerChoice + "\n" + modeRaw + "\n" + prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasCurrentPreview: Bool { preview != nil && previewInput == inputID }
    private var canPrepare: Bool {
        (mode == .text || client.configured) && !client.busy && !printerBusy && task == nil &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var placeholder: String {
        switch mode {
        case .artwork: return "Describe your sticker…"
        case .write: return "What should the label say?"
        case .text: return "Type, dictate, or insert text…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text("Make a sticker").font(.title.bold())
                Spacer()
                Button { setup = true } label: {
                    Image(systemName: "gearshape").frame(width: 28, height: 28)
                }
                .stickerButtonStyle()
                .accessibilityLabel("AI settings")
                .disabled(client.busy)
            }
            Picker("Content", selection: $modeRaw) {
                ForEach(StickerInputMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .disabled(client.busy || printerBusy)

            VStack(alignment: .leading, spacing: 14) {
                TextField(placeholder, text: $prompt, axis: .vertical)
                    .font(.title3)
                    .lineLimit(3...7)
                    .focused($promptFocused)
                    .disabled(client.busy || printerBusy)
                Label("Use your keyboard to type or dictate", systemImage: "mic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))

            if mode == .text || client.configured {
                actionGroup
            } else {
                Button("Connect OpenAI") { setup = true }
                    .stickerButtonStyle(prominent: true)
            }
            if client.busy {
                HStack {
                    ProgressView()
                    Text(client.message)
                    Spacer()
                    Button("Cancel") { task?.cancel() }
                }
                .font(.subheadline)
            }
            if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
            Text(mode == .text ? "Prints your text as written. Raycast AI can format it in the keyboard." : "Generation uses your OpenAI API credits.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $setup) { OpenAISetupView(client: client) }
        .task { promptFocused = mode == .text || client.configured }
        .onChange(of: client.busy) { _, busy in onBusyChange(busy) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if promptFocused {
                    Button("Done") { promptFocused = false }
                    Spacer()
                    Button(hasCurrentPreview ? "Print sticker" : "Preview") { primaryAction() }
                        .bold().disabled(!canPrepare)
                }
            }
        }
    }

    @ViewBuilder private var actionGroup: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 14) { actionButtons }
        } else {
            actionButtons
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 14) {
            Button(action: primaryAction) {
                Label(hasCurrentPreview ? "Print sticker" : "Preview sticker",
                      systemImage: hasCurrentPreview ? "printer" : "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .stickerButtonStyle(prominent: true)
            Menu {
                Button("Print immediately", systemImage: "printer") { prepare(true) }
                if hasCurrentPreview {
                    Button(mode == .text ? "Refresh preview" : "Generate another preview", systemImage: "arrow.clockwise") { prepare(false) }
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 32, height: 36)
            }
            .stickerButtonStyle()
            .accessibilityLabel("More sticker actions")
        }
        .disabled(!canPrepare)
    }

    private func primaryAction() {
        guard canPrepare else { return }
        promptFocused = false
        if hasCurrentPreview { onPrint() } else { prepare(false) }
    }

    private func prepare(_ printNow: Bool) {
        guard canPrepare else { return }
        promptFocused = false
        error = nil
        if printNow, hasCurrentPreview { onPrint(); return }
        let requestInput = inputID
        let requestPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .text {
            let result = StickerAIResult.text(requestPrompt)
            preview = result
            previewInput = requestInput
            onResult(result, printNow)
            return
        }
        let requestKind: StickerAIKind = mode == .artwork ? .artwork : .text
        task = Task {
            do {
                let result = try await client.generate(requestPrompt, kind: requestKind, vretti: printerChoice == "Vretti")
                try Task.checkCancellation()
                preview = result
                previewInput = requestInput
                onResult(result, printNow)
            } catch is CancellationError {
                error = "Generation cancelled."
            } catch let failure as URLError where failure.code == .cancelled {
                error = "Generation cancelled."
            } catch {
                self.error = error.localizedDescription
            }
            task = nil
        }
    }
}

private struct OpenAISetupView: View {
    @ObservedObject var client: OpenAIStickerClient
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI API access") {
                    Text("Use a personal API key for the organization containing your API credits. The key is stored in this iPhone’s Keychain and sent only to OpenAI.")
                    SecureField("Paste personal API key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(client.busy ? "Checking…" : "Save and check access") {
                        Task {
                            do { try await client.connect(key); key = ""; dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(client.busy || key.isEmpty)
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section("Credits and usage") {
                    Link("Open API billing", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                    Link("Manage API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    Text("Generation uses API credits. Printing existing text and images uses the local renderer.").font(.footnote)
                }
                if client.configured {
                    Section {
                        Button("Remove API access from this iPhone", role: .destructive) { client.disconnect(); dismiss() }
                    }
                }
            }
            .navigationTitle("AI settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

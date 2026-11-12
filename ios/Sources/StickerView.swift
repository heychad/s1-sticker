import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor struct StickerView: View {
    @StateObject private var printer = S1Bluetooth()
    @StateObject private var document: StickerDocumentModel
    @State private var selected: PhotosPickerItem?
    @State private var chooseFile = false
    @State private var error: String?
    @State private var printWhenReady = false
    @State private var generating = false
    @State private var hasContent: Bool
    @State private var editingText = false
    @FocusState private var textFocused: Bool
    private var busy: Bool { printer.busy || generating || printWhenReady }

    init(text: String? = nil, image: UIImage? = nil) {
        _document = StateObject(wrappedValue: StickerDocumentModel(text: text ?? "", image: image))
        _hasContent = State(initialValue: text != nil || image != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    #if !SHARE_EXTENSION
                    AIStickerComposer(
                        printerBusy: printer.busy || printWhenReady || (hasContent && document.rendering),
                        onBusyChange: { generating = $0 },
                        onPrint: printCurrent
                    ) { result, printNow in
                        switch result {
                        case .image(let image): document.setImage(image)
                        case .text(let text): document.setText(text)
                        }
                        hasContent = true
                        editingText = false
                        printWhenReady = printNow
                    }
                    #endif
                    if let message = error ?? (hasContent ? document.error : nil) {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.red)
                    }
                    if hasContent { previewContent }
                }
                .padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("S1 Sticker")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        PhotosPicker(selection: $selected, matching: .images) {
                            Label("Photo", systemImage: "photo")
                        }
                        Button("File", systemImage: "doc") { chooseFile = true }
                        Button("Text editor", systemImage: "text.alignleft") {
                            document.useText()
                            hasContent = true
                            editingText = true
                            textFocused = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add photo, file, or text")
                    .disabled(busy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if hasContent { printBar }
            }
            .onReceive(document.$rendering) { rendering in
                guard !rendering, printWhenReady else { return }
                printWhenReady = false
                if document.error == nil { printCurrent() }
            }
            .onChange(of: selected) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = StickerImage.decode(data) {
                        document.setImage(image)
                        hasContent = true
                        editingText = false
                    }
                }
            }
            .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.image, .pdf, .plainText, .json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try load(url)
                } catch { self.error = error.localizedDescription }
            }
            .onOpenURL { url in
                do { try load(url) } catch { self.error = error.localizedDescription }
            }
        }
        .tint(Color(red: 0.12, green: 0.34, blue: 0.27))
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Preview").font(.headline)
                Spacer()
                if document.rendering { ProgressView().controlSize(.small) }
            }
            if let output = document.output {
                Image(uiImage: output.image)
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(maxWidth: 384)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Black-and-white print preview")
            }
            if document.image == nil {
                DisclosureGroup("Edit text", isExpanded: $editingText) {
                    TextEditor(text: $document.text)
                        .frame(minHeight: 140).padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                        .focused($textFocused).disabled(busy)
                }
            }
            DisclosureGroup("Print options") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Dither grayscale", isOn: $document.dither)
                    if document.image != nil {
                        Toggle("Auto rotate", isOn: $document.autoRotate)
                        Button("Rotate 90°", systemImage: "rotate.right") { document.rotate() }
                            .stickerButtonStyle()
                    }
                    Text("Direct Bluetooth · 48 mm wide · 10 mm finishing feed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            }
            .disabled(busy)
        }
    }

    private var printBar: some View {
        VStack(spacing: 8) {
            Text(printer.message).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                if let output = document.output {
                    Text("48 × \(Int(round(Double(output.height) / 8))) mm")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button(action: printCurrent) {
                    HStack {
                        if printer.busy { ProgressView() }
                        else { Image(systemName: "printer") }
                        Text(printer.busy ? "Printing…" : "Print sticker")
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .stickerButtonStyle(prominent: true)
                .disabled(busy || document.rendering || document.output == nil)
            }
            if printer.busy {
                Button("Cancel print", role: .destructive) { printer.cancel() }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.bar)
    }

    private func load(_ url: URL) throws {
        try document.load(url)
        error = nil
        hasContent = true
        editingText = false
    }

    private func printCurrent() {
        guard !busy, !document.rendering, let output = document.output else { return }
        textFocused = false
        error = nil
        printer.printRaster(output.raster)
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        TabView {
            PublishView().tabItem { Label("Publish", systemImage: "paperplane") }
            PagesView().tabItem { Label("Pages", systemImage: "list.bullet") }
        }
        .padding()
        .frame(minWidth: 540, minHeight: 600)
    }
}

// MARK: - Publish tab

struct PublishView: View {
    @Environment(Publisher.self) private var publisher
    @State private var isTargeted = false
    @State private var showImporter = false

    var body: some View {
        @Bindable var p = publisher
        VStack(alignment: .leading, spacing: 16) {
            if !p.isRepoValid {
                Label("Site folder not found. Set it in Settings (⌘,).", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(.red)
            }

            dropZone

            if p.file != nil {
                Form {
                    Picker("Category", selection: $p.category) {
                        ForEach(p.categories, id: \.self) { Text($0.capitalized).tag($0) }
                        Divider()
                        Text("New category…").tag(Publisher.newCategoryTag)
                    }
                    if p.category == Publisher.newCategoryTag {
                        TextField("New category", text: $p.newCategory, prompt: Text("e.g. science"))
                    }
                    TextField("File name", text: $p.name)
                    LabeledContent("Address") {
                        Text(p.targetURL?.absoluteString ?? "(no GitHub remote)")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .formStyle(.columns)

                VStack(alignment: .leading, spacing: 6) {
                    if p.replacesExisting {
                        Label("A page with this name already exists. It will be updated.",
                              systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                    }
                    ForEach(p.warnings, id: \.self) {
                        Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
                .font(.callout)

                Button {
                    Task { await publisher.publish() }
                } label: {
                    Text(p.replacesExisting ? "Update" : "Publish").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!p.canPublish)
            }

            Spacer(minLength: 0)
            StatusView()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.html]) { result in
            if case .success(let url) = result { publisher.file = url }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .background(RoundedRectangle(cornerRadius: 14).fill(isTargeted ? Color.accentColor.opacity(0.08) : .clear))
            .overlay {
                VStack(spacing: 6) {
                    if let file = publisher.file {
                        Image(systemName: "doc.richtext").font(.system(size: 30))
                        Text(publisher.fileTitle).font(.headline).multilineTextAlignment(.center)
                        Text(file.lastPathComponent).foregroundStyle(.secondary)
                        Text("Drop or click to choose a different file").font(.caption).foregroundStyle(.tertiary)
                    } else {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 30))
                        Text("Drop an HTML file here").font(.headline)
                        Text("or click to choose one").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .frame(height: 160)
            .contentShape(Rectangle())
            .onTapGesture { if !publisher.isBusy { showImporter = true } }
            .dropDestination(for: URL.self) { urls, _ in
                guard !publisher.isBusy, let url = urls.first else { return false }
                publisher.file = url
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

struct StatusView: View {
    @Environment(Publisher.self) private var publisher

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch publisher.phase {
            case .idle:
                EmptyView()
            case .publishing:
                HStack { ProgressView().controlSize(.small); Text("Uploading to GitHub…") }
            case .deploying:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Building the site (about a minute). The link is already copied.")
                }
            case .live:
                Label("Live! Link copied. Paste it in Telegram.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }

            if let url = publisher.publishedURL {
                HStack {
                    Link(url.absoluteString, destination: url).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Copy") { publisher.copy(url) }
                    Button("Open") { NSWorkspace.shared.open(url) }
                }
            }

            if !publisher.log.isEmpty {
                DisclosureGroup("Details") {
                    ScrollView {
                        Text(publisher.log)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
    }
}

// MARK: - Pages tab

struct PagesView: View {
    @Environment(Publisher.self) private var publisher

    var body: some View {
        VStack {
            List(publisher.pages) { page in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.title).lineLimit(1)
                        Text("\(page.path) · \(page.modified.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = publisher.url(for: page) {
                        Button { publisher.copy(url) } label: { Image(systemName: "doc.on.doc") }
                            .help("Copy link")
                        Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "safari") }
                            .help("Open in browser")
                    }
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 2)
            }
            .overlay {
                if publisher.pages.isEmpty {
                    ContentUnavailableView("No pages yet", systemImage: "doc")
                }
            }

            HStack {
                if let base = publisher.baseURL {
                    Button("Copy Index Link") { publisher.copy(base) }
                    Button("Open Index") { NSWorkspace.shared.open(base) }
                }
                Spacer()
                Button("Refresh") { publisher.refresh() }
            }
        }
        .onAppear { publisher.refresh() }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(Publisher.self) private var publisher

    var body: some View {
        Form {
            LabeledContent("Site folder") {
                HStack {
                    Text(publisher.repoPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button("Choose…", action: choose)
                }
            }
            if !publisher.isRepoValid {
                Text("This folder has no publish.sh.").foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 520)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: publisher.repoPath)
        if panel.runModal() == .OK, let url = panel.url {
            publisher.repoPath = url.path
        }
    }
}

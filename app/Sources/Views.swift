import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.screen {
            case .setup: SetupView()
            case .projects: ProjectsView()
            case .pickVideo: PickVideoView()
            case .direction: DirectionView()
            case .working: WorkingView()
            case .done(let url): DoneView(url: url)
            case .feedback(let url): FeedbackView(url: url)
            case .failed(let message): FailedView(message: message)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .sheet(isPresented: $model.showPrompt) { PromptSheet() }
        // The debug log is available on every screen, not just while working.
        .safeAreaInset(edge: .bottom) {
            if model.showDebug {
                VStack(spacing: 0) {
                    Divider()
                    DebugConsole(debug: model.debug)
                        .frame(height: 260)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let progress = model.setupProgress {
                Text(progress)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    model.viewSystemPrompt()
                } label: {
                    Label("System prompt", systemImage: "text.alignleft")
                }
                .help("Show the system prompt for the current project")
                .disabled(model.currentProject == nil)

                Toggle(isOn: $model.showDebug) {
                    Label("Debug", systemImage: "ladybug")
                }
                .toggleStyle(.button)
                .help("Show everything the app is doing")
            }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var showKeyField = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome")
                .font(.largeTitle.bold())

            if model.hasSubscriptionLogin {
                // The user is already signed into Claude Code.
                Label("Signed in to Claude\(model.subscriptionLabel.map { " \($0)" } ?? "")",
                      systemImage: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                Text("Your Claude subscription will design the graphics.")
                    .foregroundStyle(.secondary)
                Button("Continue") { model.continueWithSubscription() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else if model.signingIn {
                ProgressView()
                    .controlSize(.large)
                Text("Finish signing in in your browser")
                    .font(.title3)
                Text("A page opened in your browser. Sign in with your Claude account, then come back here.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
                Button("Cancel") { model.cancelSignIn() }
            } else {
                Text("Sign in with your Claude subscription to design your graphics.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
                Button("Sign in to Claude") { model.signInToClaude() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                if let error = model.signInError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("I've already signed in") { model.continueWithSubscription() }
                        .buttonStyle(.link)
                }

                Button(showKeyField ? "Hide API key option" : "Use an API key instead") {
                    showKeyField.toggle()
                }
                .buttonStyle(.link)

                if showKeyField {
                    SecureField("Paste your API key", text: $model.apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 380)
                        .onSubmit { model.saveAPIKey() }
                    Button("Save and continue") { model.saveAPIKey() }
                        .disabled(model.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(40)
    }
}

struct PickVideoView: View {
    @EnvironmentObject var model: AppModel
    @State private var dropActive = false

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button {
                    model.backToProjects()
                } label: {
                    Label("Projects", systemImage: "chevron.left")
                }
                .buttonStyle(.link)
                Spacer()
                if let name = model.currentProject?.name {
                    Text(name).font(.headline).foregroundStyle(.secondary)
                }
            }
            Text("Pick a video")
                .font(.largeTitle.bold())

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(dropActive ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(height: 180)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 34))
                        Text(model.localVideo?.lastPathComponent ?? "Drop a video file here")
                            .font(.title3)
                        Button("Or choose a file…") { chooseFile() }
                    }
                    .foregroundStyle(.secondary)
                }
                .onDrop(of: [.fileURL], isTargeted: $dropActive) { providers in
                    _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                        if let url {
                            DispatchQueue.main.async {
                                model.localVideo = url
                                model.videoURLText = ""
                                model.screen = .direction
                            }
                        }
                    }
                    return true
                }

            HStack {
                VStack { Divider() }
                Text("or").foregroundStyle(.secondary)
                VStack { Divider() }
            }
            .frame(maxWidth: 380)

            HStack {
                TextField("Paste a video link (YouTube and more)", text: $model.videoURLText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(continueWithURL)
                Button("Next") { continueWithURL() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.videoURLText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(maxWidth: 460)
        }
        .padding(40)
    }

    private func continueWithURL() {
        guard !model.videoURLText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.localVideo = nil
        model.screen = .direction
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.localVideo = url
            model.videoURLText = ""
            model.screen = .direction
        }
    }
}

struct DirectionView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            Text("Any special instructions?")
                .font(.largeTitle.bold())
            Text("Optional. Describe the style or anything you want, the way you would to a designer. For example: \"Bold captions, keep it minimal, brand color is teal.\" Leave it blank to let the agent decide.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $model.direction)
                .font(.title3)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 120)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3)))

            DictateButton { startDictation(focus: $editorFocused) }

            Text("How should it look?")
                .font(.title2.bold())
            HStack(spacing: 14) {
                ForEach(LayoutMode.allCases) { mode in
                    ModeCard(mode: mode, selected: model.mode == mode)
                        .onTapGesture { model.mode = mode }
                }
            }

            HStack {
                Button("Back") { model.screen = .pickVideo }
                Spacer()
                Button("Make my graphics") { model.start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(40)
        }
    }
}

// Focuses a text editor, then triggers macOS dictation on it. Dictation
// attaches to the first responder, so focus has to land first.
@MainActor
func startDictation(focus: FocusState<Bool>.Binding) {
    focus.wrappedValue = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
    }
}

// A "Dictate" button plus the keyboard hint, reused by any text screen.
struct DictateButton: View {
    var onStart: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onStart) {
                Label("Dictate", systemImage: "mic.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Text("or press the microphone key, or fn twice.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ModeCard: View {
    let mode: LayoutMode
    let selected: Bool

    var body: some View {
        VStack(spacing: 10) {
            diagram
                .frame(width: 120, height: 72)
            Text(mode.title).font(.headline)
            Text(mode.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1)
        )
    }

    private var diagram: some View {
        VStack(spacing: 3) {
            switch mode {
            case .separate:
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.4))
                    Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                }
            case .videoTop:
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.4))
                RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.7))
            case .videoBottom:
                RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.7))
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.4))
            }
        }
    }
}

struct WorkingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        statusArea
    }

    private var statusArea: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
            Text(model.status.stageLabel)
                .font(.title.bold())
                .contentTransition(.opacity)
            if let description = model.status.stageDescription {
                Text(description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .transition(.opacity)
            }
            if let percent = model.status.percent {
                ProgressView(value: Double(percent), total: 100)
                    .frame(maxWidth: 360)
                Text("\(percent)%").foregroundStyle(.secondary)
            }
            if let detail = model.status.detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .lineLimit(4)
            }
            Text("This can take a few minutes. Feel free to do something else.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: model.showDebug ? nil : .infinity)
    }
}

struct DoneView: View {
    @EnvironmentObject var model: AppModel
    let url: URL

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("All done!")
                .font(.largeTitle.bold())
            Text(url.lastPathComponent)
                .font(.callout)
                .foregroundStyle(.secondary)
            // Exactly one prominent button, so macOS does not tint two
            // "default" buttons together and leave them lit.
            HStack(spacing: 14) {
                Button("Open the video") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button("Give feedback to the agent to make a change") {
                model.feedbackText = ""
                model.screen = .feedback(url)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button("Back to projects") { model.backToProjects() }
                .buttonStyle(.link)
        }
        .padding(40)
    }
}

// Read-only viewer for the exact system prompt, in a fixed-width font.
struct PromptSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("System prompt").font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.promptText ?? "", forType: .string)
                }
                Button("Done") { model.showPrompt = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                Text(model.promptText ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 720, height: 560)
    }
}

struct FeedbackView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var editorFocused: Bool
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                model.screen = .done(url)
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.link)

            Text("What should change?")
                .font(.largeTitle.bold())
            Text("Tell the agent what to adjust, and it will revise this video. For example: \"Make the captions bigger\" or \"Remove the counter at the end.\"")
                .foregroundStyle(.secondary)

            TextEditor(text: $model.feedbackText)
                .font(.title3)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 160)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3)))

            DictateButton { startDictation(focus: $editorFocused) }

            HStack {
                Spacer()
                Button("Send to the agent") { model.applyFeedback() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.feedbackText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(40)
    }
}

struct FailedView: View {
    @EnvironmentObject var model: AppModel
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("That didn't work")
                .font(.largeTitle.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            HStack {
                Button("Try again") { model.start() }
                    .buttonStyle(.borderedProminent)
                Button("Back to projects") { model.backToProjects() }
            }
            DisclosureGroup("Show details") {
                DebugConsole(debug: model.debug)
                    .frame(height: 240)
            }
            .frame(maxWidth: 560)
        }
        .padding(40)
    }
}

struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    @State private var newName = ""
    @State private var naming = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if naming {
                nameEntry
            } else {
                Button {
                    naming = true
                    nameFocused = true
                } label: {
                    Label("Start a new project", systemImage: "plus.circle.fill")
                        .font(.title2.weight(.semibold))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Text("Your projects")
                .font(.largeTitle.bold())

            if model.recentProjects.isEmpty {
                Spacer()
                Text("No projects yet. Start one above to begin.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                Text("Or click an existing project to work on it")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                List(model.recentProjects) { project in
                    Button { model.open(project) } label: {
                        HStack {
                            Image(systemName: project.existingOutput != nil ? "checkmark.circle.fill" : "film")
                                .foregroundStyle(project.existingOutput != nil ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(project.name).font(.headline)
                                Text(statusLine(project))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .padding(40)
    }

    private var nameEntry: some View {
        HStack {
            TextField("Name your new project", text: $newName)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($nameFocused)
                .onSubmit(create)
            Button("Create", action: create)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel") {
                naming = false
                newName = ""
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 520)
    }

    private func create() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.newProject(name: newName)
        newName = ""
        naming = false
    }

    private func statusLine(_ project: Project) -> String {
        if project.existingOutput != nil { return "Finished · \(project.info.mode)" }
        if project.hasSource { return "In progress · \(project.info.mode)" }
        return "New"
    }
}

// Scrolling log of every command, its output, and the agent's tool calls.
struct DebugConsole: View {
    @ObservedObject var debug: DebugLog

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Detailed log").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(debug.plainText, forType: .string)
                }
                Button("Clear") { debug.clear() }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(debug.lines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .onChange(of: debug.lines.count) { _, _ in
                    if let last = debug.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func color(for kind: DebugLog.Kind) -> Color {
        switch kind {
        case .command: .blue
        case .stderr, .error: .red
        case .tool: .purple
        case .info: .secondary
        case .stdout: .primary
        }
    }
}

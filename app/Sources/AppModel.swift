import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: AppScreen = .setup
    @Published var status = WorkStatus()

    // The open project. Everything a run produces lives in its folder.
    @Published var currentProject: Project?
    @Published var recentProjects: [Project] = []

    // Working inputs, synced to the project on start.
    @Published var localVideo: URL?
    @Published var videoURLText = ""
    @Published var direction = ""
    @Published var mode: LayoutMode = .videoBottom

    @Published var apiKeyDraft = ""
    @Published var setupProgress: String?

    // Self-update: set when GitHub has a newer release.
    @Published var availableUpdate: Updater.AvailableUpdate?
    @Published var updateProgress: String?

    // Revision request typed on the feedback screen.
    @Published var feedbackText = ""

    // Detailed processing log for the Debug panel.
    let debug = DebugLog()
    @Published var showDebug = false

    // In-app Claude sign-in state.
    @Published var signingIn = false
    @Published var signInError: String?
    private var loginProcess: Process?

    // System-prompt viewer.
    @Published var promptText: String?
    @Published var showPrompt = false

    init() {
        if ClaudeAuth.isConfigured {
            screen = .projects
        }
        refreshProjects()
        Task { await prepareWorkerQuietly() }
        Task { availableUpdate = await Updater.check() }
    }

    // MARK: - Self-update

    func installUpdate() {
        guard let update = availableUpdate, updateProgress == nil else { return }
        Task {
            do {
                try await Updater.install(update) { [weak self] text in
                    Task { @MainActor in self?.updateProgress = text }
                }
            } catch {
                updateProgress = nil
                debug.log(.error, "update failed: \(error.localizedDescription)")
                let alert = NSAlert()
                alert.messageText = "The update could not be installed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    // MARK: - Auth

    var subscriptionLabel: String? { ClaudeAuth.subscriptionLabel }
    var hasSubscriptionLogin: Bool { ClaudeAuth.hasSubscriptionLogin }

    func continueWithSubscription() {
        // Trust the user's "I've signed in": proceed even if detection could
        // not confirm the login. A truly missing login surfaces later as a
        // clear "not signed in" message from the design step.
        ClaudeAuth.assumeSubscription = true
        refreshProjects()
        screen = .projects
    }

    // Signs into a Claude subscription using the bundled Claude binary, which
    // opens the browser. No separate CLI install. Proceeds when it succeeds.
    func signInToClaude() {
        guard let claude = Config.claudeBinary else {
            signInError = "The sign-in tool is still being set up. Wait a moment and try again."
            return
        }
        signInError = nil
        signingIn = true
        Task {
            let ok = await runLogin(claude)
            signingIn = false
            loginProcess = nil
            if ok || ClaudeAuth.hasSubscriptionLogin {
                ClaudeAuth.assumeSubscription = true
                refreshProjects()
                screen = .projects
            } else {
                signInError = "Sign-in did not finish. Try again, and complete the page that opens in your browser."
            }
        }
    }

    func cancelSignIn() {
        loginProcess?.terminate()
        loginProcess = nil
        signingIn = false
    }

    // Shows the exact system prompt and first user message for the open
    // project, built by generate.js so the app never drifts from it.
    func viewSystemPrompt() {
        guard let project = currentProject else { return }
        promptText = "Loading…"
        showPrompt = true
        Task {
            let result = await Sidecar.runProcess(
                Config.node,
                arguments: [
                    Config.workerDir.appendingPathComponent("generate.js").path,
                    "--job", project.folder.path,
                    "--direction", direction,
                    "--print-prompt",
                ],
                cwd: Config.workerDir
            )
            promptText = result.stdout.isEmpty ? "Could not build the prompt." : result.stdout
        }
    }

    private func runLogin(_ claude: URL) async -> Bool {
        let result = await Sidecar.runProcess(claude, arguments: ["auth", "login", "--claudeai"]) { [weak self] process in
            Task { @MainActor in self?.loginProcess = process }
        }
        return result.ok
    }

    func saveAPIKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Keychain.saveAPIKey(key)
        refreshProjects()
        screen = .projects
    }

    // MARK: - Projects

    func refreshProjects() {
        recentProjects = ProjectStore.list()
    }

    func newProject(name: String) {
        let project = ProjectStore.create(name: name, mode: mode)
        openInputs(from: project)
        currentProject = project
        localVideo = nil
        videoURLText = ""
        screen = .pickVideo
    }

    func open(_ project: Project) {
        openInputs(from: project)
        currentProject = project
        if let output = project.existingOutput {
            screen = .done(output)
        } else if project.hasSource {
            screen = .direction
        } else {
            screen = .pickVideo
        }
    }

    private func openInputs(from project: Project) {
        direction = project.info.direction
        mode = LayoutMode(rawValue: project.info.mode) ?? .videoBottom
        videoURLText = project.info.sourceURLText ?? ""
        localVideo = nil
    }

    func backToProjects() {
        refreshProjects()
        screen = .projects
    }

    var hasVideo: Bool {
        localVideo != nil || !videoURLText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - First-run worker install

    private func prepareWorkerQuietly() async {
        let fm = FileManager.default
        if let bundled = Config.bundledWorker {
            let installed = Config.appSupport.appendingPathComponent("worker")
            try? fm.createDirectory(at: installed, withIntermediateDirectories: true)

            // node_modules is large (and holds the downloaded browser cache),
            // so copy it only when missing or when the app version changes.
            let installedModules = installed.appendingPathComponent("node_modules")
            let stamp = Config.appSupport.appendingPathComponent("worker-node-modules-version.txt")
            let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
            let installedVersion = (try? String(contentsOf: stamp, encoding: .utf8)) ?? ""
            if installedVersion != version || !fm.fileExists(atPath: installedModules.path) {
                setupProgress = "Setting things up…"
                try? fm.removeItem(at: installedModules)
                try? fm.copyItem(at: bundled.appendingPathComponent("node_modules"), to: installedModules)
                try? version.write(to: stamp, atomically: true, encoding: .utf8)
            }

            // Everything else (scripts and the template) is small, so refresh
            // it every launch. This keeps the installed worker in step with
            // the app without recopying node_modules.
            if let items = try? fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) {
                for item in items where item.lastPathComponent != "node_modules" {
                    let dst = installed.appendingPathComponent(item.lastPathComponent)
                    try? fm.removeItem(at: dst)
                    try? fm.copyItem(at: item, to: dst)
                }
            }
        }
        let setupScript = Config.workerDir.appendingPathComponent("setup.js")
        if fm.fileExists(atPath: setupScript.path) {
            _ = try? await Sidecar.run(Config.node, arguments: [setupScript.path], cwd: Config.workerDir, debug: debug) { [weak self] event in
                if event.type == "progress", let percent = event.percent {
                    self?.setupProgress = "Downloading components… \(percent)%"
                }
            }
        }
        setupProgress = nil
    }

    // MARK: - Pipeline

    func start() {
        runFromInputs(feedback: nil)
    }

    // Runs another pass that revises the existing design from the user's
    // typed or dictated feedback.
    func applyFeedback() {
        let text = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        feedbackText = ""
        runFromInputs(feedback: text)
    }

    private func runFromInputs(feedback: String?) {
        screen = .working
        status = WorkStatus(stageLabel: "Getting ready")
        Task {
            do {
                let output = try await runPipeline(feedback: feedback)
                screen = .done(output)
            } catch {
                debug.log(.error, "\(error)")
                // Worker scripts own the user-facing wording of failures;
                // show their message as-is.
                screen = .failed(error.localizedDescription)
            }
        }
    }

    private func setStage(_ key: String, percent: Int? = nil, detail: String? = nil) {
        status.stageLabel = stageInfo[key]?.label ?? key
        status.stageKey = key
        status.percent = percent
        if let detail { status.detail = detail }
    }

    private func handle(_ event: SidecarEvent) {
        if let stage = event.stage {
            status.stageLabel = stageInfo[stage]?.label ?? stage
            status.stageKey = stage
        }
        if event.type != "log" {
            status.percent = event.percent
        }
        // Route agent tool calls and their output only to the debug window.
        if event.type == "log", let text = event.text {
            debug.log(event.tool != nil ? .tool : .info, event.tool.map { "[\($0)] \(text)" } ?? text)
            return
        }
        if event.type == "status", let text = event.text {
            status.detail = text
        }
    }

    private func runPipeline(feedback: String?) async throws -> URL {
        guard let authMode = ClaudeAuth.mode else {
            throw SidecarError.failed("Claude is not set up")
        }
        guard var project = currentProject else {
            throw SidecarError.failed("no project is open")
        }
        let worker = Config.workerDir
        let jobDir = project.folder

        // Persist the choices for reopen.
        project.info.direction = direction
        project.info.mode = mode.rawValue
        if localVideo == nil, !videoURLText.trimmingCharacters(in: .whitespaces).isEmpty {
            project.info.sourceURLText = videoURLText.trimmingCharacters(in: .whitespaces)
        }
        ProjectStore.save(project)

        // 1. Source video: reuse what the project already has.
        var captionTrack: URL?
        var localSource: URL?
        if project.hasSource {
            debug.log(.info, "reusing existing source video")
        } else if let localVideo {
            localSource = localVideo
        } else {
            setStage("downloading")
            let done = try await Sidecar.run(
                Config.node,
                arguments: [
                    worker.appendingPathComponent("download.js").path,
                    "--url", videoURLText.trimmingCharacters(in: .whitespaces),
                    "--out", project.downloadDir.path,
                ],
                environment: ["YTDLP_PATH": Config.ytdlp.path, "FFMPEG_PATH": Config.ffmpeg.path],
                cwd: worker, debug: debug
            ) { [weak self] in self?.handle($0) }
            guard let path = done.output else { throw SidecarError.failed("the video could not be downloaded") }
            localSource = URL(fileURLWithPath: path)
            captionTrack = done.subtitles.map { URL(fileURLWithPath: $0) }
        }

        // 2. Prepare the Remotion project (idempotent: preserves prior work).
        setStage("importing")
        var createArgs = [
            worker.appendingPathComponent("create-job.js").path,
            "--mode", mode.rawValue,
            "--job", jobDir.path,
        ]
        if let localSource { createArgs.append(contentsOf: ["--source", localSource.path]) }
        try await Sidecar.run(
            Config.node, arguments: createArgs,
            environment: ["FFPROBE_PATH": Config.ffprobe.path], cwd: worker, debug: debug
        ) { [weak self] in self?.handle($0) }

        // 3 + 4. Words: reuse transcript, else captions, else transcribe.
        if project.hasTranscript {
            debug.log(.info, "reusing existing transcript")
        } else if let captionTrack {
            setStage("transcribing")
            try await Sidecar.run(
                Config.node,
                arguments: [
                    worker.appendingPathComponent("subs-to-transcript.js").path,
                    "--vtt", captionTrack.path, "--job", jobDir.path,
                ],
                cwd: worker, debug: debug
            ) { [weak self] in self?.handle($0) }
        } else {
            setStage("audio")
            let source = project.sourceFile ?? localSource
            guard let source else { throw SidecarError.failed("no source video to transcribe") }
            let audio = jobDir.appendingPathComponent("audio.wav")
            try await runPlain(Config.ffmpeg, [
                "-y", "-i", source.path, "-vn", "-ac", "1", "-ar", "16000", audio.path,
            ])
            setStage("transcribing")
            try await Sidecar.run(
                Config.transcriber,
                arguments: [audio.path, project.transcriptFile.path, Locale.current.identifier],
                debug: debug
            ) { [weak self] in self?.handle($0) }
        }

        // 5. Design the graphics. Subscription login when we have it.
        setStage("designing")
        var generateEnv: [String: String] = [:]
        let authArg: String
        switch authMode {
        case .subscription: authArg = "subscription"
        case .apiKey(let key): authArg = "apikey"; generateEnv["ANTHROPIC_API_KEY"] = key
        }
        var generateArgs = [
            worker.appendingPathComponent("generate.js").path,
            "--job", jobDir.path, "--direction", direction, "--auth", authArg,
        ]
        if let feedback {
            generateArgs.append(contentsOf: ["--feedback", feedback])
        }
        try await Sidecar.run(
            Config.node, arguments: generateArgs,
            environment: generateEnv, cwd: worker, debug: debug
        ) { [weak self] in self?.handle($0) }

        // 6. Render.
        setStage("rendering")
        let rendered = try await Sidecar.run(
            Config.node,
            arguments: [worker.appendingPathComponent("render.js").path, "--job", jobDir.path],
            environment: ["FFMPEG_PATH": Config.ffmpeg.path], cwd: worker, debug: debug
        ) { [weak self] in self?.handle($0) }
        guard let outputPath = rendered.output else { throw SidecarError.failed("rendering finished without a file") }

        ProjectStore.save(project)
        refreshProjects()
        return URL(fileURLWithPath: outputPath)
    }

    private func runPlain(_ executable: URL, _ arguments: [String]) async throws {
        debug.log(.command, "\(executable.path) \(arguments.joined(separator: " "))")
        let result = await Sidecar.runProcess(executable, arguments: arguments)
        if !result.ok {
            let tail = String(result.stderr.suffix(500))
            debug.log(.error, tail)
            throw SidecarError.failed(tail)
        }
    }
}

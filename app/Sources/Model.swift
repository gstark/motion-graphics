import Foundation

enum LayoutMode: String, CaseIterable, Identifiable {
    case separate
    case videoTop = "video-top"
    case videoBottom = "video-bottom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .separate: "Graphics only"
        case .videoTop: "Video on top"
        case .videoBottom: "Video on bottom"
        }
    }

    var caption: String {
        switch self {
        case .separate: "A see-through graphics file you can lay over the video in any editor"
        case .videoTop: "One finished video: your video above, graphics below"
        case .videoBottom: "One finished video: graphics above, your video below"
        }
    }
}

enum AppScreen {
    case setup
    case projects
    case pickVideo
    case direction
    case working
    case done(URL)
    case feedback(URL)
    case failed(String)
}

struct WorkStatus {
    var stageLabel: String = "Getting ready"
    var stageKey: String? = nil
    var percent: Int? = nil
    var detail: String? = nil

    var stageDescription: String? {
        stageKey.flatMap { stageInfo[$0]?.description }
    }
}

// The headline label and the plain-language sentence for one pipeline stage.
struct StageInfo {
    let label: String
    let description: String
}

// One entry per NDJSON stage the worker scripts emit.
let stageInfo: [String: StageInfo] = [
    "downloading": .init(
        label: "Getting your video",
        description: "Fetching the video from the web."),
    "importing": .init(
        label: "Reading your video",
        description: "Reading the video and getting it ready."),
    "audio": .init(
        label: "Listening to the video",
        description: "Pulling the audio out so it can be understood."),
    "language-model-download": .init(
        label: "Learning the language",
        description: "Getting the speech model your Mac needs."),
    "transcribing": .init(
        label: "Listening to the video",
        description: "Writing down what is said, with the timing of each line."),
    "designing": .init(
        label: "Designing your graphics",
        description: "Claude is designing graphics that match what is said."),
    "checking": .init(
        label: "Checking the design",
        description: "Making sure the design will build correctly."),
    "bundling": .init(
        label: "Warming up",
        description: "Preparing the graphics for drawing."),
    "rendering": .init(
        label: "Drawing the frames",
        description: "Drawing each frame of your graphics."),
    "stitching": .init(
        label: "Putting it all together",
        description: "Combining the graphics with your video."),
    "browser-download": .init(
        label: "Downloading components",
        description: "Downloading a one-time component the first time you run."),
]

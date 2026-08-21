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
        stageKey.flatMap { stageDescriptions[$0] }
    }
}

// Friendly names for the pipeline's NDJSON stages.
let stageLabels: [String: String] = [
    "downloading": "Getting your video",
    "importing": "Reading your video",
    "audio": "Listening to the video",
    "language-model-download": "Learning the language",
    "transcribing": "Listening to the video",
    "designing": "Designing your graphics",
    "checking": "Checking the design",
    "bundling": "Warming up",
    "rendering": "Drawing the frames",
    "stitching": "Putting it all together",
    "browser-download": "Downloading components",
]

// A plain-language sentence describing what each stage is doing.
let stageDescriptions: [String: String] = [
    "downloading": "Fetching the video from the web.",
    "importing": "Reading the video and getting it ready.",
    "audio": "Pulling the audio out so it can be understood.",
    "language-model-download": "Getting the speech model your Mac needs.",
    "transcribing": "Writing down what is said, with the timing of each line.",
    "designing": "Claude is designing graphics that match what is said.",
    "checking": "Making sure the design will build correctly.",
    "bundling": "Preparing the graphics for drawing.",
    "rendering": "Drawing each frame of your graphics.",
    "stitching": "Combining the graphics with your video.",
    "browser-download": "Downloading a one-time component the first time you run.",
]

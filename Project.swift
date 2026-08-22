import ProjectDescription

// Release builds pass the tag via TUIST_MG_VERSION (see release.sh);
// everything else is "0.0.0", which the in-app updater treats as a dev
// build and leaves alone.
let version = Environment.mgVersion.getString(default: "0.0.0")

let project = Project(
    name: "MotionGraphics",
    targets: [
        .target(
            name: "MotionGraphics",
            destinations: .macOS,
            product: .app,
            bundleId: "com.gstark.MotionGraphics",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": .string(version),
                "CFBundleVersion": .string(version),
                "LSApplicationCategoryType": "public.app-category.video",
                "NSSpeechRecognitionUsageDescription": "Transcribes your video so the graphics can follow the speech.",
            ]),
            sources: ["app/Sources/**"],
            resources: [
                "app/Resources/Assets.xcassets",
                .folderReference(path: "app/Resources/bin"),
                .folderReference(path: "app/Resources/worker"),
            ],
            settings: .settings(base: [
                "ENABLE_HARDENED_RUNTIME": "NO",
                "ENABLE_APP_SANDBOX": "NO",
                "CODE_SIGN_IDENTITY": "-",
                "SWIFT_VERSION": "5.0",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            ])
        ),
    ]
)

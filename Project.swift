import ProjectDescription

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

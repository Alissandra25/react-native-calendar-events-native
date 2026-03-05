// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CalendarEventsNative",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "CalendarEventsNative",
            targets: ["CalendarEventsNative"]
        ),
    ],
    targets: [
        .target(
            name: "CalendarEventsNative",
            path: "ios",
            sources: [
                "CalendarEventsNative.mm"
            ],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedFramework("EventKitUI"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)

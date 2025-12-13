load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_bundle",
    "apple_resource_group",
)
load("//build-system/bazel-utils:plist_fragment.bzl",
    "plist_fragment",
)

filegroup(
    name = "MetalSources",
    srcs = glob([
        "MetalResources/**/*.metal",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "TabBarComponentBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.TabBarComponent</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>TabBarComponent</string>
    """
)

apple_resource_bundle(
    name = "TabBarComponentBundle",
    infoplists = [
        ":TabBarComponentBundleInfoPlist",
    ],
    resources = [
        ":MetalSources",
    ],
)

swift_library(
    name = "TabBarComponent",
    module_name = "TabBarComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    data = [
        ":TabBarComponentBundle",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/TelegramPresentationData",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        "//submodules/TelegramUI/Components/LottieComponent",
        "//submodules/Components/BundleIconComponent",
        "//submodules/TelegramUI/Components/TextBadgeComponent",
        "//submodules/UIKitRuntimeUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)

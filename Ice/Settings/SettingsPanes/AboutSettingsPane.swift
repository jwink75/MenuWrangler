//
//  AboutSettingsPane.swift
//  Ice
//

import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL

    private var updatesManager: UpdatesManager {
        appState.updatesManager
    }

    private var acknowledgementsURL: URL {
        // swiftlint:disable:next force_unwrapping
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf")!
    }

    private var contributeURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://github.com/jordanbaird/Ice")!
    }

    private var issuesURL: URL {
        contributeURL.appendingPathComponent("issues")
    }

    private var donateURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://icemenubar.app/Donate")!
    }

    private var lastUpdateCheckString: String {
        if let date = updatesManager.lastUpdateCheckDate {
            date.formatted(date: .abbreviated, time: .standard)
        } else {
            "Never"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            mainForm
            Spacer(minLength: 20)
            bottomBar
        }
        .padding(30)
    }

    @ViewBuilder
    private var mainForm: some View {
        IceForm(padding: EdgeInsets(top: 5, leading: 30, bottom: 30, trailing: 30), spacing: 0) {
            appIconAndCopyrightSection
                .layoutPriority(1)

            Spacer(minLength: 0)
                .frame(maxHeight: 20)

            forkAttributionSection
                .layoutPriority(1)
        }
        .scrollDisabled(true)
        .frame(maxHeight: 500)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 20, style: .circular))
    }

    @ViewBuilder
    private var appIconAndCopyrightSection: some View {
        IceSection(options: .plain) {
            HStack(spacing: 10) {
                if let nsImage = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 225)
                }

                VStack(alignment: .leading) {
                    Text("MenuWrangler")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(.primary)

                    Text("Version \(Constants.versionString)")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)

                    Text(Constants.copyrightString)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var forkAttributionSection: some View {
        IceSection(options: .plain) {
            VStack(alignment: .leading, spacing: 8) {
                Text("About MenuWrangler")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("MenuWrangler is an enhanced macOS menu bar management utility derived as a fork of the open-source Ice project created by Jordan Baird.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Original Ice Project on GitHub") {
                        openURL(URL(string: "https://github.com/jordanbaird/Ice")!)
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: 600)
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            Button("Quit MenuWrangler") {
                NSApp.terminate(nil)
            }
            Spacer()
            Button("Acknowledgements") {
                NSWorkspace.shared.open(acknowledgementsURL)
            }
            Button("Ice Repository") {
                openURL(contributeURL)
            }
        }
        .padding(8)
        .buttonStyle(BottomBarButtonStyle())
        .background(.quinary, in: Capsule(style: .circular))
        .frame(height: 40)
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        Capsule(style: .circular)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

import AppKit
import ApplicationServices
import AudioToolbox
import CoreAudio
import IOKit.hidsystem
import QuartzCore

enum MediaControlCommand {
    case previous
    case playPause
    case next

    var symbolName: String {
        switch self {
        case .previous:
            return "backward.fill"
        case .playPause:
            return "playpause.fill"
        case .next:
            return "forward.fill"
        }
    }

    var toolTip: String {
        switch self {
        case .previous:
            return "Previous track"
        case .playPause:
            return "Play or pause"
        case .next:
            return "Next track"
        }
    }

    var mediaKey: Int32 {
        switch self {
        case .previous:
            return NX_KEYTYPE_PREVIOUS
        case .playPause:
            return NX_KEYTYPE_PLAY
        case .next:
            return NX_KEYTYPE_NEXT
        }
    }
}

final class VolumeMeterView: NSView {
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private var progressValue: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 8)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false

        trackLayer.cornerRadius = 4
        fillLayer.cornerRadius = 4

        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        fillLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * progressValue, height: bounds.height)
        CATransaction.commit()

        applyColors()
    }

    func update(progress: CGFloat) {
        progressValue = min(max(progress, 0), 1)
        needsLayout = true
    }

    private func applyColors() {
        trackLayer.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        fillLayer.backgroundColor = NSColor.controlAccentColor.cgColor
    }
}

fileprivate enum PopoverPanel: Int {
    case controls = 0
    case preferences = 1
}

private enum AppPreferences {
    static let scrollAxisPreferenceKey = "HoverVolume.scrollAxisPreference"
    static let automaticUpdateChecksEnabledKey = "HoverVolume.automaticUpdateChecksEnabled"
    static let automaticUpdateInstallationEnabledKey = "HoverVolume.automaticUpdateInstallationEnabled"
    static let statusItemScale: CGFloat = 0.9

    static func loadScrollAxisPreference() -> ScrollAxisPreference {
        guard
            let rawValue = UserDefaults.standard.string(forKey: scrollAxisPreferenceKey),
            let preference = ScrollAxisPreference(rawValue: rawValue)
        else {
            return .verticalPriority
        }

        return preference
    }

    static func saveScrollAxisPreference(_ preference: ScrollAxisPreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: scrollAxisPreferenceKey)
    }

    static func loadAutomaticUpdateChecksEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: automaticUpdateChecksEnabledKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: automaticUpdateChecksEnabledKey)
    }

    static func saveAutomaticUpdateChecksEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: automaticUpdateChecksEnabledKey)
    }

    static func loadAutomaticUpdateInstallationEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: automaticUpdateInstallationEnabledKey)
    }

    static func saveAutomaticUpdateInstallationEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: automaticUpdateInstallationEnabledKey)
    }

}

private extension ScrollAxisPreference {
    var title: String {
        switch self {
        case .verticalOnly:
            return "Vertical Only"
        case .verticalPriority:
            return "Vertical Priority"
        case .anyDirection:
            return "Any Direction"
        }
    }

    var controlsHintText: String {
        switch self {
        case .verticalOnly:
            return "Scroll up or down to change volume"
        case .verticalPriority:
            return "Scroll up or down to change volume. Horizontal only applies when vertical is idle"
        case .anyDirection:
            return "Scroll up, down, left, or right to change volume"
        }
    }

    var settingsDescription: String {
        switch self {
        case .verticalOnly:
            return "Only vertical movement changes volume. Best if you want clean up and down control."
        case .verticalPriority:
            return "Vertical movement takes priority. Horizontal still works when there is no vertical input."
        case .anyDirection:
            return "The strongest scroll axis changes volume, including horizontal swipes."
        }
    }
}

private struct GitHubRepositoryConfiguration {
    let owner: String
    let name: String

    var releasesURL: URL {
        URL(string: "https://github.com/\(owner)/\(name)/releases/latest")!
    }

    var latestReleaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases/latest")!
    }

    static func load(from bundle: Bundle = .main) -> GitHubRepositoryConfiguration {
        let owner = (bundle.object(forInfoDictionaryKey: "HoverVolumeGitHubOwner") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (bundle.object(forInfoDictionaryKey: "HoverVolumeGitHubRepository") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return GitHubRepositoryConfiguration(
            owner: (owner?.isEmpty == false ? owner : "Katilla1") ?? "Katilla1",
            name: (name?.isEmpty == false ? name : "HoverVolume") ?? "HoverVolume"
        )
    }
}

fileprivate struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    var displayVersion: String {
        HoverVolumeLogic.normalizedVersionString(tagName)
    }

    var preferredDownloadURL: URL {
        if let diskImage = assets.first(where: { $0.name.localizedCaseInsensitiveContains(".dmg") }) {
            return diskImage.browserDownloadURL
        }

        if let zip = assets.first(where: { $0.name.localizedCaseInsensitiveContains(".zip") }) {
            return zip.browserDownloadURL
        }

        return htmlURL
    }

    var preferredInstallAsset: Asset? {
        assets.first(where: { $0.name.localizedCaseInsensitiveContains(".zip") })
    }
}

fileprivate enum UpdateState {
    case idle(currentVersion: String)
    case checking(currentVersion: String)
    case upToDate(currentVersion: String)
    case available(currentVersion: String, release: GitHubRelease)
    case installing(currentVersion: String, release: GitHubRelease, message: String)
    case failed(currentVersion: String, message: String)

    var currentVersion: String {
        switch self {
        case let .idle(currentVersion),
             let .checking(currentVersion),
             let .upToDate(currentVersion),
             let .available(currentVersion, _),
             let .installing(currentVersion, _, _),
             let .failed(currentVersion, _):
            return currentVersion
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .checking:
            return "Checking..."
        case .installing:
            return "Installing..."
        case let .available(_, release):
            return release.preferredInstallAsset == nil ? "Download Update" : "Install Update"
        default:
            return "Check for Updates"
        }
    }

    var statusText: String {
        switch self {
        case let .idle(currentVersion):
            return "Version \(currentVersion). GitHub releases can be checked automatically."
        case .checking:
            return "Checking GitHub for the latest release..."
        case let .upToDate(currentVersion):
            return "You're on the latest version: \(currentVersion)."
        case let .available(currentVersion, release):
            return "Update available: \(release.displayVersion). Current version: \(currentVersion)."
        case let .installing(_, release, message):
            return "Installing \(release.displayVersion). \(message)"
        case let .failed(_, message):
            return message
        }
    }

    var isBusy: Bool {
        switch self {
        case .checking, .installing:
            return true
        default:
            return false
        }
    }

    var availableRelease: GitHubRelease? {
        switch self {
        case let .available(_, release), let .installing(_, release, _):
            return release
        default:
            return nil
        }
    }
}

fileprivate enum UpdateCheckOutcome {
    case upToDate
    case available(GitHubRelease)
}

fileprivate enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case unexpectedStatusCode(Int)
    case emptyVersion

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid update response."
        case let .unexpectedStatusCode(code):
            return "GitHub update check failed with status \(code)."
        case .emptyVersion:
            return "The latest GitHub release did not include a usable version tag."
        }
    }
}

fileprivate final class GitHubUpdateChecker {
    private let latestReleaseAPIURL: URL
    private let session: URLSession
    private var activeTask: URLSessionDataTask?

    init(repository: GitHubRepositoryConfiguration = .load(), session: URLSession = .shared) {
        latestReleaseAPIURL = repository.latestReleaseAPIURL
        self.session = session
    }

    func checkForUpdates(currentVersion: String, completion: @escaping (Result<UpdateCheckOutcome, Error>) -> Void) {
        activeTask?.cancel()

        var request = URLRequest(url: latestReleaseAPIURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HoverVolume/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        activeTask = session.dataTask(with: request) { data, response, error in
            let finish: (Result<UpdateCheckOutcome, Error>) -> Void = { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }

            if let cancellationError = error as NSError?, cancellationError.code == NSURLErrorCancelled {
                return
            }

            if let error {
                finish(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                finish(.failure(UpdateCheckError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                finish(.failure(UpdateCheckError.unexpectedStatusCode(httpResponse.statusCode)))
                return
            }

            guard let data else {
                finish(.failure(UpdateCheckError.invalidResponse))
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

                guard !release.displayVersion.isEmpty else {
                    finish(.failure(UpdateCheckError.emptyVersion))
                    return
                }

                if HoverVolumeLogic.isVersion(release.displayVersion, newerThan: currentVersion) {
                    finish(.success(.available(release)))
                } else {
                    finish(.success(.upToDate))
                }
            } catch is DecodingError {
                finish(.failure(UpdateCheckError.invalidResponse))
            } catch {
                finish(.failure(error))
            }
        }

        activeTask?.resume()
    }
}

fileprivate enum SelfUpdateError: LocalizedError {
    case noInstallableAsset
    case targetDirectoryNotWritable(URL)
    case downloadFailed
    case extractionFailed
    case extractedAppMissing
    case installerLaunchFailed

    var errorDescription: String? {
        switch self {
        case .noInstallableAsset:
            return "The latest GitHub release does not include a zip app build for automatic installation."
        case let .targetDirectoryNotWritable(url):
            return "HoverVolume cannot replace the app in \(url.path) because that folder is not writable."
        case .downloadFailed:
            return "The update download did not complete."
        case .extractionFailed:
            return "HoverVolume could not unpack the downloaded update."
        case .extractedAppMissing:
            return "The downloaded update did not contain a HoverVolume.app bundle."
        case .installerLaunchFailed:
            return "HoverVolume could not start the installer helper."
        }
    }
}

fileprivate final class SelfUpdater {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func install(release: GitHubRelease, replacing bundleURL: URL, progress: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let asset = release.preferredInstallAsset else {
            completion(.failure(SelfUpdateError.noInstallableAsset))
            return
        }

        let targetDirectory = bundleURL.deletingLastPathComponent()
        guard isWritableDirectory(targetDirectory) else {
            completion(.failure(SelfUpdateError.targetDirectoryNotWritable(targetDirectory)))
            return
        }

        let reportProgress: (String) -> Void = { message in
            DispatchQueue.main.async {
                progress(message)
            }
        }

        reportProgress("Downloading update archive...")
        let task = session.downloadTask(with: asset.browserDownloadURL) { localURL, _, error in
            let finish: (Result<Void, Error>) -> Void = { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }

            if let cancellationError = error as NSError?, cancellationError.code == NSURLErrorCancelled {
                return
            }

            if let error {
                finish(.failure(error))
                return
            }

            guard let localURL else {
                finish(.failure(SelfUpdateError.downloadFailed))
                return
            }

            do {
                let fileManager = FileManager.default
                let stagingRoot = fileManager.temporaryDirectory.appendingPathComponent("HoverVolumeUpdate-\(UUID().uuidString)", isDirectory: true)
                let archiveURL = stagingRoot.appendingPathComponent(asset.name)
                let extractDirectory = stagingRoot.appendingPathComponent("Extracted", isDirectory: true)
                let installerScriptURL = stagingRoot.appendingPathComponent("install-update.sh")

                try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
                try fileManager.moveItem(at: localURL, to: archiveURL)
                reportProgress("Unpacking update...")
                try SelfUpdater.runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractDirectory.path])

                guard let extractedAppURL = SelfUpdater.findFirstAppBundle(in: extractDirectory) else {
                    throw SelfUpdateError.extractedAppMissing
                }

                let script = """
                #!/bin/zsh
                set -euo pipefail
                target="$1"
                staged="$2"
                pid="$3"
                staging_root="$4"
                tmp_target="${target}.updating"
                backup_target="${target}.previous"

                while kill -0 "$pid" 2>/dev/null; do
                  sleep 0.2
                done

                rm -rf "$tmp_target" "$backup_target"
                ditto "$staged" "$tmp_target"
                if [ -d "$target" ]; then
                  mv "$target" "$backup_target"
                fi
                mv "$tmp_target" "$target"
                open "$target"
                rm -rf "$backup_target" "$staging_root"
                """

                try script.write(to: installerScriptURL, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installerScriptURL.path)

                reportProgress("Preparing to relaunch...")

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [
                    installerScriptURL.path,
                    bundleURL.path,
                    extractedAppURL.path,
                    String(ProcessInfo.processInfo.processIdentifier),
                    stagingRoot.path
                ]

                try process.run()
                finish(.success(()))
            } catch let error as SelfUpdateError {
                finish(.failure(error))
            } catch {
                finish(.failure(SelfUpdateError.installerLaunchFailed))
            }
        }

        task.resume()
    }

    private func isWritableDirectory(_ directoryURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.isWritableFile(atPath: directoryURL.path) else { return false }

        let probeURL = directoryURL.appendingPathComponent(".hovervolume-write-test-\(UUID().uuidString)")
        let probeData = Data()

        do {
            try probeData.write(to: probeURL)
            try fileManager.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }

    private static func runProcess(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SelfUpdateError.extractionFailed
        }
    }

    private static func findFirstAppBundle(in directoryURL: URL) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }

        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                return url
            }
        }

        return nil
    }
}

private enum AccessibilityPermissionState {
    case granted
    case denied

    var statusText: String {
        switch self {
        case .granted:
            return "Accessibility access is enabled. HoverVolume can use synthetic system transport events when direct app control is unavailable."
        case .denied:
            return "Accessibility access is off. Direct Music and Spotify control may still work, but generic media-key fallback may fail until HoverVolume is allowed in Privacy & Security > Accessibility."
        }
    }
}

private enum ScriptableMediaApplication: CaseIterable {
    case spotify
    case music

    var bundleIdentifier: String {
        switch self {
        case .spotify:
            return "com.spotify.client"
        case .music:
            return "com.apple.Music"
        }
    }

    var appName: String {
        switch self {
        case .spotify:
            return "Spotify"
        case .music:
            return "Music"
        }
    }

    func appleScript(for command: MediaControlCommand) -> String {
        let commandText: String
        switch command {
        case .previous:
            commandText = "previous track"
        case .playPause:
            commandText = "playpause"
        case .next:
            commandText = "next track"
        }

        return """
        tell application "\(appName)"
            \(commandText)
        end tell
        """
    }
}

final class MediaControlsViewController: NSViewController {
    private enum UI {
        static let controlsPanelSize = NSSize(width: 316, height: 208)
        static let preferencesPanelSize = NSSize(width: 344, height: 402)
        static let controlsContentWidth = CGFloat(272)
        static let preferencesContentWidth = CGFloat(308)
    }

    var onToggleMute: (() -> Void)?
    var onMediaCommand: ((MediaControlCommand) -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onDownloadUpdate: (() -> Void)?
    var onQuit: (() -> Void)?
    var onScrollPreferenceChange: ((ScrollAxisPreference) -> Void)?
    var onAutomaticUpdateChecksChange: ((Bool) -> Void)?
    var onAutomaticUpdateInstallationChange: ((Bool) -> Void)?
    fileprivate var onPopoverPanelChange: ((PopoverPanel) -> Void)?
    var onRequestAccessibilityPermission: (() -> Void)?

    private let panelSelector = NSSegmentedControl(labels: ["Controls", "Preferences"], trackingMode: .selectOne, target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "HoverVolume")
    private let volumeLabel = NSTextField(labelWithString: "Volume 0%")
    private let levelMeter = VolumeMeterView(frame: .zero)
    private let hintLabel = NSTextField(labelWithString: "Scroll over the menu bar icon or this panel to change volume")
    private let muteButton = NSButton(title: "Mute", target: nil, action: nil)
    private let updatesButton = NSButton(title: "Check for Updates", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit HoverVolume", target: nil, action: nil)
    private let controlsStack = NSStackView()
    private let settingsStack = NSStackView()
    private let scrollBehaviorTitleLabel = NSTextField(labelWithString: "Scroll Behavior")
    private let scrollBehaviorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let settingsDescriptionLabel = NSTextField(labelWithString: "")
    private let permissionsTitleLabel = NSTextField(labelWithString: "Permissions")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityPermissionButton = NSButton(title: "Enable Accessibility Access", target: nil, action: nil)
    private let automaticUpdateChecksButton = NSButton(checkboxWithTitle: "Automatically check GitHub for updates", target: nil, action: nil)
    private let automaticUpdateInstallationButton = NSButton(checkboxWithTitle: "Install updates automatically when available", target: nil, action: nil)
    private let updateStatusLabel = NSTextField(labelWithString: "")
    private let checkNowButton = NSButton(title: "Check Now", target: nil, action: nil)
    private let downloadUpdateButton = NSButton(title: "Install Update", target: nil, action: nil)

    private var currentPanel: PopoverPanel {
        PopoverPanel(rawValue: panelSelector.selectedSegment) ?? .controls
    }

    override func loadView() {
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: UI.controlsPanelSize))
        effectView.material = .popover
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true
        view = effectView
        view.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        volumeLabel.alignment = .center
        volumeLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        volumeLabel.alignment = .center

        hintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2

        panelSelector.segmentStyle = .rounded
        panelSelector.controlSize = .small
        panelSelector.selectedSegment = PopoverPanel.controls.rawValue
        panelSelector.target = self
        panelSelector.action = #selector(handlePanelSelection(_:))

        muteButton.bezelStyle = .rounded
        muteButton.controlSize = .regular
        muteButton.font = .systemFont(ofSize: 12, weight: .semibold)
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        muteButton.imagePosition = .imageLeading
        muteButton.contentTintColor = .white
        muteButton.bezelColor = .controlAccentColor

        updatesButton.isBordered = false
        updatesButton.controlSize = .small
        updatesButton.contentTintColor = .controlAccentColor
        updatesButton.target = self
        updatesButton.action = #selector(handleCheckForUpdates)

        quitButton.isBordered = false
        quitButton.controlSize = .small
        quitButton.contentTintColor = .secondaryLabelColor
        quitButton.target = self
        quitButton.action = #selector(handleQuit)

        scrollBehaviorTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        scrollBehaviorTitleLabel.alignment = .left

        scrollBehaviorPopup.controlSize = .regular
        scrollBehaviorPopup.target = self
        scrollBehaviorPopup.action = #selector(handleScrollPreferenceSelection(_:))
        scrollBehaviorPopup.addItems(withTitles: ScrollAxisPreference.allCases.map(\.title))

        settingsDescriptionLabel.font = .systemFont(ofSize: 11)
        settingsDescriptionLabel.textColor = .secondaryLabelColor
        settingsDescriptionLabel.lineBreakMode = .byWordWrapping
        settingsDescriptionLabel.maximumNumberOfLines = 0

        permissionsTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        permissionsTitleLabel.alignment = .left

        accessibilityStatusLabel.font = .systemFont(ofSize: 11)
        accessibilityStatusLabel.textColor = .secondaryLabelColor
        accessibilityStatusLabel.lineBreakMode = .byWordWrapping
        accessibilityStatusLabel.maximumNumberOfLines = 0

        accessibilityPermissionButton.bezelStyle = .rounded
        accessibilityPermissionButton.controlSize = .regular
        accessibilityPermissionButton.target = self
        accessibilityPermissionButton.action = #selector(handleAccessibilityPermissionRequest)

        automaticUpdateChecksButton.font = .systemFont(ofSize: 12, weight: .medium)
        automaticUpdateChecksButton.target = self
        automaticUpdateChecksButton.action = #selector(handleAutomaticUpdateChecksToggle(_:))

        automaticUpdateInstallationButton.font = .systemFont(ofSize: 12, weight: .medium)
        automaticUpdateInstallationButton.target = self
        automaticUpdateInstallationButton.action = #selector(handleAutomaticUpdateInstallationToggle(_:))

        updateStatusLabel.font = .systemFont(ofSize: 11)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.lineBreakMode = .byWordWrapping
        updateStatusLabel.maximumNumberOfLines = 0

        checkNowButton.bezelStyle = .rounded
        checkNowButton.controlSize = .regular
        checkNowButton.target = self
        checkNowButton.action = #selector(handleCheckForUpdates)

        downloadUpdateButton.bezelStyle = .rounded
        downloadUpdateButton.controlSize = .regular
        downloadUpdateButton.target = self
        downloadUpdateButton.action = #selector(handleDownloadUpdate)
        downloadUpdateButton.isHidden = true

        let previousButton = makeMediaButton(for: .previous)
        let playPauseButton = makeMediaButton(for: .playPause)
        let nextButton = makeMediaButton(for: .next)

        let mediaRow = NSStackView(views: [previousButton, playPauseButton, nextButton])
        mediaRow.orientation = .horizontal
        mediaRow.alignment = .centerY
        mediaRow.distribution = .fillEqually
        mediaRow.spacing = 6

        let divider = NSBox()
        divider.boxType = .separator

        let footerRow = NSStackView(views: [updatesButton, quitButton])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.distribution = .fillEqually
        footerRow.spacing = 8

        controlsStack.orientation = .vertical
        controlsStack.alignment = .centerX
        controlsStack.spacing = 10
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        [
            titleLabel,
            volumeLabel,
            levelMeter,
            muteButton,
            mediaRow,
            hintLabel,
            divider,
            footerRow
        ].forEach(controlsStack.addArrangedSubview)

        let settingsHintLabel = NSTextField(labelWithString: "Choose how scroll gestures should affect volume when your pointer is over the menu bar item.")
        settingsHintLabel.font = .systemFont(ofSize: 11)
        settingsHintLabel.textColor = .secondaryLabelColor
        settingsHintLabel.lineBreakMode = .byWordWrapping
        settingsHintLabel.maximumNumberOfLines = 0

        let updatesTitleLabel = NSTextField(labelWithString: "Updates")
        updatesTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        updatesTitleLabel.alignment = .left

        let updatesHintLabel = NSTextField(labelWithString: "HoverVolume checks GitHub Releases and can take you straight to the latest downloadable build.")
        updatesHintLabel.font = .systemFont(ofSize: 11)
        updatesHintLabel.textColor = .secondaryLabelColor
        updatesHintLabel.lineBreakMode = .byWordWrapping
        updatesHintLabel.maximumNumberOfLines = 0

        let updateActionsRow = NSStackView(views: [checkNowButton, downloadUpdateButton])
        updateActionsRow.orientation = .horizontal
        updateActionsRow.alignment = .centerY
        updateActionsRow.distribution = .fillEqually
        updateActionsRow.spacing = 10

        settingsStack.orientation = .vertical
        settingsStack.alignment = .leading
        settingsStack.spacing = 10
        settingsStack.translatesAutoresizingMaskIntoConstraints = false
        [
            scrollBehaviorTitleLabel,
            scrollBehaviorPopup,
            settingsDescriptionLabel,
            settingsHintLabel,
            permissionsTitleLabel,
            accessibilityStatusLabel,
            accessibilityPermissionButton,
            updatesTitleLabel,
            automaticUpdateChecksButton,
            automaticUpdateInstallationButton,
            updateStatusLabel,
            updateActionsRow,
            updatesHintLabel
        ].forEach(settingsStack.addArrangedSubview)
        settingsStack.isHidden = true

        let stack = NSStackView(views: [panelSelector, controlsStack, settingsStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.detachesHiddenViews = true
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            panelSelector.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            controlsStack.widthAnchor.constraint(equalToConstant: UI.controlsContentWidth),
            settingsStack.widthAnchor.constraint(equalToConstant: UI.preferencesContentWidth),
            levelMeter.widthAnchor.constraint(equalToConstant: UI.controlsContentWidth),
            mediaRow.widthAnchor.constraint(equalToConstant: UI.controlsContentWidth),
            divider.widthAnchor.constraint(equalToConstant: UI.controlsContentWidth),
            footerRow.widthAnchor.constraint(equalToConstant: 220),
            scrollBehaviorPopup.widthAnchor.constraint(equalTo: settingsStack.widthAnchor),
            accessibilityPermissionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            automaticUpdateChecksButton.widthAnchor.constraint(equalTo: settingsStack.widthAnchor),
            automaticUpdateInstallationButton.widthAnchor.constraint(equalTo: settingsStack.widthAnchor),
            checkNowButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            downloadUpdateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            muteButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 126)
        ])

        updateVisiblePanel()
    }

    func update(volume: CGFloat, isMuted: Bool) {
        let percent = Int(round(volume * 100))
        volumeLabel.stringValue = "Volume \(percent)%"
        levelMeter.update(progress: volume)
        muteButton.title = isMuted ? "Unmute" : "Mute"
        muteButton.image = NSImage(
            systemSymbolName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            accessibilityDescription: muteButton.title
        )
    }

    func updateScrollPreference(_ preference: ScrollAxisPreference) {
        scrollBehaviorPopup.selectItem(at: preferenceIndex(for: preference))
        hintLabel.stringValue = preference.controlsHintText
        settingsDescriptionLabel.stringValue = preference.settingsDescription
    }

    func updateAutomaticUpdateChecksEnabled(_ isEnabled: Bool) {
        automaticUpdateChecksButton.state = isEnabled ? .on : .off
    }

    fileprivate func updateAccessibilityPermissionState(_ state: AccessibilityPermissionState) {
        accessibilityStatusLabel.stringValue = state.statusText
        accessibilityPermissionButton.isHidden = state == .granted
    }

    func preferredPopoverContentSize() -> NSSize {
        switch currentPanel {
        case .controls:
            return UI.controlsPanelSize
        case .preferences:
            return UI.preferencesPanelSize
        }
    }

    func updateAutomaticUpdateInstallationEnabled(_ isEnabled: Bool, checksEnabled: Bool) {
        automaticUpdateInstallationButton.state = isEnabled ? .on : .off
        automaticUpdateInstallationButton.isEnabled = checksEnabled
    }

    fileprivate func updateUpdateState(_ state: UpdateState) {
        updateStatusLabel.stringValue = state.statusText
        updatesButton.title = state.primaryActionTitle
        updatesButton.isEnabled = !state.isBusy
        checkNowButton.isEnabled = !state.isBusy
        downloadUpdateButton.isHidden = state.availableRelease == nil
        downloadUpdateButton.isEnabled = !state.isBusy
        downloadUpdateButton.title = state.primaryActionTitle == "Download Update" ? "Open Download" : "Install Update"
    }

    private func makeMediaButton(for command: MediaControlCommand) -> NSButton {
        let button = NSButton(image: NSImage(
            systemSymbolName: command.symbolName,
            accessibilityDescription: command.toolTip
        ) ?? NSImage(), target: self, action: #selector(handleMediaButton(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.imagePosition = .imageOnly
        button.tag = mediaTag(for: command)
        button.toolTip = command.toolTip
        button.contentTintColor = command == .playPause ? .controlAccentColor : .labelColor
        return button
    }

    private func updateVisiblePanel() {
        let selectedPanel = currentPanel
        controlsStack.isHidden = selectedPanel != .controls
        settingsStack.isHidden = selectedPanel != .preferences
        view.needsLayout = true
        onPopoverPanelChange?(selectedPanel)
    }

    private func preferenceIndex(for preference: ScrollAxisPreference) -> Int {
        ScrollAxisPreference.allCases.firstIndex(of: preference) ?? 0
    }

    private func selectedScrollPreference() -> ScrollAxisPreference? {
        let index = scrollBehaviorPopup.indexOfSelectedItem
        guard ScrollAxisPreference.allCases.indices.contains(index) else { return nil }
        return ScrollAxisPreference.allCases[index]
    }

    @objc private func toggleMute() {
        onToggleMute?()
    }

    @objc private func handlePanelSelection(_ sender: NSSegmentedControl) {
        updateVisiblePanel()
    }

    @objc private func handleMediaButton(_ sender: NSButton) {
        guard let command = mediaCommand(for: sender.tag) else { return }
        onMediaCommand?(command)
    }

    @objc private func handleScrollPreferenceSelection(_ sender: NSPopUpButton) {
        guard let preference = selectedScrollPreference() else { return }
        updateScrollPreference(preference)
        onScrollPreferenceChange?(preference)
    }

    @objc private func handleAutomaticUpdateChecksToggle(_ sender: NSButton) {
        onAutomaticUpdateChecksChange?(sender.state == .on)
    }

    @objc private func handleAutomaticUpdateInstallationToggle(_ sender: NSButton) {
        onAutomaticUpdateInstallationChange?(sender.state == .on)
    }

    @objc private func handleAccessibilityPermissionRequest() {
        onRequestAccessibilityPermission?()
    }

    @objc private func handleCheckForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func handleDownloadUpdate() {
        onDownloadUpdate?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }

    private func mediaTag(for command: MediaControlCommand) -> Int {
        switch command {
        case .previous:
            return 1
        case .playPause:
            return 2
        case .next:
            return 3
        }
    }

    private func mediaCommand(for tag: Int) -> MediaControlCommand? {
        switch tag {
        case 1:
            return .previous
        case 2:
            return .playPause
        case 3:
            return .next
        default:
            return nil
        }
    }
}

final class VolumeController {
    private let callbackQueue = DispatchQueue.main
    private var observedDeviceID: AudioDeviceID?
    private var observedVolumeAddresses: [AudioObjectPropertyAddress] = []
    private var onChange: (() -> Void)?
    private var isObservingDefaultOutput = false

    private lazy var defaultOutputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refreshObservedDevice()
    }

    private lazy var volumeListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.onChange?()
    }

    deinit {
        stopObserving()
    }

    func startObserving(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
        addDefaultOutputListenerIfNeeded()
        refreshObservedDevice()
    }

    func stopObserving() {
        removeDefaultOutputListener()
        removeVolumeListeners(from: observedDeviceID, addresses: observedVolumeAddresses)
        observedVolumeAddresses = []
        observedDeviceID = nil
        onChange = nil
    }

    func changeVolume(by delta: Float32) {
        guard abs(delta) >= 0.001, let current = volume else { return }
        setVolume(to: current + delta)
    }

    func setVolume(to newValue: Float32) {
        guard let deviceID = observedDeviceID ?? defaultOutputDeviceID() else { return }

        var value = min(max(newValue, 0), 1)
        let addresses = observedVolumeAddresses.isEmpty ? volumeAddresses(for: deviceID) : observedVolumeAddresses

        for var address in addresses {
            AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout.size(ofValue: value)),
                &value
            )
        }
    }

    var volume: Float32? {
        guard let deviceID = observedDeviceID ?? defaultOutputDeviceID() else { return nil }
        return readVolume(from: deviceID)
    }

    private func refreshObservedDevice() {
        let newDeviceID = defaultOutputDeviceID()
        let newAddresses = newDeviceID.map(volumeAddresses(for:)) ?? []

        guard
            newDeviceID != observedDeviceID ||
            !haveSameSelectors(observedVolumeAddresses, newAddresses)
        else {
            onChange?()
            return
        }

        removeVolumeListeners(from: observedDeviceID, addresses: observedVolumeAddresses)
        observedDeviceID = newDeviceID
        observedVolumeAddresses = newAddresses
        addVolumeListeners(to: newDeviceID, addresses: newAddresses)
        onChange?()
    }

    private func readVolume(from deviceID: AudioDeviceID) -> Float32? {
        let addresses = observedVolumeAddresses.isEmpty ? volumeAddresses(for: deviceID) : observedVolumeAddresses
        guard !addresses.isEmpty else { return nil }

        let values = addresses.compactMap { address -> Float32? in
            var address = address
            var value = Float32.zero
            var size = UInt32(MemoryLayout.size(ofValue: value))

            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
            return status == noErr ? value : nil
        }

        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total / Float32(values.count)
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = Self.defaultOutputAddress
        var deviceID = AudioDeviceID.zero
        var size = UInt32(MemoryLayout.size(ofValue: deviceID))

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private func addDefaultOutputListenerIfNeeded() {
        guard !isObservingDefaultOutput else { return }

        var address = Self.defaultOutputAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            callbackQueue,
            defaultOutputListener
        )

        isObservingDefaultOutput = (status == noErr)
    }

    private func removeDefaultOutputListener() {
        guard isObservingDefaultOutput else { return }

        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            callbackQueue,
            defaultOutputListener
        )

        isObservingDefaultOutput = false
    }

    private func addVolumeListeners(to deviceID: AudioDeviceID?, addresses: [AudioObjectPropertyAddress]) {
        guard let deviceID else { return }

        for var address in addresses {
            AudioObjectAddPropertyListenerBlock(deviceID, &address, callbackQueue, volumeListener)
        }
    }

    private func removeVolumeListeners(from deviceID: AudioDeviceID?, addresses: [AudioObjectPropertyAddress]) {
        guard let deviceID else { return }

        for var address in addresses {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, callbackQueue, volumeListener)
        }
    }

    private func volumeAddresses(for deviceID: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        var mainAddress = Self.virtualMainVolumeAddress
        if AudioObjectHasProperty(deviceID, &mainAddress) {
            return [mainAddress]
        }

        let channels: [AudioObjectPropertyElement] = [1, 2]

        return channels.compactMap { channel in
            var address = Self.channelVolumeAddress(element: channel)
            return AudioObjectHasProperty(deviceID, &address) ? address : nil
        }
    }

    private func haveSameSelectors(_ lhs: [AudioObjectPropertyAddress], _ rhs: [AudioObjectPropertyAddress]) -> Bool {
        guard lhs.count == rhs.count else { return false }

        return zip(lhs, rhs).allSatisfy { left, right in
            left.mSelector == right.mSelector &&
            left.mScope == right.mScope &&
            left.mElement == right.mElement
        }
    }

    private static let virtualMainVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func channelVolumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let updatePromptSuppressionDelay: TimeInterval = 1.0

    private enum UI {
        static let baseItemWidth = 24.0
        static let baseBarWidth = 14.0
        static let baseBarHeight = 2.5
        static let baseBarYOffset = 2.0
        static let baseSymbolPointSize = 13.0
        static let animationDuration = 0.14
    }

    private let volumeController = VolumeController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: UI.baseItemWidth)
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let tickLayer = CALayer()
    private let controlsPopover = NSPopover()
    private let controlsViewController = MediaControlsViewController()
    private let repository = GitHubRepositoryConfiguration.load()
    private let updateChecker = GitHubUpdateChecker()
    private let selfUpdater = SelfUpdater()

    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var lastRenderedVolume: CGFloat = -1
    private var lastButtonBounds = CGRect.zero
    private var lastAudibleVolume: Float32 = 0.35
    private var scrollAxisPreference = AppPreferences.loadScrollAxisPreference()
    private let statusItemScale = AppPreferences.statusItemScale
    private var automaticUpdateChecksEnabled = AppPreferences.loadAutomaticUpdateChecksEnabled()
    private var automaticUpdateInstallationEnabled =
        AppPreferences.loadAutomaticUpdateChecksEnabled() &&
        AppPreferences.loadAutomaticUpdateInstallationEnabled()
    private var updateState = UpdateState.idle(currentVersion: AppDelegate.currentAppVersion())
    private var hasPresentedUpdateAlertThisRun = false
    private var accessibilityPermissionState: AccessibilityPermissionState = .denied

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupControlsPopover()
        installScrollMonitoring()
        refreshAccessibilityPermissionState()
        refreshUpdateUI()
        volumeController.startObserving { [weak self] in
            self?.refreshUI(animated: true)
        }
        refreshUI()

        if automaticUpdateChecksEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.updatePromptSuppressionDelay) { [weak self] in
                self?.performUpdateCheck(userInitiated: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        volumeController.stopObserving()

        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
        }

        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }

        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleControlsPopover() {
        guard let button = statusItem.button else { return }

        if controlsPopover.isShown {
            controlsPopover.performClose(nil)
            return
        }

        refreshUI()
        applyPopoverPanelSize()
        controlsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.imagePosition = .imageOnly
        button.toolTip = "Scroll to change volume. Click for mute and media controls."
        button.imageScaling = .scaleProportionallyUpOrDown
        button.wantsLayer = true
        button.target = self
        button.action = #selector(toggleControlsPopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        configureIndicator(in: button)
        applyStatusItemScale()
    }

    private func setupControlsPopover() {
        controlsViewController.onToggleMute = { [weak self] in
            self?.toggleMute()
        }
        controlsViewController.onMediaCommand = { [weak self] command in
            self?.sendMediaCommand(command)
        }
        controlsViewController.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }
        controlsViewController.onDownloadUpdate = { [weak self] in
            self?.performAvailableUpdateAction()
        }
        controlsViewController.onQuit = { [weak self] in
            self?.quit()
        }
        controlsViewController.onScrollPreferenceChange = { [weak self] preference in
            self?.setScrollAxisPreference(preference)
        }
        controlsViewController.onAutomaticUpdateChecksChange = { [weak self] isEnabled in
            self?.setAutomaticUpdateChecksEnabled(isEnabled)
        }
        controlsViewController.onAutomaticUpdateInstallationChange = { [weak self] isEnabled in
            self?.setAutomaticUpdateInstallationEnabled(isEnabled)
        }
        controlsViewController.onPopoverPanelChange = { [weak self] _ in
            self?.applyPopoverPanelSize()
        }
        controlsViewController.onRequestAccessibilityPermission = { [weak self] in
            self?.requestAccessibilityPermission()
        }
        controlsViewController.updateScrollPreference(scrollAxisPreference)
        controlsViewController.updateAccessibilityPermissionState(accessibilityPermissionState)
        controlsViewController.updateAutomaticUpdateChecksEnabled(automaticUpdateChecksEnabled)
        controlsViewController.updateAutomaticUpdateInstallationEnabled(
            automaticUpdateInstallationEnabled,
            checksEnabled: automaticUpdateChecksEnabled
        )
        controlsViewController.updateUpdateState(updateState)

        controlsPopover.animates = true
        controlsPopover.behavior = .transient
        controlsPopover.contentViewController = controlsViewController
        applyPopoverPanelSize()
    }

    private func checkForUpdates() {
        if updateState.availableRelease != nil {
            performAvailableUpdateAction()
            return
        }

        performUpdateCheck(userInitiated: true)
    }

    private func downloadLatestUpdate() {
        let targetURL = updateState.availableRelease?.preferredDownloadURL ?? repository.releasesURL
        NSWorkspace.shared.open(targetURL)
    }

    private func performAvailableUpdateAction() {
        guard let release = updateState.availableRelease else {
            downloadLatestUpdate()
            return
        }

        if release.preferredInstallAsset == nil {
            downloadLatestUpdate()
        } else {
            beginInstallingUpdate(release: release)
        }
    }

    private func installScrollMonitoring() {
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            _ = self?.handleScroll(event)
        }

        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event) ? nil : event
        }

        let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] _ in
            self?.closePopoverIfNeededForOutsideInteraction()
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
            self?.closePopoverIfNeededForOutsideInteraction()
            return event
        }
    }

    @discardableResult
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard isPointerInInteractiveArea() else { return false }
        guard let delta = volumeDelta(for: event) else { return false }
        volumeController.changeVolume(by: delta)
        refreshUI(animated: true)
        return true
    }

    private func volumeDelta(for event: NSEvent) -> Float32? {
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: event.scrollingDeltaX,
            scrollingDeltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            momentumPhaseIsEmpty: event.momentumPhase.isEmpty,
            axisPreference: scrollAxisPreference
        )
    }

    private func setScrollAxisPreference(_ preference: ScrollAxisPreference) {
        scrollAxisPreference = preference
        AppPreferences.saveScrollAxisPreference(preference)
        controlsViewController.updateScrollPreference(preference)
    }

    private func setAutomaticUpdateChecksEnabled(_ isEnabled: Bool) {
        automaticUpdateChecksEnabled = isEnabled
        AppPreferences.saveAutomaticUpdateChecksEnabled(isEnabled)
        controlsViewController.updateAutomaticUpdateChecksEnabled(isEnabled)

        if !isEnabled {
            setAutomaticUpdateInstallationEnabled(false)
        } else {
            controlsViewController.updateAutomaticUpdateInstallationEnabled(
                automaticUpdateInstallationEnabled,
                checksEnabled: automaticUpdateChecksEnabled
            )
        }
    }

    private func setAutomaticUpdateInstallationEnabled(_ isEnabled: Bool) {
        automaticUpdateInstallationEnabled = isEnabled && automaticUpdateChecksEnabled
        AppPreferences.saveAutomaticUpdateInstallationEnabled(automaticUpdateInstallationEnabled)
        controlsViewController.updateAutomaticUpdateInstallationEnabled(
            automaticUpdateInstallationEnabled,
            checksEnabled: automaticUpdateChecksEnabled
        )
    }

    private func isPointerInInteractiveArea() -> Bool {
        let mouseLocation = NSEvent.mouseLocation

        if statusItemFrame()?.contains(mouseLocation) == true {
            return true
        }

        if controlsPopover.isShown,
           let popoverFrame = controlsViewController.view.window?.frame,
           popoverFrame.insetBy(dx: -6, dy: -6).contains(mouseLocation) {
            return true
        }

        return false
    }

    private func isPointInsidePopoverOrStatusItem(_ location: CGPoint) -> Bool {
        if statusItemFrame()?.contains(location) == true {
            return true
        }

        if controlsPopover.isShown,
           let popoverFrame = controlsViewController.view.window?.frame,
           popoverFrame.insetBy(dx: -6, dy: -6).contains(location) {
            return true
        }

        return false
    }

    private func closePopoverIfNeededForOutsideInteraction() {
        guard controlsPopover.isShown else { return }
        let mouseLocation = NSEvent.mouseLocation

        if !isPointInsidePopoverOrStatusItem(mouseLocation) {
            controlsPopover.performClose(nil)
        }
    }

    private func statusItemFrame() -> CGRect? {
        guard
            let button = statusItem.button,
            let window = button.window
        else {
            return nil
        }

        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    private func refreshUI(animated: Bool = false) {
        let volume = CGFloat(volumeController.volume ?? 0)
        let isMuted = volume <= 0.001

        if !isMuted {
            lastAudibleVolume = Float32(volume)
        }

        statusItem.button?.image = speakerImage(for: volume)
        updateIndicator(for: volume, animated: animated)
        controlsViewController.update(volume: volume, isMuted: isMuted)
    }

    private func refreshUpdateUI() {
        controlsViewController.updateUpdateState(updateState)
    }

    private func refreshAccessibilityPermissionState() {
        accessibilityPermissionState = isAccessibilityPermissionGranted() ? .granted : .denied
        controlsViewController.updateAccessibilityPermissionState(accessibilityPermissionState)
    }

    private func isAccessibilityPermissionGranted() -> Bool {
        AXIsProcessTrusted()
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAccessibilityPermissionState()
    }

    private func performUpdateCheck(userInitiated: Bool) {
        let currentVersion = updateState.currentVersion
        updateState = .checking(currentVersion: currentVersion)
        refreshUpdateUI()

        updateChecker.checkForUpdates(currentVersion: currentVersion) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(.upToDate):
                self.updateState = .upToDate(currentVersion: currentVersion)
                self.refreshUpdateUI()

                if userInitiated {
                    self.presentUpToDateAlert(for: currentVersion)
                }
            case let .success(.available(release)):
                self.updateState = .available(currentVersion: currentVersion, release: release)
                self.refreshUpdateUI()

                if self.automaticUpdateInstallationEnabled && !userInitiated {
                    self.beginInstallingUpdate(release: release)
                } else if userInitiated || !self.hasPresentedUpdateAlertThisRun {
                    self.presentAvailableUpdateAlert(release: release)
                    self.hasPresentedUpdateAlertThisRun = true
                }
            case let .failure(error):
                let message = error.localizedDescription.isEmpty ? "GitHub update check failed." : error.localizedDescription
                self.updateState = .failed(currentVersion: currentVersion, message: message)
                self.refreshUpdateUI()

                if userInitiated {
                    self.presentUpdateCheckFailureAlert(message: message)
                }
            }
        }
    }

    private func beginInstallingUpdate(release: GitHubRelease) {
        let currentVersion = updateState.currentVersion
        updateState = .installing(currentVersion: currentVersion, release: release, message: "Starting...")
        refreshUpdateUI()

        selfUpdater.install(
            release: release,
            replacing: Bundle.main.bundleURL,
            progress: { [weak self] message in
                guard let self else { return }
                self.updateState = .installing(currentVersion: currentVersion, release: release, message: message)
                self.refreshUpdateUI()
            },
            completion: { [weak self] result in
                guard let self else { return }

                switch result {
                case .success:
                    self.presentInstallationStartingAlert(version: release.displayVersion)
                case let .failure(error):
                    let message = error.localizedDescription.isEmpty ? "HoverVolume could not install the update." : error.localizedDescription
                    self.updateState = .available(currentVersion: currentVersion, release: release)
                    self.refreshUpdateUI()
                    self.presentUpdateInstallFailureAlert(message: message, release: release)
                }
            }
        )
    }

    private func presentUpToDateAlert(for version: String) {
        let alert = NSAlert()
        alert.messageText = "HoverVolume is up to date"
        alert.informativeText = "Version \(version) matches the latest GitHub release."
        alert.addButton(withTitle: "OK")
        presentAlert(alert)
    }

    private func presentAvailableUpdateAlert(release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "HoverVolume \(release.displayVersion) is available on GitHub."
        alert.addButton(withTitle: release.preferredInstallAsset == nil ? "Download Update" : "Install Update")
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")

        switch presentAlert(alert) {
        case .alertFirstButtonReturn:
            if release.preferredInstallAsset == nil {
                NSWorkspace.shared.open(release.preferredDownloadURL)
            } else {
                beginInstallingUpdate(release: release)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.htmlURL)
        default:
            break
        }
    }

    private func presentUpdateCheckFailureAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "OK")

        if presentAlert(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(repository.releasesURL)
        }
    }

    private func presentInstallationStartingAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "Installing Update"
        alert.informativeText = "HoverVolume \(version) has been staged. The app will quit, replace itself, and relaunch."
        alert.addButton(withTitle: "Continue")
        _ = presentAlert(alert)
        NSApp.terminate(nil)
    }

    private func presentUpdateInstallFailureAlert(message: String, release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "Update Install Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "Open Release")
        alert.addButton(withTitle: "OK")

        if presentAlert(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.preferredDownloadURL)
        }
    }

    private func presentAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Needed"
        alert.informativeText = "HoverVolume needs Accessibility access to send media transport commands like play, pause, next, and previous."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if presentAlert(alert) == .alertFirstButtonReturn {
            requestAccessibilityPermission()
        }
    }

    private func presentAutomationPermissionAlert(for application: ScriptableMediaApplication) {
        let alert = NSAlert()
        alert.messageText = "Automation Permission Needed"
        alert.informativeText = "HoverVolume needs permission to control \(application.appName). Allow HoverVolume under System Settings > Privacy & Security > Automation, then try the media buttons again."
        alert.addButton(withTitle: "OK")
        _ = presentAlert(alert)
    }

    @discardableResult
    private func presentAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    func applicationDidResignActive(_ notification: Notification) {
        controlsPopover.performClose(nil)
    }

    private func toggleMute() {
        guard let currentVolume = volumeController.volume else { return }

        if currentVolume > 0.001 {
            lastAudibleVolume = currentVolume
            volumeController.setVolume(to: 0)
        } else {
            volumeController.setVolume(to: max(lastAudibleVolume, 0.05))
        }

        refreshUI(animated: true)
    }

    private func sendMediaCommand(_ command: MediaControlCommand) {
        if let scriptResult = sendScriptableMediaCommand(command) {
            switch scriptResult {
            case .handled:
                return
            case let .automationDenied(application):
                presentAutomationPermissionAlert(for: application)
                return
            case .notAvailable:
                break
            }
        }

        refreshAccessibilityPermissionState()

        guard accessibilityPermissionState == .granted else {
            presentAccessibilityPermissionAlert()
            return
        }

        postMediaKey(command.mediaKey)
    }

    private enum ScriptedMediaCommandResult {
        case handled
        case automationDenied(ScriptableMediaApplication)
        case notAvailable
    }

    private func sendScriptableMediaCommand(_ command: MediaControlCommand) -> ScriptedMediaCommandResult? {
        guard let application = preferredScriptableMediaApplication() else {
            return .notAvailable
        }

        let source = application.appleScript(for: command)
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&errorInfo)

        if let errorInfo,
           let errorCode = errorInfo[NSAppleScript.errorNumber] as? Int {
            if errorCode == -1743 {
                return .automationDenied(application)
            }

            return .notAvailable
        }

        return .handled
    }

    private func preferredScriptableMediaApplication() -> ScriptableMediaApplication? {
        let runningApplications = NSWorkspace.shared.runningApplications

        if let frontmost = runningApplications.first(where: \.isActive),
           let application = ScriptableMediaApplication.allCases.first(where: { $0.bundleIdentifier == frontmost.bundleIdentifier }) {
            return application
        }

        for application in ScriptableMediaApplication.allCases {
            if runningApplications.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }) {
                return application
            }
        }

        return nil
    }

    private func postMediaKey(_ key: Int32) {
        for (isKeyDown, data2) in [(true, -1), (false, 0)] {
            let keyState = isKeyDown ? 0xA : 0xB
            let data1 = Int((key << 16) | (Int32(keyState) << 8))

            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: data2
            ) else {
                continue
            }

            NSApp.postEvent(event, atStart: false)

            guard let cgEvent = event.cgEvent else { continue }
            cgEvent.post(tap: .cghidEventTap)
            cgEvent.post(tap: .cgSessionEventTap)

            if isKeyDown {
                usleep(12000)
            }
        }
    }

    private func configureIndicator(in button: NSStatusBarButton) {
        guard let rootLayer = button.layer else { return }

        trackLayer.cornerRadius = barHeight / 2
        fillLayer.cornerRadius = barHeight / 2
        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        tickLayer.contentsScale = 2
        tickLayer.opacity = 0.7

        rootLayer.addSublayer(trackLayer)
        rootLayer.addSublayer(fillLayer)
        rootLayer.addSublayer(tickLayer)
    }

    private func updateIndicator(for volume: CGFloat, animated: Bool) {
        guard let button = statusItem.button else { return }

        layoutIndicatorIfNeeded(in: button.bounds)
        applyIndicatorColors()

        let targetWidth = trackLayer.bounds.width * volume

        if animated && lastRenderedVolume >= 0 {
            let animation = CABasicAnimation(keyPath: "bounds.size.width")
            animation.fromValue = fillLayer.presentation()?.bounds.width ?? fillLayer.bounds.width
            animation.toValue = targetWidth
            animation.duration = UI.animationDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fillLayer.add(animation, forKey: "volumeWidth")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: targetWidth, height: barHeight)
        fillLayer.position = CGPoint(x: trackLayer.frame.minX, y: trackLayer.frame.midY)
        CATransaction.commit()

        lastRenderedVolume = volume
    }

    private func layoutIndicatorIfNeeded(in bounds: CGRect) {
        guard bounds != lastButtonBounds else { return }

        let x = floor((bounds.width - barWidth) / 2)
        let frame = CGRect(x: x, y: barYOffset, width: barWidth, height: barHeight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = frame
        fillLayer.bounds = CGRect(x: 0, y: 0, width: fillLayer.bounds.width, height: barHeight)
        fillLayer.position = CGPoint(x: frame.minX, y: frame.midY)
        tickLayer.frame = frame
        CATransaction.commit()

        lastButtonBounds = bounds
    }

    private func applyIndicatorColors() {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let trackColor = isDark ? NSColor.white.withAlphaComponent(0.28) : NSColor.black.withAlphaComponent(0.16)
        let tickColor = isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.12)

        trackLayer.backgroundColor = trackColor.cgColor
        fillLayer.backgroundColor = NSColor.controlAccentColor.cgColor
        tickLayer.contents = Self.makeTickPatternImage(width: 36, height: 6, color: tickColor)
    }

    private func speakerImage(for volume: CGFloat) -> NSImage? {
        let symbolName = HoverVolumeLogic.speakerSymbolName(for: volume)
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Volume"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func applyStatusItemScale() {
        statusItem.length = itemWidth
        lastButtonBounds = .zero

        guard let button = statusItem.button else { return }
        button.needsLayout = true
        trackLayer.cornerRadius = barHeight / 2
        fillLayer.cornerRadius = barHeight / 2
        refreshUI(animated: false)
    }

    private func applyPopoverPanelSize() {
        let size = controlsViewController.preferredPopoverContentSize()
        controlsViewController.preferredContentSize = size
        controlsPopover.contentSize = size
    }

    private var itemWidth: CGFloat {
        UI.baseItemWidth * statusItemScale
    }

    private var barWidth: CGFloat {
        UI.baseBarWidth * statusItemScale
    }

    private var barHeight: CGFloat {
        max(2, UI.baseBarHeight * statusItemScale)
    }

    private var barYOffset: CGFloat {
        UI.baseBarYOffset * statusItemScale
    }

    private var symbolPointSize: CGFloat {
        UI.baseSymbolPointSize * statusItemScale
    }

    private static func makeTickPatternImage(width: Int, height: Int, color: NSColor) -> CGImage? {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false, drawingHandler: { rect in
            NSColor.clear.setFill()
            rect.fill()

            color.setFill()
            let path = NSBezierPath()
            let step = max(4, width / 6)

            for x in stride(from: step, to: width, by: step) {
                path.appendRect(NSRect(x: x, y: 0, width: 1, height: height))
            }

            path.fill()
            return true
        })

        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func currentAppVersion() -> String {
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return bundleVersion ?? "0.0.0"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

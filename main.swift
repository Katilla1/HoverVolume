import AppKit
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
            return NX_KEYTYPE_REWIND
        case .playPause:
            return NX_KEYTYPE_PLAY
        case .next:
            return NX_KEYTYPE_FAST
        }
    }
}

final class MediaControlsViewController: NSViewController {
    var onToggleMute: (() -> Void)?
    var onMediaCommand: ((MediaControlCommand) -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    private let volumeLabel = NSTextField(labelWithString: "Volume 0%")
    private let hintLabel = NSTextField(labelWithString: "Scroll on the icon or here to change volume")
    private let muteButton = NSButton(title: "Mute", target: nil, action: nil)
    private let updatesButton = NSButton(title: "Check for Updates", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit HoverVolume", target: nil, action: nil)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 148))
        view.translatesAutoresizingMaskIntoConstraints = false

        volumeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        volumeLabel.alignment = .center

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2

        muteButton.bezelStyle = .rounded
        muteButton.controlSize = .small
        muteButton.target = self
        muteButton.action = #selector(toggleMute)
        muteButton.imagePosition = .imageLeading

        updatesButton.bezelStyle = .rounded
        updatesButton.controlSize = .small
        updatesButton.target = self
        updatesButton.action = #selector(handleCheckForUpdates)

        quitButton.bezelStyle = .inline
        quitButton.controlSize = .small
        quitButton.target = self
        quitButton.action = #selector(handleQuit)

        let previousButton = makeMediaButton(for: .previous)
        let playPauseButton = makeMediaButton(for: .playPause)
        let nextButton = makeMediaButton(for: .next)

        let mediaRow = NSStackView(views: [previousButton, playPauseButton, nextButton])
        mediaRow.orientation = .horizontal
        mediaRow.alignment = .centerY
        mediaRow.distribution = .fillEqually
        mediaRow.spacing = 8

        let stack = NSStackView(views: [volumeLabel, muteButton, mediaRow, hintLabel, updatesButton, quitButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            mediaRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            muteButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
    }

    func update(volume: CGFloat, isMuted: Bool) {
        let percent = Int(round(volume * 100))
        volumeLabel.stringValue = "Volume \(percent)%"
        muteButton.title = isMuted ? "Unmute" : "Mute"
        muteButton.image = NSImage(
            systemSymbolName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            accessibilityDescription: muteButton.title
        )
    }

    private func makeMediaButton(for command: MediaControlCommand) -> NSButton {
        let button = NSButton(image: NSImage(
            systemSymbolName: command.symbolName,
            accessibilityDescription: command.toolTip
        ) ?? NSImage(), target: self, action: #selector(handleMediaButton(_:)))
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.imagePosition = .imageOnly
        button.tag = mediaTag(for: command)
        button.toolTip = command.toolTip
        return button
    }

    @objc private func toggleMute() {
        onToggleMute?()
    }

    @objc private func handleMediaButton(_ sender: NSButton) {
        guard let command = mediaCommand(for: sender.tag) else { return }
        onMediaCommand?(command)
    }

    @objc private func handleCheckForUpdates() {
        onCheckForUpdates?()
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
    private static let releasesURL = URL(string: "https://github.com/Katilla1/HoverVolume/releases/latest")!

    private enum UI {
        static let itemWidth = 28.0
        static let barWidth = 18.0
        static let barHeight = 3.0
        static let barYOffset = 2.5
        static let animationDuration = 0.14
        static let fillColor = NSColor.systemGreen
    }

    private let volumeController = VolumeController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: UI.itemWidth)
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let tickLayer = CALayer()
    private let tickImage = AppDelegate.makeTickPatternImage(width: 36, height: 6)
    private let controlsPopover = NSPopover()
    private let controlsViewController = MediaControlsViewController()

    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var lastRenderedVolume: CGFloat = -1
    private var lastButtonBounds = CGRect.zero
    private var lastAudibleVolume: Float32 = 0.35

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupControlsPopover()
        installScrollMonitoring()
        volumeController.startObserving { [weak self] in
            self?.refreshUI(animated: true)
        }
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        volumeController.stopObserving()

        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
        }

        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
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
        controlsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.imagePosition = .imageOnly
        button.toolTip = "Scroll to change volume. Click for mute and media controls."
        button.wantsLayer = true
        button.target = self
        button.action = #selector(toggleControlsPopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        configureIndicator(in: button)
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
        controlsViewController.onQuit = { [weak self] in
            self?.quit()
        }

        controlsPopover.animates = true
        controlsPopover.behavior = .transient
        controlsPopover.contentViewController = controlsViewController
        controlsPopover.contentSize = NSSize(width: 232, height: 148)
    }

    private func checkForUpdates() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    private func installScrollMonitoring() {
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            _ = self?.handleScroll(event)
        }

        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event) ? nil : event
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
            momentumPhaseIsEmpty: event.momentumPhase.isEmpty
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
        postMediaKey(command.mediaKey)
    }

    private func postMediaKey(_ key: Int32) {
        for isKeyDown in [true, false] {
            let keyState = isKeyDown ? 0xA : 0xB
            let data1 = Int((key << 16) | (Int32(keyState) << 8))

            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )?.cgEvent else {
                continue
            }

            event.post(tap: .cghidEventTap)
        }
    }

    private func configureIndicator(in button: NSStatusBarButton) {
        guard let rootLayer = button.layer else { return }

        trackLayer.cornerRadius = UI.barHeight / 2
        fillLayer.cornerRadius = UI.barHeight / 2
        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        tickLayer.contents = tickImage
        tickLayer.contentsScale = 2
        tickLayer.opacity = 0.55

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
        fillLayer.bounds = CGRect(x: 0, y: 0, width: targetWidth, height: UI.barHeight)
        fillLayer.position = CGPoint(x: trackLayer.frame.minX, y: trackLayer.frame.midY)
        CATransaction.commit()

        lastRenderedVolume = volume
    }

    private func layoutIndicatorIfNeeded(in bounds: CGRect) {
        guard bounds != lastButtonBounds else { return }

        let x = floor((bounds.width - UI.barWidth) / 2)
        let frame = CGRect(x: x, y: UI.barYOffset, width: UI.barWidth, height: UI.barHeight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = frame
        fillLayer.bounds = CGRect(x: 0, y: 0, width: fillLayer.bounds.width, height: UI.barHeight)
        fillLayer.position = CGPoint(x: frame.minX, y: frame.midY)
        tickLayer.frame = frame
        CATransaction.commit()

        lastButtonBounds = bounds
    }

    private func applyIndicatorColors() {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let trackColor = isDark ? NSColor.white.withAlphaComponent(0.28) : NSColor.black.withAlphaComponent(0.18)

        trackLayer.backgroundColor = trackColor.cgColor
        fillLayer.backgroundColor = UI.fillColor.cgColor
    }

    private func speakerImage(for volume: CGFloat) -> NSImage? {
        let symbolName = HoverVolumeLogic.speakerSymbolName(for: volume)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Volume")
        image?.isTemplate = true
        return image
    }

    private static func makeTickPatternImage(width: Int, height: Int) -> CGImage? {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false, drawingHandler: { rect in
            NSColor.clear.setFill()
            rect.fill()

            NSColor.white.withAlphaComponent(0.22).setFill()
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

import AppKit
import AudioToolbox
import CoreAudio
import QuartzCore

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
        setVolume(current + delta)
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

    private func setVolume(_ newValue: Float32) {
        guard let deviceID = observedDeviceID ?? defaultOutputDeviceID() else { return }

        var value = min(max(newValue, 0), 1)
        let addresses = observedVolumeAddresses.isEmpty ? volumeAddresses(for: deviceID) : observedVolumeAddresses

        for var address in addresses {
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value)
        }
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

        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum UI {
        static let itemWidth = 28.0
        static let barWidth = 18.0
        static let barHeight = 3.0
        static let barYOffset = 2.5
        static let animationDuration = 0.14
        static let wheelStep: Float32 = 0.05
        static let trackpadDeltaScale: Float32 = 0.004
        static let maxTrackpadDeltaPerEvent: Float32 = 0.08
        static let fillColor = NSColor.systemGreen
    }

    private let volumeController = VolumeController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: UI.itemWidth)
    private let volumeMenuItem = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let tickLayer = CALayer()
    private let tickImage = AppDelegate.makeTickPatternImage(width: 36, height: 6)
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var lastRenderedVolume: CGFloat = -1
    private var lastButtonBounds = CGRect.zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
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

    func menuWillOpen(_ menu: NSMenu) {
        refreshUI()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.imagePosition = .imageOnly
        button.toolTip = "Hover and scroll to change volume"
        button.wantsLayer = true
        configureIndicator(in: button)

        let menu = NSMenu()
        menu.delegate = self
        volumeMenuItem.isEnabled = false
        menu.addItem(volumeMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit HoverVolume", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
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
        guard isMouseOverStatusItem() else { return false }
        guard let delta = volumeDelta(for: event) else { return false }
        volumeController.changeVolume(by: delta)
        refreshUI(animated: true)
        return true
    }

    private func volumeDelta(for event: NSEvent) -> Float32? {
        guard abs(event.scrollingDeltaY) >= 0.01 else { return nil }
        guard event.momentumPhase.isEmpty else { return nil }

        if event.hasPreciseScrollingDeltas {
            let scaled = Float32(event.scrollingDeltaY) * UI.trackpadDeltaScale
            return max(-UI.maxTrackpadDeltaPerEvent, min(UI.maxTrackpadDeltaPerEvent, scaled))
        }

        return event.scrollingDeltaY > 0 ? UI.wheelStep : -UI.wheelStep
    }

    private func isMouseOverStatusItem() -> Bool {
        guard
            let button = statusItem.button,
            let window = button.window
        else {
            return false
        }

        let frameInWindow = button.convert(button.bounds, to: nil)
        let frameOnScreen = window.convertToScreen(frameInWindow)
        return frameOnScreen.contains(NSEvent.mouseLocation)
    }

    private func refreshUI(animated: Bool = false) {
        let volume = CGFloat(volumeController.volume ?? 0)
        let percent = Int(round(volume * 100))
        volumeMenuItem.title = "Volume \(percent)%"
        statusItem.button?.image = speakerImage(for: volume)
        updateIndicator(for: volume, animated: animated)
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
        let symbolName: String

        switch volume {
        case 0:
            symbolName = "speaker.slash.fill"
        case 0..<0.34:
            symbolName = "speaker.fill"
        case 0.34..<0.67:
            symbolName = "speaker.wave.2.fill"
        default:
            symbolName = "speaker.wave.3.fill"
        }

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

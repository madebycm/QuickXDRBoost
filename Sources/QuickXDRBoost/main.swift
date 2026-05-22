import AppKit
import CoreGraphics
import IOKit
import MetalKit
import ServiceManagement

private let bundleId = "local.quickxdrboost"
private let repoURL = URL(string: "https://github.com/madebycm/QuickXDRBoost")!
private let supportedDevices: Set<String> = [
    "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
    "Mac14,6", "Mac14,10", "Mac14,5", "Mac14,9",
    "Mac15,7", "Mac15,9", "Mac15,11", "Mac15,6", "Mac15,8", "Mac15,10", "Mac15,3",
    "Mac16,1", "Mac16,6", "Mac16,8", "Mac16,7", "Mac16,5",
    "Mac17,2", "Mac17,6", "Mac17,8", "Mac17,7", "Mac17,9",
]
private let sdr600NitsDevices: Set<String> = [
    "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11",
    "Mac16,1", "Mac16,6", "Mac16,8", "Mac16,7", "Mac16,5",
    "Mac17,2", "Mac17,6", "Mac17,8", "Mac17,7", "Mac17,9",
]
private let externalXDRDisplays: Set<String> = ["Pro Display XDR", "Studio Display XDR"]

private extension NSScreen {
    var displayId: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}

private func modelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    guard let data = IORegistryEntryCreateCFProperty(
        service,
        "model" as CFString,
        kCFAllocatorDefault,
        0
    )?.takeRetainedValue() as? Data else {
        return nil
    }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
}

private func isBuiltIn(_ screen: NSScreen) -> Bool {
    guard let displayId = screen.displayId else { return false }
    return CGDisplayIsBuiltin(displayId) != 0
}

private func deviceMaxBrightness() -> Float {
    guard let model = modelIdentifier() else { return 1.59 }
    return sdr600NitsDevices.contains(model) ? 1.535 : 1.59
}

private func refGamma(for screen: NSScreen) -> Float {
    isBuiltIn(screen) ? deviceMaxBrightness() : 1.6
}

private func supportedScreens() -> [NSScreen] {
    let modelSupported = modelIdentifier().map { supportedDevices.contains($0) } ?? false
    return NSScreen.screens.filter { screen in
        (isBuiltIn(screen) && modelSupported) || externalXDRDisplays.contains(screen.localizedName)
    }
}

private final class GammaTable {
    static let size: UInt32 = 256
    private var red = [CGGammaValue](repeating: 0, count: Int(size))
    private var green = [CGGammaValue](repeating: 0, count: Int(size))
    private var blue = [CGGammaValue](repeating: 0, count: Int(size))

    init?(displayId: CGDirectDisplayID) {
        var samples: UInt32 = 0
        let result = CGGetDisplayTransferByTable(displayId, Self.size, &red, &green, &blue, &samples)
        guard result == .success else { return nil }
    }

    func apply(displayId: CGDirectDisplayID, boostFactor: Float, whitePointGamma: Double) {
        var r = red
        var g = green
        var b = blue
        for index in r.indices {
            r[index] = powf(r[index], Float(whitePointGamma)) * boostFactor
            g[index] = powf(g[index], Float(whitePointGamma)) * boostFactor
            b[index] = powf(b[index], Float(whitePointGamma)) * boostFactor
        }
        CGSetDisplayTransferByTable(displayId, Self.size, &r, &g, &b)
    }

    func restore(displayId: CGDirectDisplayID) {
        apply(displayId: displayId, boostFactor: 1, whitePointGamma: 1)
    }
}

private final class OverlayView: MTKView, MTKViewDelegate {
    private var commandQueue: MTLCommandQueue?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1), device: MTLCreateSystemDefaultDevice())
        guard let device else { fatalError("No Metal device available") }
        commandQueue = device.makeCommandQueue()
        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        clearColor = MTLClearColorMake(16, 16, 16, 1)
        preferredFramesPerSecond = 5
        delegate = self

        if let layer = layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.isOpaque = false
            layer.pixelFormat = .rgba16Float
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func draw(in view: MTKView) {
        guard
            let commandQueue,
            let descriptor = currentRenderPassDescriptor,
            let drawable = currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

private final class OverlayController {
    let window: NSWindow

    init?(screen: NSScreen) {
        guard screen.displayId != nil else { return nil }
        let rect = NSRect(x: screen.frame.minX, y: screen.frame.maxY - 1, width: 1, height: 1)
        window = NSWindow(contentRect: rect, styleMask: [], backing: .buffered, defer: false)
        window.collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        window.level = .screenSaver
        window.canHide = false
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentView = OverlayView()
        window.orderFrontRegardless()
    }

    func update(screen: NSScreen) {
        window.setFrameOrigin(NSPoint(x: screen.frame.minX, y: screen.frame.maxY - 1))
        window.orderFrontRegardless()
    }
}

@MainActor
private final class BoostController {
    private var overlays: [CGDirectDisplayID: OverlayController] = [:]
    private var baselines: [CGDirectDisplayID: GammaTable] = [:]
    private var timer: Timer?
    private var enabled = true
    var brightness: Float {
        didSet {
            brightness = max(0, min(1, brightness))
            UserDefaults.standard.set(brightness, forKey: "brightness")
            refresh()
        }
    }
    var whitePointEnabled: Bool {
        didSet {
            UserDefaults.standard.set(whitePointEnabled, forKey: "whitePointEnabled")
            refresh()
        }
    }
    var whitePointIntensity: Float {
        didSet {
            whitePointIntensity = max(0, min(200, whitePointIntensity))
            UserDefaults.standard.set(whitePointIntensity, forKey: "whitePointIntensity")
            refresh()
        }
    }

    init() {
        brightness = UserDefaults.standard.object(forKey: "brightness") == nil
            ? 1
            : UserDefaults.standard.float(forKey: "brightness")
        whitePointEnabled = UserDefaults.standard.object(forKey: "whitePointEnabled") == nil
            ? false
            : UserDefaults.standard.bool(forKey: "whitePointEnabled")
        whitePointIntensity = UserDefaults.standard.object(forKey: "whitePointIntensity") == nil
            ? 100
            : UserDefaults.standard.float(forKey: "whitePointIntensity")
    }

    func start() {
        enabled = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        enabled = false
        timer?.invalidate()
        timer = nil
        restore()
    }

    private func gammaFactor(screen: NSScreen) -> Float {
        let referenceEDR: Float = 4.0
        let maxEDR = Float(screen.maximumExtendedDynamicRangeColorComponentValue)
        if brightness > 0.995 {
            return 1 + (refGamma(for: screen) - 1) * maxEDR / referenceEDR
        }
        return 1 + (refGamma(for: screen) - 1) * min(maxEDR / referenceEDR, brightness)
    }

    private var whitePointGamma: Double {
        guard whitePointEnabled else { return 1 }
        return 1 + Double(whitePointIntensity) / 100 * 0.8
    }

    private func refresh() {
        guard enabled else { return }
        let xdrScreens = supportedScreens()
        let xdrIds = Set(xdrScreens.compactMap(\.displayId))
        let gammaScreens = whitePointEnabled ? NSScreen.screens : xdrScreens
        let activeIds = Set(gammaScreens.compactMap(\.displayId))

        for id in overlays.keys where !xdrIds.contains(id) {
            overlays[id]?.window.close()
            overlays.removeValue(forKey: id)
        }

        for id in baselines.keys where !activeIds.contains(id) {
            baselines[id]?.restore(displayId: id)
            baselines.removeValue(forKey: id)
        }

        for screen in xdrScreens {
            guard let displayId = screen.displayId else { continue }
            if overlays[displayId] == nil {
                overlays[displayId] = OverlayController(screen: screen)
            } else {
                overlays[displayId]?.update(screen: screen)
            }
        }

        for screen in gammaScreens {
            guard let displayId = screen.displayId else { continue }
            if baselines[displayId] == nil {
                baselines[displayId] = GammaTable(displayId: displayId)
            }

            var boostFactor: Float = 1
            if screen.maximumExtendedDynamicRangeColorComponentValue > 1.05 {
                boostFactor = xdrIds.contains(displayId) ? gammaFactor(screen: screen) : 1
            }
            baselines[displayId]?.apply(
                displayId: displayId,
                boostFactor: boostFactor,
                whitePointGamma: whitePointGamma
            )
        }
    }

    private func restore() {
        for (id, table) in baselines {
            table.restore(displayId: id)
        }
        baselines.removeAll()
        overlays.values.forEach { $0.window.close() }
        overlays.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
}

private final class LaunchAtLoginController {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}

@MainActor
private final class MenuController: NSObject, NSApplicationDelegate {
    private let boost = BoostController()
    private let launchAtLogin = LaunchAtLoginController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let boostValueItem = NSMenuItem()
    private let boostSlider = NSSlider(value: 1, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let whitePointCheckbox = NSButton(checkboxWithTitle: "Reduce white point", target: nil, action: nil)
    private let whitePointValueItem = NSMenuItem()
    private let whitePointSlider = NSSlider(value: 100, minValue: 0, maxValue: 200, target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        terminateRunningCopies()
        configureMenu()
        boost.start()
        updateDisplay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        boost.stop()
    }

    private func configureMenu() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "QuickXDRBoost")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        boostValueItem.isEnabled = false
        menu.addItem(boostValueItem)

        boostSlider.target = self
        boostSlider.action = #selector(boostSliderChanged(_:))
        boostSlider.numberOfTickMarks = 5
        boostSlider.allowsTickMarkValuesOnly = false
        boostSlider.frame = NSRect(x: 14, y: 8, width: 220, height: 28)

        let boostSliderContainer = NSView(frame: NSRect(x: 0, y: 0, width: 248, height: 44))
        boostSliderContainer.addSubview(boostSlider)
        let boostSliderItem = NSMenuItem()
        boostSliderItem.view = boostSliderContainer
        menu.addItem(boostSliderItem)

        menu.addItem(.separator())
        whitePointCheckbox.target = self
        whitePointCheckbox.action = #selector(whitePointCheckboxChanged(_:))
        whitePointCheckbox.frame = NSRect(x: 14, y: 5, width: 220, height: 24)
        let whitePointCheckboxContainer = NSView(frame: NSRect(x: 0, y: 0, width: 248, height: 34))
        whitePointCheckboxContainer.addSubview(whitePointCheckbox)
        let whitePointCheckboxItem = NSMenuItem()
        whitePointCheckboxItem.view = whitePointCheckboxContainer
        menu.addItem(whitePointCheckboxItem)

        whitePointValueItem.isEnabled = false
        menu.addItem(whitePointValueItem)

        whitePointSlider.target = self
        whitePointSlider.action = #selector(whitePointSliderChanged(_:))
        whitePointSlider.numberOfTickMarks = 5
        whitePointSlider.allowsTickMarkValuesOnly = false
        whitePointSlider.frame = NSRect(x: 14, y: 8, width: 220, height: 28)
        let whitePointSliderContainer = NSView(frame: NSRect(x: 0, y: 0, width: 248, height: 44))
        whitePointSliderContainer.addSubview(whitePointSlider)
        let whitePointSliderItem = NSMenuItem()
        whitePointSliderItem.view = whitePointSliderContainer
        menu.addItem(whitePointSliderItem)

        menu.addItem(.separator())
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginCheckbox.frame = NSRect(x: 14, y: 5, width: 220, height: 24)
        let launchContainer = NSView(frame: NSRect(x: 0, y: 0, width: 248, height: 34))
        launchContainer.addSubview(launchAtLoginCheckbox)
        let launchItem = NSMenuItem()
        launchItem.view = launchContainer
        menu.addItem(launchItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About QuickXDRBoost", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit QuickXDRBoost", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func updateDisplay() {
        let boostPercent = Int(round(boost.brightness * 100))
        let whitePointPercent = Int(round(boost.whitePointIntensity))
        boostValueItem.title = "XDR boost: \(boostPercent)%"
        boostSlider.doubleValue = Double(boostPercent)
        whitePointCheckbox.state = boost.whitePointEnabled ? .on : .off
        whitePointValueItem.title = "White point reduction: \(whitePointPercent)%"
        whitePointSlider.doubleValue = Double(whitePointPercent)
        whitePointSlider.isEnabled = boost.whitePointEnabled
        launchAtLoginCheckbox.state = launchAtLogin.isEnabled ? .on : .off
        statusItem.button?.toolTip = "QuickXDRBoost - XDR \(boostPercent)%, white point \(whitePointPercent)%"
    }

    @objc private func boostSliderChanged(_ sender: NSSlider) {
        boost.brightness = Float(sender.doubleValue / 100)
        updateDisplay()
    }

    @objc private func whitePointCheckboxChanged(_ sender: NSButton) {
        boost.whitePointEnabled = sender.state == .on
        updateDisplay()
    }

    @objc private func whitePointSliderChanged(_ sender: NSSlider) {
        boost.whitePointIntensity = Float(sender.doubleValue)
        updateDisplay()
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        do {
            try launchAtLogin.setEnabled(sender.state == .on)
        } catch {
            sender.state = launchAtLogin.isEnabled ? .on : .off
            let alert = NSAlert()
            alert.messageText = "Could not update launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        updateDisplay()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "QuickXDRBoost"
        alert.informativeText = """
        XDR brightness boost for the macOS menu bar.

        Made by madebycm.
        \(repoURL.absoluteString)
        """
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(repoURL)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private func terminateRunningCopies() {
    let currentPid = ProcessInfo.processInfo.processIdentifier
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        where app.processIdentifier != currentPid {
        app.terminate()
    }
}

@main
private enum Main {
    @MainActor
    static func main() {
        let command = CommandLine.arguments.dropFirst().first
        if command == "off" || command == "quit" {
            terminateRunningCopies()
            CGDisplayRestoreColorSyncSettings()
            return
        }
        if command == "status" {
            let currentPid = ProcessInfo.processInfo.processIdentifier
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .contains { $0.processIdentifier != currentPid }
            print(running ? "Running" : "Stopped")
            return
        }

        let app = NSApplication.shared
        let delegate = MenuController()
        app.delegate = delegate
        app.run()
    }
}

import Cocoa

class SliderView: NSView {
    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let slider: NSSlider
    private let onValueChange: (Double) -> Void

    init(title: String, initialValue: Double, min: Double, max: Double, onChange: @escaping (Double) -> Void) {
        self.onValueChange = onChange

        self.titleLabel = NSTextField(labelWithString: title)
        self.valueLabel = NSTextField(labelWithString: String(format: "%.2fx", initialValue))
        self.slider = NSSlider(value: initialValue, minValue: min, maxValue: max, target: nil, action: nil)

        super.init(frame: NSRect(x: 0, y: 0, width: 230, height: 52))

        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        titleLabel.frame = NSRect(x: 16, y: 30, width: 140, height: 16)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        valueLabel.frame = NSRect(x: 160, y: 30, width: 54, height: 16)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.textColor = .secondaryLabelColor
        addSubview(valueLabel)

        slider.frame = NSRect(x: 14, y: 6, width: 202, height: 22)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        addSubview(slider)
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let val = sender.doubleValue
        valueLabel.stringValue = String(format: "%.2fx", val)
        onValueChange(val)
    }

    func setValue(_ val: Double) {
        slider.doubleValue = val
        valueLabel.stringValue = String(format: "%.2fx", val)
    }
}

class MenuBarApp: NSObject, NSApplicationDelegate, DeviceManagerDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var deviceManager: DeviceManager!
    private var eventInterceptor: EventInterceptor!
    private var config: MouseConfig!

    private var statusMenuItem: NSMenuItem!
    private var transportMenuItem: NSMenuItem!
    private var batteryMenuItem: NSMenuItem!

    private var tabSwitcherItem: NSMenuItem!
    private var backForwardItem: NSMenuItem!
    private var disableSideButtonsItem: NSMenuItem!
    private var invertScrollMenuItem: NSMenuItem!
    private var cursorSliderView: SliderView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        config = MouseConfig.load()
        eventInterceptor = EventInterceptor(config: config)
        let started = eventInterceptor.start()
        if !started {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options)
        }

        deviceManager = DeviceManager()
        deviceManager.delegate = self

        setupMenuBar()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = createMenuBarIcon()
            button.imagePosition = .imageOnly
        }

        menu = NSMenu()

        // Device Header
        statusMenuItem = NSMenuItem(title: "HyperX Pulsefire Haste 2 Core", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        transportMenuItem = NSMenuItem(title: "Connection: Searching...", action: nil, keyEquivalent: "")
        transportMenuItem.isEnabled = false
        menu.addItem(transportMenuItem)

        batteryMenuItem = NSMenuItem(title: "Battery: N/A", action: nil, keyEquivalent: "")
        batteryMenuItem.isEnabled = false
        menu.addItem(batteryMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Side Buttons Submenu
        let sideButtonsParent = NSMenuItem(title: "Side Buttons Action", action: nil, keyEquivalent: "")
        let sideButtonsSubmenu = NSMenu()

        tabSwitcherItem = NSMenuItem(title: "Chrome / Browser Tab Switcher", action: #selector(setSideButtonMode(_:)), keyEquivalent: "")
        tabSwitcherItem.target = self
        tabSwitcherItem.representedObject = SideButtonMode.tabs
        sideButtonsSubmenu.addItem(tabSwitcherItem)

        backForwardItem = NSMenuItem(title: "History Back / Forward", action: #selector(setSideButtonMode(_:)), keyEquivalent: "")
        backForwardItem.target = self
        backForwardItem.representedObject = SideButtonMode.navigation
        sideButtonsSubmenu.addItem(backForwardItem)

        disableSideButtonsItem = NSMenuItem(title: "Disabled (Default Mouse Buttons)", action: #selector(setSideButtonMode(_:)), keyEquivalent: "")
        disableSideButtonsItem.target = self
        disableSideButtonsItem.representedObject = SideButtonMode.disabled
        sideButtonsSubmenu.addItem(disableSideButtonsItem)

        sideButtonsParent.submenu = sideButtonsSubmenu
        menu.addItem(sideButtonsParent)

        updateSideButtonMenuState()

        // Invert Scroll
        invertScrollMenuItem = NSMenuItem(title: "Invert Scroll Wheel", action: #selector(toggleInvertScroll), keyEquivalent: "")
        invertScrollMenuItem.target = self
        invertScrollMenuItem.state = config.invertScroll ? .on : .off
        menu.addItem(invertScrollMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Cursor Acceleration / Multiplier Slider View
        let sliderContainer = NSMenuItem()
        let sliderView = SliderView(
            title: "Cursor Acceleration",
            initialValue: config.cursorMultiplier,
            min: 0.5,
            max: 3.0
        ) { [weak self] newMultiplier in
            guard let self = self else { return }
            self.config.cursorMultiplier = newMultiplier
            self.eventInterceptor.config = self.config
            self.config.save()
        }
        self.cursorSliderView = sliderView
        sliderContainer.view = sliderView
        menu.addItem(sliderContainer)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh Status", action: #selector(refreshStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openConfigItem = NSMenuItem(title: "Open Config File", action: #selector(openConfigFile), keyEquivalent: "")
        openConfigItem.target = self
        menu.addItem(openConfigItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit HyperX Driver", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        if let dev = deviceManager.currentDevice {
            deviceDidConnect(dev)
        }
    }

    private func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSBezierPath(roundedRect: NSRect(x: 3.5, y: 1.5, width: 11, height: 15), xRadius: 4.5, yRadius: 4.5)
            body.lineWidth = 1.3
            NSColor.black.setStroke()
            body.stroke()

            let wheel = NSBezierPath(roundedRect: NSRect(x: 7.5, y: 9.5, width: 3, height: 4.5), xRadius: 1.5, yRadius: 1.5)
            NSColor.black.setFill()
            wheel.fill()

            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: 9, y: 9.5))
            divider.line(to: NSPoint(x: 9, y: 6.8))
            divider.lineWidth = 1.1
            divider.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }

    private func updateSideButtonMenuState() {
        tabSwitcherItem.state = (config.sideButtonMode == .tabs) ? .on : .off
        backForwardItem.state = (config.sideButtonMode == .navigation) ? .on : .off
        disableSideButtonsItem.state = (config.sideButtonMode == .disabled) ? .on : .off
    }

    // MARK: - Delegate Actions

    func deviceDidConnect(_ device: ConnectedDevice) {
        statusMenuItem.title = device.name
        transportMenuItem.title = "Connection: \(device.transport)"
        batteryMenuItem.title = "Battery: \(device.battery)"
    }

    func deviceDidDisconnect() {
        transportMenuItem.title = "Connection: Disconnected"
        batteryMenuItem.title = "Battery: N/A"
    }

    func batteryDidUpdate(_ battery: String) {
        batteryMenuItem.title = "Battery: \(battery)"
    }

    // MARK: - Menu Actions

    @objc private func setSideButtonMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SideButtonMode else { return }
        config.sideButtonMode = mode
        updateSideButtonMenuState()
        eventInterceptor.config = config
        config.save()
    }

    @objc private func toggleInvertScroll() {
        config.invertScroll.toggle()
        invertScrollMenuItem.state = config.invertScroll ? .on : .off
        eventInterceptor.config = config
        config.save()
    }

    @objc private func refreshStatus() {
        deviceManager.refreshBattery()
    }

    @objc private func openConfigFile() {
        let url = MouseConfig.configFile
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        eventInterceptor.stop()
        NSApplication.shared.terminate(nil)
    }
}

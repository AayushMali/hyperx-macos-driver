import Cocoa

let args = CommandLine.arguments

if args.contains("--status") {
    let dm = DeviceManager()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))

    if let dev = dm.currentDevice {
        print("Device: \(dev.name)")
        print("Transport: \(dev.transport)")
        print("Vendor ID: 0x\(String(format: "%04X", dev.vendorId))")
        print("Product ID: 0x\(String(format: "%04X", dev.productId))")
        print("Battery: \(dev.battery)")
    } else {
        print("No HyperX mouse detected.")
    }
    exit(0)
}

if args.contains("--daemon") {
    let config = MouseConfig.load()
    let interceptor = EventInterceptor(config: config)
    let dm = DeviceManager()

    if !interceptor.start() {
        print("Warning: Accessibility permissions not granted. Cannot intercept mouse buttons.")
        print("Enable permissions in System Settings -> Privacy & Security -> Accessibility.")
    } else {
        print("HyperX Driver daemon active.")
    }

    if let dev = dm.currentDevice {
        print("Connected to \(dev.name) via \(dev.transport)")
    }

    CFRunLoopRun()
    exit(0)
}

// Default: Menu Bar Application
let app = NSApplication.shared
let delegate = MenuBarApp()
app.delegate = delegate
app.run()

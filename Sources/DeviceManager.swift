import Foundation
import IOKit
import IOKit.hid

struct ConnectedDevice {
    var name: String
    var transport: String
    var vendorId: Int
    var productId: Int
    var battery: String = "N/A"
}

protocol DeviceManagerDelegate: AnyObject {
    func deviceDidConnect(_ device: ConnectedDevice)
    func deviceDidDisconnect()
    func batteryDidUpdate(_ battery: String)
}

class DeviceManager {
    weak var delegate: DeviceManagerDelegate?

    private var hidManager: IOHIDManager?
    private(set) var currentDevice: ConnectedDevice?
    private var batteryTimer: Timer?

    init() {
        setupHIDManager()
    }

    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else { return }

        // Match HyperX Vendor IDs (HP 0x03F0, Kingston 0x0951)
        let matchCriteria: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String: 0x03f0,
                kIOHIDProductIDKey as String: 0x08b5
            ],
            [
                kIOHIDVendorIDKey as String: 0x03f0,
                kIOHIDDeviceUsagePageKey as String: 1,
                kIOHIDDeviceUsageKey as String: 2
            ],
            [
                kIOHIDVendorIDKey as String: 0x0951,
                kIOHIDDeviceUsagePageKey as String: 1,
                kIOHIDDeviceUsageKey as String: 2
            ]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchCriteria as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context = context else { return }
            let selfPtr = Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue()
            selfPtr.handleDeviceMatched(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context = context else { return }
            let selfPtr = Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue()
            selfPtr.handleDeviceRemoved(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        checkInitialDevices()
    }

    private func checkInitialDevices() {
        guard let manager = hidManager,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }

        for device in devices {
            if handleDeviceMatched(device) {
                break
            }
        }
    }

    @discardableResult
    private func handleDeviceMatched(_ device: IOHIDDevice) -> Bool {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "USB"
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0

        // Filter only HyperX or Pulsefire devices
        if !name.localizedCaseInsensitiveContains("HyperX") &&
           !name.localizedCaseInsensitiveContains("Pulsefire") &&
           pid != 0x08b5 {
            return false
        }

        let isBLE = transport.localizedCaseInsensitiveContains("Bluetooth")
        let displayTransport = isBLE ? "Bluetooth Low Energy" : "2.4GHz USB Dongle"

        let connected = ConnectedDevice(
            name: name.isEmpty ? "HyperX Pulsefire Haste 2 Core" : name,
            transport: displayTransport,
            vendorId: vid,
            productId: pid,
            battery: "Checking..."
        )

        currentDevice = connected
        delegate?.deviceDidConnect(connected)

        refreshBattery()
        startBatteryTimer()
        return true
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0

        if name.localizedCaseInsensitiveContains("HyperX") ||
           name.localizedCaseInsensitiveContains("Pulsefire") ||
           pid == 0x08b5 {
            currentDevice = nil
            stopBatteryTimer()
            delegate?.deviceDidDisconnect()
        }
    }

    private func startBatteryTimer() {
        stopBatteryTimer()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refreshBattery()
        }
    }

    private func stopBatteryTimer() {
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    func refreshBattery() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let battery = self?.queryBluetoothBattery() ?? "N/A"
            DispatchQueue.main.async {
                self?.currentDevice?.battery = battery
                self?.delegate?.batteryDidUpdate(battery)
            }
        }
    }

    private func queryBluetoothBattery() -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let spList = json["SPBluetoothDataType"] as? [[String: Any]],
                  let first = spList.first,
                  let connected = first["device_connected"] as? [[String: Any]] else {
                return "N/A"
            }

            for dict in connected {
                for (name, rawDetails) in dict {
                    if name.localizedCaseInsensitiveContains("HyperX") ||
                       name.localizedCaseInsensitiveContains("Pulsefire") {
                        if let details = rawDetails as? [String: Any],
                           let level = details["device_batteryLevelMain"] as? String {
                            return level
                        }
                    }
                }
            }
        } catch {
            return "N/A"
        }
        return "N/A"
    }

    deinit {
        stopBatteryTimer()
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}

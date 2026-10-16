import Cocoa
import CoreGraphics
import os.log

private let logger = OSLog(subsystem: "com.hyperx.control", category: "interceptor")

class EventInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var config: MouseConfig

    private var pendingClickWorkItem: DispatchWorkItem?
    private var lastSideButtonIsForward: Bool?
    private var lastSideButtonClickTime: TimeInterval = 0
    private let doubleClickThreshold: TimeInterval = 0.25

    init(config: MouseConfig) {
        self.config = config
    }

    func start() -> Bool {
        guard AXIsProcessTrusted() else {
            os_log("Process is not trusted for Accessibility", log: logger, type: .error)
            return false
        }

        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.otherMouseDown.rawValue) |
                        (1 << CGEventType.otherMouseUp.rawValue) |
                        (1 << CGEventType.scrollWheel.rawValue) |
                        (1 << CGEventType.mouseMoved.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let interceptor = Unmanaged<EventInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return interceptor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: context
        ) else {
            os_log("Failed to create session event tap", log: logger, type: .error)
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        pendingClickWorkItem?.cancel()
        pendingClickWorkItem = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Side Buttons (Button 3 = Back, Button 4/5 = Forward)
        if type == .otherMouseDown || type == .otherMouseUp {
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

            if (config.sideButtonMode != .disabled || config.doubleClickSegments) &&
               (buttonNumber == 3 || buttonNumber == 4 || buttonNumber == 5) {
                if type == .otherMouseDown {
                    let isForward = (buttonNumber == 4 || buttonNumber == 5)
                    DispatchQueue.main.async { [weak self] in
                        self?.handleSideButtonPress(isForward: isForward)
                    }
                }
                return nil
            }
        }

        // Scroll Wheel adjustments
        if type == .scrollWheel {
            if config.invertScroll {
                let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -deltaY)

                let ptDeltaY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -ptDeltaY)

                let fixDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixDeltaY)
            }

            if config.scrollMultiplier != 1.0 {
                let deltaY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * config.scrollMultiplier
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(deltaY))

                let ptDeltaY = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)) * config.scrollMultiplier
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(ptDeltaY))
            }
        }

        // Cursor Multiplier
        if type == .mouseMoved && config.cursorMultiplier != 1.0 {
            let dx = event.getDoubleValueField(.mouseEventDeltaX) * config.cursorMultiplier
            let dy = event.getDoubleValueField(.mouseEventDeltaY) * config.cursorMultiplier
            event.setDoubleValueField(.mouseEventDeltaX, value: dx)
            event.setDoubleValueField(.mouseEventDeltaY, value: dy)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleSideButtonPress(isForward: Bool) {
        if !config.doubleClickSegments {
            triggerSideButtonAction(isForward: isForward)
            return
        }

        let now = ProcessInfo.processInfo.systemUptime

        // Fast double-click on the same side button triggers [ or ] segment move
        if let lastForward = lastSideButtonIsForward,
           lastForward == isForward,
           (now - lastSideButtonClickTime) <= doubleClickThreshold,
           pendingClickWorkItem != nil {
            pendingClickWorkItem?.cancel()
            pendingClickWorkItem = nil
            lastSideButtonIsForward = nil
            lastSideButtonClickTime = 0

            triggerSegmentKey(isForward: isForward)
            return
        }

        // Flush any pending single-click on the opposite side button
        if let pending = pendingClickWorkItem, let lastForward = lastSideButtonIsForward {
            pending.cancel()
            pendingClickWorkItem = nil
            triggerSideButtonAction(isForward: lastForward)
        }

        lastSideButtonIsForward = isForward
        lastSideButtonClickTime = now

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingClickWorkItem = nil
            self.lastSideButtonIsForward = nil
            self.triggerSideButtonAction(isForward: isForward)
        }
        pendingClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleClickThreshold, execute: workItem)
    }

    private func triggerSegmentKey(isForward: Bool) {
        // [ is 0x21 (previous segment), ] is 0x1E (next segment)
        let keyCode: CGKeyCode = isForward ? 0x1E : 0x21
        sendKeyPress(keyCode: keyCode, flags: [])
    }

    private func triggerSideButtonAction(isForward: Bool) {
        switch config.sideButtonMode {
        case .tabs:
            let tabKeyCode: CGKeyCode = 0x30
            var flags: CGEventFlags = .maskControl
            if !isForward {
                flags.insert(.maskShift)
            }
            sendKeyPress(keyCode: tabKeyCode, flags: flags)

        case .navigation:
            let keyCode: CGKeyCode = isForward ? 0x1E : 0x21
            sendKeyPress(keyCode: keyCode, flags: .maskCommand)

        case .segments:
            triggerSegmentKey(isForward: isForward)

        case .disabled:
            break
        }
    }

    private func sendKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cgSessionEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cgSessionEventTap)
    }

    deinit {
        stop()
    }
}

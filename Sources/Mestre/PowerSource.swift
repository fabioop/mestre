import Foundation
import IOKit.ps

/// AC-or-battery state and battery level, read from IOKit and reported on change
/// through IOKit's own notification, so nothing polls.
struct PowerSource: Equatable {
    var onAC: Bool
    /// Nil on a Mac without a battery.
    var batteryPercent: Int?

    static func current() -> PowerSource {
        let onAC = (IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String?) != kIOPSBatteryPowerValue
        var percent: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = description[kIOPSCurrentCapacityKey] as? Int,
                      let capacity = description[kIOPSMaxCapacityKey] as? Int, capacity > 0 else { continue }
                percent = current * 100 / capacity
            }
        }
        return PowerSource(onAC: onAC, batteryPercent: percent)
    }
}

/// Calls `onChange` on the main thread whenever the power source changes.
final class PowerSourceWatcher {
    private var source: CFRunLoopSource?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerSourceWatcher>.fromOpaque(context).takeUnretainedValue().onChange()
        }, context)?.takeRetainedValue() else { return }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    }
}

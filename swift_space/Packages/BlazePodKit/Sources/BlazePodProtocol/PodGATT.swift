import Foundation

/// GATT layout of a BlazePod (observed in app v6.0.1, class `je.q0`).
/// UUIDs are plain strings so this module stays free of CoreBluetooth.
public enum PodGATT {
    /// Advertised service UUID used as the scan filter. Also hosts the touch characteristic.
    public static let touchService        = "50C928BD-4CB8-4C84-B745-0E58A0280CD6"
    /// Notify: hit / touch events.
    public static let touchCharacteristic = "50C9727E-4CB8-4C84-B745-0E58A0280CD6"

    /// LED service.
    public static let lightService        = "50C97BFA-4CB8-4C84-B745-0E58A0280CD6"
    /// Write: [G, B, R] or [G, B, R, 1] (see `LightCommand`).
    public static let lightCharacteristic = "50C912A2-4CB8-4C84-B745-0E58A0280CD6"
    /// Notify (parsed by the app but never subscribed): light-ended reason, see `LightEndReason`.
    public static let lightStatusCharacteristic = "50C912CF-4CB8-4C84-B745-0E58A0280CD6"
    /// Declared in the app but unused.
    public static let unknownCharacteristic = "50C912CD-4CB8-4C84-B745-0E58A0280CD6"

    /// Nordic UART Service – ASCII command channel.
    public static let nusService = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let nusRX      = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" // phone -> pod (write)
    public static let nusTX      = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" // pod -> phone (notify)

    /// Standard SIG services.
    public static let batteryService  = "180F"
    public static let batteryLevel    = "2A19"
    public static let deviceInfo      = "180A"
    public static let modelNumber     = "2A24"
    public static let serialNumber    = "2A25"
    public static let firmwareRevision = "2A26"
    public static let hardwareRevision = "2A27" // declared, never read

    /// Advertised local names.
    public static let advertisedName = "BlazePod"
    public static let bootloaderName = "BlazeDfu"

    /// Bluetooth SIG company identifier carried in the manufacturer data (decimal 2519).
    public static let companyID: UInt16 = 0x09D7
}

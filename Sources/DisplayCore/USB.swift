import Foundation
import IOKit
import IOKit.usb

enum USB {
  static let appleVendorID = 0x05AC
  static let studioDisplayProductID = 0x1114

  static func isStudioDisplayConnected() -> Bool {
    deviceExists(vendorID: appleVendorID, productID: studioDisplayProductID)
  }

  private static func deviceExists(vendorID: Int, productID: Int) -> Bool {
    guard let matching = IOServiceMatching("IOUSBHostDevice") else { return false }
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return false }
    defer { IOObjectRelease(iter) }

    while true {
      let service = IOIteratorNext(iter)
      if service == 0 { break }
      defer { IOObjectRelease(service) }
      if intProperty(service, "idVendor") == vendorID,
         intProperty(service, "idProduct") == productID {
        return true
      }
    }
    return false
  }

  private static func intProperty(_ entry: io_registry_entry_t, _ key: String) -> Int? {
    guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else { return nil }
    return value.takeRetainedValue() as? Int
  }
}

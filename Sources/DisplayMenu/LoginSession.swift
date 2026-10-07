import CoreGraphics
import VirtualDisplayBridge

@MainActor
protocol ManagedVirtualDisplay: AnyObject {
  var displayID: UInt32 { get }
  func invalidate()
}

extension MDTVirtualDisplay: ManagedVirtualDisplay {}

enum LoginSession {
  static var isActive: Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return session[kCGSessionOnConsoleKey as String] as? Bool == true
  }
}

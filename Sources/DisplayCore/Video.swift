import CoreGraphics

@_silgen_name("CGSConfigureDisplayEnabled")
private func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef, _ displayID: CGDirectDisplayID, _ enabled: Bool) -> CGError

public enum Video {
  public static func isManagedVirtualDisplay(_ id: CGDirectDisplayID) -> Bool {
    CGDisplayVendorNumber(id) == 0x4D44 && CGDisplayModelNumber(id) == 1
  }

  public enum Error: Swift.Error, CustomStringConvertible {
    case coreGraphics(api: String, error: CGError)
    case displayNotActive(id: CGDirectDisplayID)
    case wouldDisableLastDisplay(id: CGDirectDisplayID)

    public var description: String {
      switch self {
      case .coreGraphics(let api, let error):
        return "\(api) failed with CGError \(error.rawValue)."
      case .displayNotActive(let id):
        return "Display \(id) is not in the active display list."
      case .wouldDisableLastDisplay(let id):
        return "Refusing to disable display \(id): it is the only active display."
      }
    }
  }

  public static func listActiveDisplays() throws -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    var result = CGGetActiveDisplayList(.max, nil, &count)
    guard result == .success else {
      throw Error.coreGraphics(api: "CGGetActiveDisplayList", error: result)
    }

    let buffer = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(count))
    defer { buffer.deallocate() }
    result = CGGetActiveDisplayList(count, buffer, &count)
    guard result == .success else {
      throw Error.coreGraphics(api: "CGGetActiveDisplayList", error: result)
    }

    return (0..<Int(count)).map { buffer[$0] }
  }

  public static func setEnabled(id: CGDirectDisplayID, enabled: Bool, persistent: Bool) throws {
    if !enabled {
      let active = try listActiveDisplays()
      guard active.contains(id) else { throw Error.displayNotActive(id: id) }
      guard active.count > 1 else { throw Error.wouldDisableLastDisplay(id: id) }
    }

    var config: CGDisplayConfigRef?
    var result = CGBeginDisplayConfiguration(&config)
    guard result == .success, let config else {
      throw Error.coreGraphics(api: "CGBeginDisplayConfiguration", error: result)
    }
    var completed = false
    defer { if !completed { CGCancelDisplayConfiguration(config) } }
    result = CGSConfigureDisplayEnabled(config, id, enabled)
    guard result == .success else {
      throw Error.coreGraphics(api: "CGSConfigureDisplayEnabled", error: result)
    }
    let option: CGConfigureOption = persistent ? .permanently : .forSession
    completed = true // Complete consumes the configuration even when it fails.
    result = CGCompleteDisplayConfiguration(config, option)
    guard result == .success else {
      throw Error.coreGraphics(api: "CGCompleteDisplayConfiguration", error: result)
    }
  }
}

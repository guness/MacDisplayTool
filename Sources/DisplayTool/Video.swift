import CoreGraphics

@_silgen_name("CGSConfigureDisplayEnabled")
private func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef, _ displayID: CGDirectDisplayID, _ enabled: Bool) -> CGError

enum Video {
  enum Error: Swift.Error, CustomStringConvertible {
    case coreGraphics(api: String, error: CGError)
    case displayNotActive(id: CGDirectDisplayID)
    case displayNotOnline(id: CGDirectDisplayID)
    case wouldDisableLastDisplay(id: CGDirectDisplayID)

    var description: String {
      switch self {
      case .coreGraphics(let api, let error):
        return "\(api) failed with CGError \(error.rawValue)."
      case .displayNotActive(let id):
        return "Display \(id) is not in the active display list."
      case .displayNotOnline(let id):
        return "Display \(id) is not in the online display list."
      case .wouldDisableLastDisplay(let id):
        return "Refusing to disable display \(id): it is the only active display."
      }
    }
  }

  static func listActiveDisplays() throws -> [CGDirectDisplayID] {
    try query(CGGetActiveDisplayList, name: "CGGetActiveDisplayList")
  }

  static func listOnlineDisplays() throws -> [CGDirectDisplayID] {
    try query(CGGetOnlineDisplayList, name: "CGGetOnlineDisplayList")
  }

  private static func query(
    _ api: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError,
    name: String
  ) throws -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    var result = api(.max, nil, &count)
    guard result == .success else {
      throw Error.coreGraphics(api: name, error: result)
    }

    let buffer = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(count))
    defer { buffer.deallocate() }
    result = api(count, buffer, &count)
    guard result == .success else {
      throw Error.coreGraphics(api: name, error: result)
    }

    return (0..<Int(count)).map { buffer[$0] }
  }

  static func setEnabled(id: CGDirectDisplayID, enabled: Bool, persistent: Bool) throws {
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
    result = CGSConfigureDisplayEnabled(config, id, enabled)
    guard result == .success else {
      throw Error.coreGraphics(api: "CGSConfigureDisplayEnabled", error: result)
    }
    let option: CGConfigureOption = persistent ? .permanently : .forSession
    result = CGCompleteDisplayConfiguration(config, option)
    guard result == .success else {
      throw Error.coreGraphics(api: "CGCompleteDisplayConfiguration", error: result)
    }
  }
}

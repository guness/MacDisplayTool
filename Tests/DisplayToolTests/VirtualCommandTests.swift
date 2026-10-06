import ArgumentParser
import Foundation
import DisplayCore
import Testing
@testable import DisplayTool

struct VirtualCommandTests {
  @Test func persistentAgentRunsForegroundChildWithoutRecursiveInstallation() throws {
    let command = try DisplayTool.Virtual.parse(["2732", "2048", "--persistent", "--name", "Remote Display"])
    #expect(command.persistent)
    let config = VirtualAgent.configuration(executable: "/Applications/My Tools/DisplayTool",
      logPath: "/tmp/virtual.log", width: command.width, height: command.height,
      refreshRate: command.refreshRate, name: command.name)
    let data = try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0)
    let decoded = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let arguments = try #require(decoded["ProgramArguments"] as? [String])
    #expect(arguments.first == "/Applications/My Tools/DisplayTool")
    let child = try DisplayTool.Virtual.parse(Array(arguments.dropFirst(2)))
    #expect(!child.persistent)
    #expect(child.width == command.width)
    #expect(child.height == command.height)
    #expect(child.name == "Remote Display")
  }
  @Test func acceptsCustomDimensionsAndFractionalRefreshRate() throws {
    let command = try DisplayTool.Virtual.parse(["2732", "2048", "--refresh-rate", "59.94"])
    #expect(command.width == 2732)
    #expect(command.height == 2048)
    #expect(command.refreshRate == 59.94)
  }

  @Test(arguments: [
    ["0", "1080"], ["1920", "-1"], ["16385", "1080"],
    ["1920", "1080", "--refresh-rate", "nan"],
    ["1920", "1080", "--refresh-rate", "inf"],
    ["1920", "1080", "--refresh-rate", "0"],
    ["1920", "1080", "--refresh-rate", "241"],
    ["1920", "1080", "--name", "   "]
  ])
  func rejectsInvalidConfiguration(arguments: [String]) {
    #expect(throws: (any Swift.Error).self) {
      try DisplayTool.Virtual.parse(arguments)
    }
  }
}

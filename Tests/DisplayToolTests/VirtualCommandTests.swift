import ArgumentParser
import Testing
@testable import DisplayTool

struct VirtualCommandTests {
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

import ArgumentParser
import Testing
@testable import DisplayTool

struct ToggleCommandTests {
  @Test func originalToggleAndSetSyntaxRemainsAvailable() throws {
    let automatic = try DisplayTool.Toggle.parse([])
    #expect(automatic.displayID == nil)
    #expect(!automatic.persistent)
    let explicit = try DisplayTool.Toggle.parse(["3", "--persistent"])
    #expect(explicit.displayID == 3)
    #expect(explicit.persistent)
    let disable = try DisplayTool.Set.parse(["3", "--disabled"])
    #expect(disable.configuration == .disabled)
    #expect(!disable.persistent)
    let enable = try DisplayTool.Set.parse(["3", "--enabled", "--persistent"])
    #expect(enable.configuration == .enabled)
    #expect(enable.persistent)
  }
}

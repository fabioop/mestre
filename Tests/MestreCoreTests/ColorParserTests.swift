import Foundation
import Testing
@testable import MestreCore

@Suite struct ColorParserTests {
    @Test func parsesHexForms() throws {
        let orange = try #require(ColorParser.parse("#ff8800"))
        #expect(orange.hex == "#FF8800")
        #expect(orange.rgbString == "rgb(255, 136, 0)")
        #expect(orange.hslString == "hsl(32, 100%, 50%)")
        #expect(ColorParser.parse("#F80")?.hex == "#FF8800")
        #expect(ColorParser.parse("#ff880080")?.rgbString == "rgba(255, 136, 0, 0.502)")
        #expect(ColorParser.parse("#ggg") == nil)
        #expect(ColorParser.parse("#12345") == nil)
    }

    @Test func parsesFunctionsAndNames() throws {
        #expect(ColorParser.parse("rgb(255, 136, 0)")?.hex == "#FF8800")
        #expect(ColorParser.parse("rgb(100% 0% 0%)")?.hex == "#FF0000")
        #expect(ColorParser.parse("rgba(0,0,255,0.5)")?.hex == "#0000FF80")
        #expect(ColorParser.parse("hsl(120, 100%, 50%)")?.hex == "#00FF00")
        #expect(ColorParser.parse("hsl(0 0% 50%)")?.hex == "#808080")
        #expect(ColorParser.parse("Coral")?.hex == "#FF7F50")
        #expect(ColorParser.parse("Coral", allowNames: false) == nil)
        #expect(ColorParser.parse("hsl(0.5turn 100% 50%)")?.hex == "#00FFFF")
        #expect(ColorParser.parse("rgb(1,2)") == nil)
        #expect(ColorParser.parse("rgba(0,0,0,abc)") == nil)
        #expect(ColorParser.parse("rgb(1,2,3,4,5)") == nil)
        #expect(ColorParser.parse("rgb(1,2,3) junk") == nil)
        #expect(ColorParser.parse("safari") == nil)
        #expect(ColorParser.parse("#ff0001")?.hslString == "hsl(0, 100%, 50%)")
    }

    @Test func gateAndSwiftUIOutput() throws {
        #expect(ColorParser.mayBeColor("#fff") && ColorParser.mayBeColor("rgb(1,2,3)") && ColorParser.mayBeColor("teal"))
        #expect(!ColorParser.mayBeColor("teal", allowNames: false) && !ColorParser.mayBeColor("xcode"))
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"colors": {"formats": ["HEX"], "names": true}}"#.utf8))
        #expect(config.colors.formats == ["hex"] && config.colors.names)
        let half = try #require(ColorParser.parse("rgba(255, 255, 255, 0.5)"))
        #expect(half.swiftUIString == "Color(red: 1, green: 1, blue: 1, opacity: 0.5)")
        let roundTrip = ParsedColor.fromHSL(hue: 32, saturation: 1, lightness: 0.5)
        #expect(roundTrip.hex == "#FF8800")
    }
}

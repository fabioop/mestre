import Foundation
import Testing
@testable import MestreCore

@Suite struct WindowGeometryTests {
    let screen = CGRect(x: 0, y: 25, width: 1200, height: 775)  // below a 25pt menu bar
    let window = CGRect(x: 100, y: 100, width: 600, height: 400)

    @Test func halvesTileTheScreen() throws {
        let left = try #require(WindowGeometry.frame(for: .leftHalf, in: screen, current: window))
        let right = try #require(WindowGeometry.frame(for: .rightHalf, in: screen, current: window))
        #expect(left == CGRect(x: 0, y: 25, width: 600, height: 775))
        #expect(right == CGRect(x: 600, y: 25, width: 600, height: 775))
        let top = try #require(WindowGeometry.frame(for: .topHalf, in: screen, current: window))
        let bottom = try #require(WindowGeometry.frame(for: .bottomHalf, in: screen, current: window))
        #expect(top.maxY == bottom.minY && bottom.maxY == screen.maxY)
    }

    @Test func thirdsAndTwoThirdsLineUp() throws {
        let l = try #require(WindowGeometry.frame(for: .leftThird, in: screen, current: window))
        let c = try #require(WindowGeometry.frame(for: .centerThird, in: screen, current: window))
        let r = try #require(WindowGeometry.frame(for: .rightThird, in: screen, current: window))
        #expect(l.maxX == c.minX && c.maxX == r.minX && r.maxX == screen.maxX)
        let two = try #require(WindowGeometry.frame(for: .leftTwoThirds, in: screen, current: window))
        #expect(two.maxX == r.minX)
    }

    @Test func gapsAreHonoured() throws {
        let left = try #require(WindowGeometry.frame(for: .leftHalf, in: screen, current: window, gap: 10))
        let right = try #require(WindowGeometry.frame(for: .rightHalf, in: screen, current: window, gap: 10))
        #expect(left.minX == 10 && left.minY == 35)
        #expect(right.minX - left.maxX == 10)
        #expect(right.maxX == screen.maxX - 10)
    }

    @Test func centerKeepsSizeAndMaximizeFillsScreen() throws {
        let centered = try #require(WindowGeometry.frame(for: .center, in: screen, current: window))
        #expect(centered.size == window.size && centered.midX == screen.midX && centered.midY == screen.midY)
        #expect(WindowGeometry.frame(for: .maximize, in: screen, current: window) == screen)
        #expect(WindowGeometry.frame(for: .restore, in: screen, current: window) == nil)
    }

    @Test func repeatedLeftCyclesHalfTwoThirdsThird() throws {
        let cycle = WindowGeometry.cycle(for: .leftHalf)
        #expect(WindowGeometry.next(in: cycle, current: window, screen: screen) == .leftHalf)
        let half = try #require(WindowGeometry.frame(for: .leftHalf, in: screen, current: window))
        #expect(WindowGeometry.next(in: cycle, current: half, screen: screen) == .leftTwoThirds)
        let third = try #require(WindowGeometry.frame(for: .leftThird, in: screen, current: window))
        #expect(WindowGeometry.next(in: cycle, current: third.offsetBy(dx: 1, dy: 0), screen: screen) == .leftHalf)
    }

    @Test func movingBetweenDisplaysKeepsRelativePosition() {
        let other = CGRect(x: 1200, y: 0, width: 800, height: 600)
        let moved = WindowGeometry.move(window, from: screen, to: other)
        #expect(moved.size == window.size)
        #expect(moved.minX > other.minX && moved.maxX <= other.maxX)
        let huge = CGRect(x: 0, y: 25, width: 2000, height: 2000)
        #expect(WindowGeometry.move(huge, from: screen, to: other).size == other.size)
    }
}

@Suite struct WindowsConfigTests {
    let screen = CGRect(x: 0, y: 25, width: 1200, height: 775)
    let window = CGRect(x: 100, y: 100, width: 600, height: 400)

    @Test func everyLayoutHasATitleSymbolAndUniqueDefaultHotkey() {
        let hotkeys = WindowLayout.allCases.compactMap(\.defaultHotkey)
        #expect(hotkeys.count == WindowLayout.allCases.count)
        #expect(Set(hotkeys).count == hotkeys.count)
        #expect(WindowLayout.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
        #expect(hotkeys.allSatisfy { KeyCombo(parsing: $0) != nil })
    }

    @Test func windowsConfigDecodesAndDrivesHotkeyDefaults() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"windows": {"gap": -4}}"#.utf8))
        #expect(config.windows.gap == 0)
        #expect(config.hotkeyDefaults["ctrl+option+left"] == "window:leftHalf")
        let off = try JSONDecoder().decode(Config.self, from: Data(#"{"windows": {"enabled": false}}"#.utf8))
        #expect(off.hotkeyDefaults.isEmpty)
    }

    @Test func userHotkeysOverrideAndDisableDefaults() {
        let codes: [Character: UInt16] = ["h": 4, "t": 17, "d": 2, "f": 3, "g": 5, "e": 14, "u": 32, "i": 34, "j": 38, "k": 40, "c": 8]
        let table = HotkeyTable(hotkeys: ["hyper+h": "window:leftHalf", "ctrl+option+right": "", "hyper+t": "Terminal"],
                                defaults: WindowLayout.defaultHotkeys, panelHotKey: .default, keyCodes: codes)
        let targets = Dictionary(uniqueKeysWithValues: table.entries.map { ($0.text, $0.target) })
        #expect(targets["hyper+h"] == "window:leftHalf")
        #expect(targets["ctrl+option+right"] == nil)
        #expect(targets["ctrl+option+left"] == "window:leftHalf")
        #expect(table.entries.first { $0.text == "ctrl+option+up" }?.isDefault == true)
        #expect(table.windowEntries.count == WindowLayout.allCases.count)  // one disabled, one added
        #expect(HotkeyTable.windowLayout(in: "window:maximize") == .maximize)
        #expect(HotkeyTable.windowLayout(in: "Terminal") == nil)
        #expect(table.unresolvedTargets(in: []) == ["Terminal"])
    }

    @Test func targetResolvesCyclesRestoreAndDisplays() throws {
        let other = CGRect(x: 1200, y: 0, width: 800, height: 600)
        #expect(WindowGeometry.target(for: .restore, current: window, screen: screen, screens: [screen], gap: 0) == .restore)
        #expect(WindowGeometry.target(for: .nextDisplay, current: window, screen: screen, screens: [screen], gap: 0) == .nothing)
        guard case .frame(let moved) = WindowGeometry.target(for: .nextDisplay, current: window, screen: screen, screens: [screen, other], gap: 0) else { Issue.record("expected a frame"); return }
        #expect(other.contains(moved))
        guard case .frame(let half) = WindowGeometry.target(for: .leftHalf, current: window, screen: screen, screens: [screen], gap: 0) else { Issue.record("expected a frame"); return }
        #expect(half.width == 600)
        // A window that snaps to a 10pt grid still counts as "at the half".
        guard case .frame(let next) = WindowGeometry.target(for: .leftHalf, current: half.insetBy(dx: 0, dy: 5), screen: screen, screens: [screen], gap: 0) else { Issue.record("expected a frame"); return }
        #expect(next.width == 800)
    }

    @Test func maximizedWindowsFillTheNextDisplay() {
        let other = CGRect(x: 1200, y: 0, width: 800, height: 600)
        #expect(WindowGeometry.move(screen, from: screen, to: other) == other)
        let overhanging = CGRect(x: -200, y: 25, width: 600, height: 400)
        let moved = WindowGeometry.move(overhanging, from: screen, to: other)
        #expect(moved.minX == other.minX)
    }
}

@Suite struct OpenWindowsConfigTests {
    @Test func listWindowsDefaultsOnAndDecodes() throws {
        #expect(Config().windows.listWindows)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"windows": {"listWindows": false}}"#.utf8))
        #expect(!config.windows.listWindows)
    }
}

import Testing
@testable import MestreCore

@Suite struct AppVersionTests {
    @Test func releasesBelowOneAreTheBeta() {
        #expect(AppVersion.display("0.1.0") == "0.1.0 (beta)")
        #expect(AppVersion.display("0.12.3") == "0.12.3 (beta)")
    }

    @Test func theLabelEndsAtOne() {
        #expect(AppVersion.display("1.0.0") == "1.0.0")
        #expect(AppVersion.display("10.0.1") == "10.0.1")
    }

    @Test func preReleaseAndDevelopmentVersionsStayAsTheyAre() {
        #expect(AppVersion.display("0.1.0-beta.1") == "0.1.0-beta.1")
        #expect(AppVersion.display("0.0.0-dev") == "0.0.0-dev")
    }
}

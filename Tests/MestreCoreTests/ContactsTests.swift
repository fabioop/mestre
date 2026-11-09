import Foundation
import Testing
@testable import MestreCore

@Suite struct ContactIndexTests {
    static let jane = ContactRecord(id: "1:ABPerson", name: "Jane Doe", nickname: "JD", organization: "Acme Corp",
                                    emails: [.init(label: "work", value: "jane.doe@acme.com"), .init(label: "home", value: "jane@home.org")],
                                    phones: [.init(label: "mobile", value: "+351 912-345 678")])
    static let joao = ContactRecord(id: "2", name: "João Silva", organization: "Padaria", phones: [.init(value: "(21) 555-0100")])
    static let john = ContactRecord(id: "3", name: "John Smith", emails: [.init(value: "jsmith@example.com")])
    static let acme = ContactRecord(id: "4", name: "", organization: "Acme Deliveries")
    static let index = ContactIndex([john, joao, jane, acme])

    private func names(_ query: String, limit: Int = 10) -> [String] {
        Self.index.search(query, limit: limit).map(\.record.name)
    }

    @Test func emptyQueryListsEveryoneByName() {
        #expect(names("") == ["Acme Deliveries", "Jane Doe", "João Silva", "John Smith"])
        #expect(names("  ", limit: 2) == ["Acme Deliveries", "Jane Doe"])
    }

    @Test func findsByNameNicknameOrganisationAndEmail() {
        #expect(names("jane").first == "Jane Doe")
        #expect(names("doe") == ["Jane Doe"])
        #expect(names("jd").first == "Jane Doe")
        #expect(names("padaria") == ["João Silva"])
        #expect(names("home.org") == ["Jane Doe"])
        #expect(names("jsmith") == ["John Smith"])
    }

    @Test func accentsAndCaseDoNotMatter() {
        #expect(names("joao") == ["João Silva"])
        #expect(names("JOÃO") == ["João Silva"])
    }

    @Test func everyWordMustMatch() {
        #expect(names("jane acme") == ["Jane Doe"])
        #expect(names("jane smith").isEmpty)
        #expect(names("acme").count == 2)
    }

    @Test func aNameBeatsAnOrganisationAndAnExactWordBeatsAPrefix() {
        let acme = Self.index.search("acme", limit: 10)
        #expect(acme.first?.record.name == "Acme Deliveries")
        let jo = ContactIndex([ContactRecord(id: "a", name: "Jo Park"), ContactRecord(id: "b", name: "Joanna Park")]).search("jo", limit: 2)
        #expect(jo.map(\.record.name) == ["Jo Park", "Joanna Park"])
        #expect(jo[0].score == 100)
    }

    @Test func phoneDigitsMatchWhateverTheFormatting() {
        #expect(names("912345") == ["Jane Doe"])
        #expect(names("912 345") == ["Jane Doe"])
        #expect(names("+351 912") == ["Jane Doe"])
        #expect(names("5550100") == ["João Silva"])
        // Two digits are too few to search phone numbers.
        #expect(names("91").isEmpty)
    }

    @Test func initialsAndLettersInOrder() {
        #expect(Set(names("js")) == ["John Smith", "João Silva"])
        #expect(names("jsmt") == ["John Smith"])
    }

    @Test func ordinarySearchesTakeWholeWordsAndNumbersNotArithmetic() {
        func global(_ query: String) -> [String] { Self.index.search(query, limit: 10, wordsOnly: true).map(\.record.name) }
        // João Silva's initials don't count; John's address starts with "js".
        #expect(global("js") == ["John Smith"])
        #expect(global("jsmt").isEmpty)
        #expect(global("jane") == ["Jane Doe"])
        #expect(global("+351 912") == ["Jane Doe"])
        #expect(global("912345") == ["Jane Doe"])
        #expect(global("91234+5").isEmpty)
        #expect(global("(21) 555").isEmpty)
    }

    @Test func aCardWithNothingToNameItIsNeverFound() {
        let index = ContactIndex([ContactRecord(id: "e", name: "")])
        #expect(index.search("", limit: 5).map(\.record.name) == [ContactRecord.unnamed])
        #expect(index.search("name", limit: 5).isEmpty)
    }

    @Test func aCompanyCardIsNamedAfterTheCompany() {
        #expect(Self.acme.name == "Acme Deliveries")
        #expect(Self.acme.subtitle == nil)
        #expect(ContactRecord(id: "x", name: " ", emails: [.init(value: "a@b.c")]).name == "a@b.c")
        #expect(ContactRecord(id: "y", name: "").name == "No Name")
    }

    @Test func subtitleIsTheOrganisationThenEmailOrPhone() {
        #expect(Self.jane.subtitle == "Acme Corp · jane.doe@acme.com")
        #expect(Self.joao.subtitle == "Padaria · (21) 555-0100")
        #expect(Self.john.subtitle == "jsmith@example.com")
    }
}

@Suite struct ContactActionsTests {
    let jane = ContactIndexTests.jane

    @Test func oneActionPerValueAndTheFirstKeepsThePlainID() {
        let ids = ContactActions.actions(for: jane).map(\.id)
        #expect(ids == ["reveal", "copyEmail", "copyEmail.1", "copyPhone", "email", "email.1", "call", "message", "facetime"])
        #expect(Set(ids).count == ids.count)
        let titles = ContactActions.actions(for: jane).map(\.title)
        #expect(titles.contains("Email jane@home.org (home)"))
        #expect(titles.contains("Call"))
    }

    @Test func theDefaultActionComesFirstOrOpenInContactsWhenTheCardLacksIt() {
        #expect(ContactActions.actions(for: jane, defaultAction: .call).first?.id == "call")
        let noPhone = ContactIndexTests.john
        #expect(ContactActions.actions(for: noPhone, defaultAction: .call).first?.id == "reveal")
        // Messages and FaceTime fall back to the email on a card with no phone.
        #expect(ContactActions.actions(for: noPhone).map(\.id) == ["reveal", "copyEmail", "email", "message", "facetime"])
    }

    @Test func idsMapBackToTheirValue() {
        #expect(ContactActions.target(for: "email.1") == .init(kind: .email, index: 1))
        #expect(ContactActions.target(for: "call") == .init(kind: .call, index: 0))
        #expect(ContactActions.target(for: "reveal.1") == nil)
        #expect(ContactActions.target(for: "email.x") == nil)
        #expect(ContactActions.target(for: "quit") == nil)
        #expect(ContactActions.value(for: .init(kind: .copyEmail, index: 1), in: jane) == "jane@home.org")
        #expect(ContactActions.value(for: .init(kind: .copyEmail, index: 5), in: jane) == nil)
    }

    @Test func linksUseTheConfiguredSchemes() {
        func url(_ id: String, _ settings: Config.Contacts = Config.Contacts()) -> String? {
            ContactActions.target(for: id).flatMap { ContactActions.url(for: $0, in: jane, settings: settings) }?.absoluteString
        }
        #expect(url("reveal") == "addressbook://1:ABPerson")
        #expect(url("email") == "mailto:jane.doe@acme.com")
        #expect(url("call") == "tel:+351912345678")
        #expect(url("message") == "sms:+351912345678")
        #expect(url("facetime") == "facetime:+351912345678")
        #expect(url("copyEmail") == nil)
        var settings = Config.Contacts()
        settings.callScheme = .facetimeAudio
        settings.messageScheme = .imessage
        #expect(url("call", settings) == "facetime-audio:+351912345678")
        #expect(url("message", settings) == "imessage:+351912345678")
        #expect(ContactActions.dialable("(21) 555-0100") == "215550100")
        #expect(ContactActions.dialable("+1 555 123 4567 ext. 89") == "+15551234567")
        #expect(ContactActions.dialable("555 1234,89") == "5551234")
    }

    @Test func everyActionIdIsDeclared() {
        let declared = Set(ContactActions.declared.map(\.id))
        let plain = ContactActions.actions(for: jane).map { String($0.id.split(separator: ".")[0]) }
        #expect(Set(plain).isSubset(of: declared))
    }
}

@Suite struct ContactsConfigTests {
    @Test func defaultsAndOldFilesDecode() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(config.contacts == Config.Contacts())
        #expect(config.contacts.keyword == "contact" && config.contacts.searchEverywhere && config.contacts.defaultAction == .reveal)
    }

    @Test func valuesAreReadAndClampedAndUnknownChoicesFallBack() throws {
        let json = #"{"contacts": {"keyword": "Who", "searchEverywhere": false, "maxResults": 999, "defaultAction": "EMAIL", "callScheme": "facetime-audio", "messageScheme": "carrier-pigeon"}}"#
        let contacts = try JSONDecoder().decode(Config.self, from: Data(json.utf8)).contacts
        #expect(contacts.keyword == "who")
        #expect(!contacts.searchEverywhere)
        #expect(contacts.maxResults == 100)
        #expect(contacts.defaultAction == .email)
        #expect(contacts.callScheme == .facetimeAudio)
        #expect(contacts.messageScheme == .sms)
        let round = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(Config()))
        #expect(round.contacts == Config.Contacts())
    }
}

/// Guards the keystroke budget from AGENTS.md for a large address book. Debug builds are several
/// times slower than release, so the ceiling is loose: it catches quadratic blow-ups.
@Suite struct ContactPerformanceTests {
    private static let first = ["Ana", "Bruno", "Carla", "Diogo", "Eva", "Filipe", "Gonçalo", "Helena", "Inês", "João"]
    private static let last = ["Silva", "Santos", "Ferreira", "Pereira", "Oliveira", "Costa", "Rodrigues", "Martins", "Sousa", "Fernandes"]
    private static let records: [ContactRecord] = (0..<5_000).map { i in
        let given = first[i % first.count], family = last[(i / first.count) % last.count]
        return ContactRecord(id: "\(i)", name: "\(given) \(family) \(i)", organization: "Company \(i % 300)",
                             emails: [.init(value: "\(given.lowercased()).\(family.lowercased())\(i)@example.com")],
                             phones: [.init(label: "mobile", value: "+351 91\(String(format: "%07d", i))")])
    }

    @Test func buildingTheIndexOfFiveThousandContactsIsQuick() {
        let start = ContinuousClock.now
        let index = ContactIndex(Self.records)
        let elapsed = ContinuousClock.now - start
        print("indexing 5 000 contacts: \(elapsed)")
        #expect(index.count == 5_000)
        // Off the main thread, but still well under the 1 s index budget.
        #expect(elapsed < (ProcessInfo.processInfo.environment["CI"] == nil ? .seconds(2) : .seconds(10)))
    }

    @Test func searchingFiveThousandContactsStaysFast() {
        let index = ContactIndex(Self.records)
        let queries = ["a", "an", "ana", "silva", "joao sil", "company 12", "js", "912345", "zzz", "ana.silva4"]
        _ = index.search("warm up", limit: 8)
        let start = ContinuousClock.now
        for query in queries { _ = index.search(query, limit: 8) }
        let perQuery = (ContinuousClock.now - start) / queries.count
        print("searching 5 000 contacts: \(perQuery) per query")
        let ceiling: Duration = ProcessInfo.processInfo.environment["CI"] == nil ? .milliseconds(25) : .milliseconds(250)
        #expect(perQuery < ceiling, "contact search took \(perQuery) per query (debug build)")
        #expect(index.search("joao silva", limit: 8).allSatisfy { $0.record.name.hasPrefix("João Silva") })
    }
}

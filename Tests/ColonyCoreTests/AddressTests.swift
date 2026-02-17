import XCTest
@testable import ColonyCore

final class AddressTests: XCTestCase {
    func testParseLocalImplicit() throws {
        let a = try Address.parse("@foo")
        XCTAssertEqual(a.target, .local)
        XCTAssertEqual(a.session, "foo")
    }

    func testParseLocalExplicit() throws {
        let a = try Address.parse("@local:foo")
        XCTAssertEqual(a.target, .local)
        XCTAssertEqual(a.session, "foo")
    }

    func testParseSsh() throws {
        let a = try Address.parse("@mbp:codex1")
        XCTAssertEqual(a.target, .ssh(host: "mbp"))
        XCTAssertEqual(a.session, "codex1")
    }
}

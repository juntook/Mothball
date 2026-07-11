// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Core

@Suite("Localization resources")
struct LocalizationResourceTests {
    @Test("zh-Hans table ships in the Core bundle and translates safety tiers")
    func zhHansTableShips() throws {
        let path = try #require(
            Bundle.module.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "zh-Hans")
        )
        let table = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        #expect(table["safety.regenerable.name"] == "可再生")
        #expect(table["safety.user_data.name"] == "用户数据")
        #expect(table["safety.protected.name"] == "受保护")
    }

    @Test("en table covers every zh-Hans key")
    func enCoversAllKeys() throws {
        func keys(_ loc: String) throws -> Set<String> {
            let path = try #require(
                Bundle.module.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: loc)
            )
            let table = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            return Set(table.keys)
        }
        let en = try keys("en")
        let zh = try keys("zh-Hans")
        #expect(zh.subtracting(en).isEmpty)
    }
}

import Foundation
import Testing

@testable import SeshctlCore

@Suite("StableHash")
struct StableHashTests {
    @Test("Empty string hashes to djb2 initial seed 5381")
    func emptyString() {
        #expect(StableHash.djb2("") == 5381)
    }

    @Test("Single-character 'a' hashes to 5381 * 33 + 97 = 177670")
    func singleCharacter() {
        #expect(StableHash.djb2("a") == 177670)
    }

    @Test("Same input produces same output")
    func deterministic() {
        #expect(StableHash.djb2("seshctl") == StableHash.djb2("seshctl"))
        #expect(StableHash.djb2("mozi-app") == StableHash.djb2("mozi-app"))
    }

    @Test("Different inputs produce different outputs for common repo names")
    func differentInputs() {
        let names = ["seshctl", "mozi-app", "dashboard", "infra", "api"]
        let hashes = Set(names.map { StableHash.djb2($0) })
        #expect(hashes.count == names.count)
    }
}

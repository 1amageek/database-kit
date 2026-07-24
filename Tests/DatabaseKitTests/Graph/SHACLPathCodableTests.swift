import DatabaseKit
import DatabaseTypes
import Foundation
import Testing
@testable import DatabaseKit

@Suite("SHACL path Codable adapter")
struct SHACLPathCodableTests {
    @Test("Codable preserves the validated semantic path")
    func roundTrip() throws {
        let path = SHACLPath.alternative(
            try SHACLPathList([
                .predicate(try RDFPredicateIRI("urn:name")),
                .oneOrMore(
                    .inverse(
                        .predicate(try RDFPredicateIRI("urn:parent"))
                    )
                ),
            ])
        )

        let encoded = try JSONEncoder().encode(path)
        let decoded = try JSONDecoder().decode(
            SHACLPath.self,
            from: encoded
        )

        #expect(decoded == path)
    }
}

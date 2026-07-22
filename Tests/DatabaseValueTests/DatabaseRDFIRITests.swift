import DatabaseValue
import Testing

@Suite("RDF IRI validation")
struct DatabaseRDFIRITests {
    @Test("absolute RFC 3987 forms retain exact spelling")
    func validAbsoluteIRIs() throws {
        let values = [
            "a:",
            "x:#",
            "x:?",
            "x:?#",
            "urn:example:calendar",
            "https://user:pass@example.com:443/a/b?query=東京#祭",
            "https://[2001:db8::1]/calendar",
            "https://[v1.fe80::a]/future",
            "file:///tmp/calendar",
            "custom:/absolute/path",
            "custom:rootless",
            "https://example.com/%E6%9D%B1%E4%BA%AC",
            "x:/a/%2E/b",
            "x:/a/./b",
            "x:/a/../b",
            "x:/a/.../b",
            "x://",
            "x://:80",
            "x://host:65536",
            "x://256.256.256.256/",
            "x://[::ffff:192.0.2.128]/",
            "x:\u{20D0}",
        ]

        for value in values {
            #expect(try DatabaseRDFIRI(value).rawValue == value)
        }
    }

    @Test("relative, malformed, and forbidden forms fail deterministically")
    func invalidIRIs() {
        let values = [
            "relative/path",
            ":missing-scheme",
            "1invalid:value",
            "urn:%ZZ",
            "https://example.com/%A",
            "https://[2001:db8:::1]/",
            "https://[2001:db8::1::2]/",
            "https://[v.fe80]/",
            "https://example.com/has space",
            "https://example.com/{invalid}",
            "https://user@example.com@evil.invalid/",
            "x://host:abc",
            "x://host:+80",
            "x://host:８０",
            "x://[::1]:\u{20D0}",
            "x://[fe80::1%25eth0]/",
            "x://[1:2:3:4:5:6:7]/",
            "x://[1:2:3:4:5:6:7:8:9]/",
            "x://[::ffff:192.0.2.01]/",
            "x://[v1.a%20]/",
            "x:#a#b",
            "x:\u{200E}",
            "x:\u{202E}",
            "x://\u{20D0}host:bad",
        ]

        for value in values {
            #expect(throws: DatabaseRDFIRIError.self) {
                _ = try DatabaseRDFIRI(value)
            }
        }
    }

    @Test("IRI identity does not apply Unicode normalization")
    func exactIdentity() throws {
        let composed = try DatabaseRDFIRI("https://example.com/é")
        let decomposed = try DatabaseRDFIRI("https://example.com/e\u{301}")

        #expect(composed != decomposed)
        #expect(Set([composed, decomposed]).count == 2)
        #expect((composed < decomposed) != (decomposed < composed))
    }

    @Test("private-use scalars are admitted only in the query")
    func privateUseScope() throws {
        let privateScalar = "\u{E000}"
        _ = try DatabaseRDFIRI("urn:value?query=\(privateScalar)")
        #expect(throws: DatabaseRDFIRIError.self) {
            _ = try DatabaseRDFIRI("urn:value#\(privateScalar)")
        }
        #expect(throws: DatabaseRDFIRIError.self) {
            _ = try DatabaseRDFIRI("urn:\(privateScalar)")
        }
    }

    @Test("all spelling distinctions remain part of RDF IRI identity")
    func spellingDistinctions() throws {
        let pairs = [
            ("HTTP://EXAMPLE/", "http://example/"),
            ("x:/%7e", "x:/%7E"),
            ("x:/%41", "x:/A"),
            ("x:", "x:#"),
            ("x:", "x:?"),
            ("x://host", "x://host/"),
        ]

        for (left, right) in pairs {
            let leftIRI = try DatabaseRDFIRI(left)
            let rightIRI = try DatabaseRDFIRI(right)
            #expect(leftIRI != rightIRI)
            #expect(Set([leftIRI, rightIRI]).count == 2)
        }
    }
}

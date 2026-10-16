import DatabaseKit
import Testing

@Suite("Owned SQL array input grammar")
struct QueryArrayInputTests {
    private func limits(bytes: UInt64 = 100_000, nodes: UInt64 = 1000,
                        depth: UInt64 = 6, elements: UInt64 = 1000) -> QueryValueLimits {
        QueryValueLimits(maximumRetainedBytes: bytes, maximumTotalNodes: nodes,
                         maximumNestingDepth: depth, maximumCollectionElements: elements)
    }

    @Test("Shape lower bounds quoted escapes and NULL retain their distinct meanings")
    func shapeAndCells() throws {
        let value = try QueryArrayInput(sqlLexicalForm: #"[-2:-1][4:6]={{NULL,"NULL",""},{a\,b,"é😀",N\ULL}}"#, limits: limits())
        #expect(value.dimensions == [try QueryArrayDimension(lowerBound: -2, length: 2),
                                     try QueryArrayDimension(lowerBound: 4, length: 3)])
        #expect(value.count == 6)
        #expect(try value.elementText(at: 0) == nil)
        #expect(try value.elementText(at: 1) == "NULL")
        #expect(try value.elementText(at: 2) == "")
        #expect(try value.elementText(at: 3) == "a,b")
        #expect(try value.elementText(at: 4) == "é😀")
        #expect(try value.elementText(at: 5) == "NULL")
        let spaces = try QueryArrayInput(sqlLexicalForm: #"{  a  ," b ",x\  }"#, limits: limits())
        #expect(try spaces.elementText(at: 0) == "a")
        #expect(try spaces.elementText(at: 1) == " b ")
        #expect(try spaces.elementText(at: 2) == "x ")
        let escapedSpace = try QueryArrayInput(sqlLexicalForm: #"{\ }"#, limits: limits())
        #expect(try escapedSpace.elementText(at: 0) == " ")
    }

    @Test("Empty and six-dimensional arrays use one flat index and owned requested text")
    func emptyDeepAndOwnedText() throws {
        let empty = try QueryArrayInput(sqlLexicalForm: " {} ", limits: limits())
        #expect(empty.count == 0 && empty.dimensions.isEmpty)
        #expect(throws: QueryValueError.invalidArrayInputIndex(index: 0, count: 0)) { try empty.elementText(at: 0) }
        func owned() throws(QueryValueError) -> QueryArrayInput {
            let source = "{{{{{{\"owned\\\\text\"}}}}}}"
            return try QueryArrayInput(sqlLexicalForm: source, limits: limits())
        }
        let value = try owned()
        #expect(value.dimensions.count == 6)
        let text = try value.elementText(at: 0)
        #expect(text == "owned\\text")
        #expect(throws: QueryValueError.invalidArrayInputIndex(index: -1, count: 1)) { try value.elementText(at: -1) }
        #expect(throws: QueryValueError.invalidArrayInputIndex(index: 1, count: 1)) { try value.elementText(at: 1) }
    }

    @Test("Malformed grammar shape bounds and trailing input throw intrinsic syntax errors")
    func malformedInput() {
        for text in ["", "{", "{a,}", "{,a}", "{{}}", "{{1},{2,3}}", "{1,{2}}", "{\"open}",
                     "{a\"b}", "{a}tail", "[1:2]={1}", "[2:1]={}", "[2147483647:2147483647]={1}",
                     "[-2147483648:2147483646]={1}", "{{{{{{{1}}}}}}}", "{a\\"] {
            do {
                _ = try QueryArrayInput(sqlLexicalForm: text, limits: limits())
                Issue.record("Malformed array was accepted: \(text)")
            } catch {
                guard case .malformedArrayInput(let offset, _) = error else {
                    Issue.record("Expected an intrinsic array syntax failure: \(error)"); continue
                }
                #expect(offset <= UInt64(text.utf8.count))
            }
        }
    }

    @Test("Input plus actual metadata and logical limits enforce exact and one-past")
    func resourceBoundaries() throws {
        let text = "{a,NULL,c}"
        let baseline = try QueryArrayInput(sqlLexicalForm: text, limits: limits())
        #expect(baseline.retainedByteCount > UInt64(text.utf8.count))
        let exact = try QueryArrayInput(sqlLexicalForm: text,
            limits: limits(bytes: baseline.retainedByteCount, nodes: 4, depth: 2, elements: 3))
        #expect(try exact.elementText(at: 2) == "c")
        for budget in [limits(bytes: baseline.retainedByteCount - 1), limits(nodes: 3),
                       limits(depth: 1), limits(elements: 2)] {
            #expect(throws: QueryValueError.self) { try QueryArrayInput(sqlLexicalForm: text, limits: budget) }
        }
    }

    @Test("Large escaped input indexes cells without requiring scalar conversion")
    func requestedCellOnly() throws {
        let raw = String(repeating: #""not a date\,not JSON""# + ",", count: 200) + #""last\\cell""#
        let input = try QueryArrayInput(sqlLexicalForm: "{" + raw + "}", limits: limits(bytes: 100_000, elements: 201))
        #expect(input.count == 201)
        #expect(try input.elementText(at: 200) == "last\\cell")
        #expect(try input.elementText(at: 0) == "not a date,not JSON")
    }
}

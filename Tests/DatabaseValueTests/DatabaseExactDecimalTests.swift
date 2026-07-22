import DatabaseValue
import Testing

@Suite("DatabaseExactDecimal")
struct DatabaseExactDecimalTests {
    @Test func normalizesAndAddsWithoutFloatingPoint() throws {
        let left = DatabaseExactDecimal(coefficient: 120, scale: 2)
        let right = DatabaseExactDecimal(coefficient: 3, scale: 1)

        #expect(left == DatabaseExactDecimal(coefficient: 12, scale: 1))
        #expect(
            try left.adding(right)
                == DatabaseExactDecimal(coefficient: 15, scale: 1)
        )
    }

    @Test func multipliesAndDividesExactly() throws {
        let left = DatabaseExactDecimal(coefficient: 25, scale: 1)
        let right = DatabaseExactDecimal(coefficient: 4, scale: 0)

        #expect(
            try left.multiplying(by: right)
                == DatabaseExactDecimal(coefficient: 10, scale: 0)
        )
        #expect(
            try left.dividing(by: right)
                == DatabaseExactDecimal(coefficient: 625, scale: 3)
        )
    }

    @Test func inexactDivisionAndOverflowAreTypedFailures() {
        let one = DatabaseExactDecimal(coefficient: 1, scale: 0)
        let three = DatabaseExactDecimal(coefficient: 3, scale: 0)
        #expect(throws: DatabaseExactDecimalError.inexactResult) {
            _ = try one.dividing(by: three)
        }

        let maximum = DatabaseExactDecimal(coefficient: Int64.max, scale: 0)
        #expect(throws: DatabaseExactDecimalError.numericOverflow) {
            _ = try maximum.adding(one)
        }
    }

    @Test func comparesExtremeScalesWithoutAligningLargeCoefficients() {
        let enormous = DatabaseExactDecimal(
            coefficient: 1,
            scale: Int32.min
        )
        let tiny = DatabaseExactDecimal(
            coefficient: Int64.max,
            scale: Int32.max
        )

        #expect(enormous.compare(to: tiny) == 1)
        #expect(tiny.compare(to: enormous) == -1)
        #expect(enormous.compare(to: enormous) == 0)
    }

    @Test func zeroArithmeticDoesNotExpandExtremeScales() throws {
        let zero = DatabaseExactDecimal(coefficient: 0, scale: Int32.max)
        let enormous = DatabaseExactDecimal(coefficient: 1, scale: Int32.min)

        #expect(try enormous.adding(zero) == enormous)
        #expect(try enormous.subtracting(zero) == enormous)
        #expect(try enormous.multiplying(by: zero) == zero)
    }

    @Test func multiplicationNormalizesBeforeNarrowingToInt64() throws {
        let left = DatabaseExactDecimal(
            coefficient: 4_611_686_018_427_387_904,
            scale: 0
        )
        let right = DatabaseExactDecimal(coefficient: 5, scale: 0)

        #expect(
            try left.multiplying(by: right)
                == DatabaseExactDecimal(
                    coefficient: 2_305_843_009_213_693_952,
                    scale: -1
                )
        )
    }

    @Test func divisionUsesTerminatingDecimalFactorsWithoutExpansionOverflow() throws {
        let maximum = DatabaseExactDecimal(
            coefficient: Int64.max,
            scale: 0
        )
        let ten = DatabaseExactDecimal(coefficient: 10, scale: 0)
        let one = DatabaseExactDecimal(coefficient: 1, scale: 0)
        let forty = DatabaseExactDecimal(coefficient: 40, scale: 0)

        #expect(
            try maximum.dividing(by: ten)
                == DatabaseExactDecimal(
                    coefficient: Int64.max,
                    scale: 1
                )
        )
        #expect(
            try one.dividing(by: forty)
                == DatabaseExactDecimal(coefficient: 25, scale: 3)
        )
        #expect(
            throws: DatabaseExactDecimalError.numericOverflow
        ) {
            _ = try DatabaseExactDecimal(
                coefficient: Int64.min,
                scale: 0
            ).dividing(by: DatabaseExactDecimal(coefficient: -1, scale: 0))
        }
    }

    @Test func remainderUsesModularScalingForExtremePowers() throws {
        let positive = DatabaseExactDecimal(coefficient: 1, scale: -100)
        let negative = DatabaseExactDecimal(coefficient: -1, scale: -100)
        let three = DatabaseExactDecimal(coefficient: 3, scale: 0)
        let muchLargerDivisor = DatabaseExactDecimal(coefficient: 1, scale: -101)

        #expect(
            try positive.remainder(dividingBy: three)
                == DatabaseExactDecimal(coefficient: 1, scale: 0)
        )
        #expect(
            try negative.remainder(dividingBy: three)
                == DatabaseExactDecimal(coefficient: -1, scale: 0)
        )
        #expect(
            try positive.remainder(dividingBy: muchLargerDivisor)
                == positive
        )
    }

    @Test func decimalLexicalFormIsFixedPointAndBounded() throws {
        #expect(
            try DatabaseExactDecimal(
                coefficient: 123,
                scale: 2
            ).decimalLexicalForm(maximumUTF8Count: 16) == "1.23"
        )
        #expect(
            try DatabaseExactDecimal(
                coefficient: -123,
                scale: 5
            ).decimalLexicalForm(maximumUTF8Count: 16) == "-0.00123"
        )
        #expect(
            try DatabaseExactDecimal(
                coefficient: 123,
                scale: -2
            ).decimalLexicalForm(maximumUTF8Count: 16) == "12300"
        )

        let large = DatabaseExactDecimal(coefficient: 1, scale: 129)
        let lexical = try large.decimalLexicalForm(maximumUTF8Count: 132)
        #expect(lexical.utf8.count == 131)
        #expect(!lexical.contains("e"))
        #expect(
            throws: DatabaseExactDecimalLexicalError.representationTooLarge(
                required: 131,
                maximum: 130
            )
        ) {
            _ = try large.decimalLexicalForm(maximumUTF8Count: 130)
        }
    }
}

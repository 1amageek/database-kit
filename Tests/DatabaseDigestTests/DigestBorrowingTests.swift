import DatabaseDigest
import DatabaseValue
import Testing

@Suite("Digest Input Borrowing Tests")
struct DigestBorrowingTests {
    @Test func eachAccumulatorBorrowsOwnedInputOnce() {
        let byteCount = 65_537

        let md5Owner = DigestBorrowCountingOwner(byte: 0xa5, count: byteCount)
        var md5 = MD5Accumulator()
        md5.update(DatabaseBytes(retaining: md5Owner))
        _ = md5.finalize()
        #expect(md5Owner.borrowCount == 1)

        let sha1Owner = DigestBorrowCountingOwner(byte: 0xa5, count: byteCount)
        var sha1 = SHA1Accumulator()
        sha1.update(DatabaseBytes(retaining: sha1Owner))
        _ = sha1.finalize()
        #expect(sha1Owner.borrowCount == 1)

        let sha384Owner = DigestBorrowCountingOwner(
            byte: 0xa5,
            count: byteCount
        )
        var sha384 = SHA384Accumulator()
        sha384.update(DatabaseBytes(retaining: sha384Owner))
        _ = sha384.finalize()
        #expect(sha384Owner.borrowCount == 1)

        let sha512Owner = DigestBorrowCountingOwner(
            byte: 0xa5,
            count: byteCount
        )
        var sha512 = SHA512Accumulator()
        sha512.update(DatabaseBytes(retaining: sha512Owner))
        _ = sha512.finalize()
        #expect(sha512Owner.borrowCount == 1)
    }
}

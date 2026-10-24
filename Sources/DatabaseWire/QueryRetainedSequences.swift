import DatabaseKit

extension QueryRowPage: QueryRows {
    public func makeAsyncIterator() -> QueryRowAsyncIterator {
        QueryRowAsyncIterator(makeRowIterator())
    }
}

extension RDFGraphPage: QueryGraph {
    public func makeAsyncIterator() -> RDFGraphAsyncIterator {
        RDFGraphAsyncIterator(makeQuadIterator())
    }
}

#if DATABASE_KIT_MULTI_BASE
extension QueryBooleanResult: QueryBoolean {}
#endif

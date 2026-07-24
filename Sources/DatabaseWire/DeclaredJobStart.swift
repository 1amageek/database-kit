/// A declared `job.start` operation encoded without an inner payload buffer.
public enum DeclaredJobStart<Job: DatabaseJobDescriptor>:
    DatabaseOperation {
    public typealias Request = JobInvocation<Job>
    public typealias Response = JobStartOperation.Response

    public static var identifier: DatabaseOperationIdentifier { .jobStart }
}

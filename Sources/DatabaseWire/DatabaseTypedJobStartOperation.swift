/// Typed `job.start` operation whose request is encoded without an inner buffer.
public enum DatabaseTypedJobStartOperation<Job: DatabaseJobDescriptor>:
    DatabaseOperation {
    public typealias Request = DatabaseTypedJobStartRequest<Job>
    public typealias Response = JobStartOperation.Response

    public static var identifier: DatabaseOperationIdentifier { .jobStart }
}

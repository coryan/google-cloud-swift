# Mocking long-running operations in tests

<!--
    It seems that swift-docc does not support reference-style links at the bottom of the file:

    https://github.com/swiftlang/swift-docc/issues/685
-->
[Installing Swift]: https://www.swift.org/getting-started/
[Getting Started with Swift]: <doc:quickstart>
[Long-running operations]: <doc:long-running-operations>
[Workflows API]: https://cloud.google.com/workflows
[Long-running Operations AIP]: https://google.aip.dev/151

When writing unit tests for applications that call Google Cloud APIs, you typically want to mock the client library instead of making real network requests or polling GCP services.

The Google Cloud client libraries for Swift generate mockable Swift protocols for each service (such as `Clients.WorkflowsProtocol`). For methods that perform Long-Running Operations (LROs), the protocol declares a single canonical polling method:

```swift
func <methodName>PollingUntilDone(
  request: <RequestType>,
  options: GoogleGax.RequestOptions
) async throws -> any GoogleGax.PollableOperation<<ResponseType>>
```

All convenience overloads (such as omitting the `options:` argument or passing individual parameters) are implemented as protocol extensions that forward to this canonical method. Consequently, a mock only needs to implement `<methodName>PollingUntilDone(request:options:)`.

This guide demonstrates how to mock an LRO helper to simulate operations that complete with success or error.

## The PollableOperation protocol

The return type of an LRO polling helper is `any GoogleGax.PollableOperation<ResponseType>`. This is a Swift protocol defined in `GoogleGax`:

```swift
public protocol PollableOperation<ResponseType> {
  associatedtype ResponseType
  func wait() async throws -> ResponseType
}
```

To mock an LRO in your test target, define a small helper conforming to `PollableOperation`:

@Snippet(path: "MockLongRunningOperationsSuccess", slice: "helper")

## Mock an operation that completes with success

To simulate an operation that successfully creates or modifies a resource:

1. Add the necessary imports:
   @Snippet(path: "MockLongRunningOperationsSuccess", slice: "imports")
2. Define a helper conforming to `PollableOperation`:
   @Snippet(path: "MockLongRunningOperationsSuccess", slice: "helper")
3. Define a mock client conforming to the service protocol (e.g. `Clients.WorkflowsProtocol`):
   @Snippet(path: "MockLongRunningOperationsSuccess", slice: "mock")
4. In your unit test, configure the mock's handler to return a successful result:
   @Snippet(path: "MockLongRunningOperationsSuccess", slice: "handler")
5. Call the operation helper (using either convenience overloads or the canonical method) and await the result:
   @Snippet(path: "MockLongRunningOperationsSuccess", slice: "call")
   @Snippet(path: "MockLongRunningOperationsSuccess", slice: "wait")

## Mock an operation that completes with an error

Long-running operations can fail in two distinct ways:
- **Initiation failure**: The initial RPC that starts the operation throws an error (e.g., permission denied or invalid arguments). You can simulate this by having your mock handler throw an error directly.
- **Operation failure**: The operation is accepted, but during execution on the server it fails or is canceled. In this case, the method returns a `PollableOperation`, but calling `wait()` throws an error.

To simulate an operation that completes with an error:

1. Define a domain or test error:
   @Snippet(path: "MockLongRunningOperationsError", slice: "error_type")
2. Configure the mock's handler to return a failing `MockPollableOperation`:
   @Snippet(path: "MockLongRunningOperationsError", slice: "handler")
3. Call the operation helper and verify that `wait()` throws the expected error:
   @Snippet(path: "MockLongRunningOperationsError", slice: "call")
   @Snippet(path: "MockLongRunningOperationsError", slice: "wait")

## Next steps

* [Long-running operations](long-running-operations.md) describes how to use LRO helpers with live services.
* [Override the default retry policies](override-retry-policy.md) describes how to configure backoff and retry behavior.

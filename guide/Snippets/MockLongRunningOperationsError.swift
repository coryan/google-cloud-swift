// snippet.hide
// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// snippet.show
// snippet.imports
import Foundation
import GoogleCloudWorkflowsV1
import GoogleGax

// snippet.end

// snippet.helper [START swift_mock_lro_error_helper]
/// A test helper conforming to `PollableOperation` that returns a predefined result or throws an error.
struct MockPollableOperation<ResponseType>: PollableOperation {
  let result: Result<ResponseType, any Error>

  func wait() async throws -> ResponseType {
    try result.get()
  }
}
// snippet.end [END swift_mock_lro_error_helper]

// snippet.mock [START swift_mock_lro_error_client]
/// A mock client conforming to `Clients.WorkflowsProtocol`.
final class MockWorkflowsClient: Clients.WorkflowsProtocol, @unchecked Sendable {
  var createWorkflowHandler:
    (
      (CreateWorkflowRequest, GoogleGax.RequestOptions) async throws -> any GoogleGax
        .PollableOperation<Workflow>
    )?

  func createWorkflowPollingUntilDone(
    request: CreateWorkflowRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> any GoogleGax.PollableOperation<Workflow> {
    if let handler = createWorkflowHandler {
      return try await handler(request, options)
    }
    throw GoogleGax.RequestError.unimplemented
  }
}
// snippet.end [END swift_mock_lro_error_client]

// snippet.error [START swift_mock_lro_error_type]
enum WorkflowError: Error, CustomStringConvertible {
  case executionFailed(String)

  var description: String {
    switch self {
    case .executionFailed(let reason):
      return "Workflow execution failed: \(reason)"
    }
  }
}
// snippet.end [END swift_mock_lro_error_type]

// snippet.function [START swift_mock_lro_error_function]
func testFailedWorkflowCreation() async throws {
  // snippet.end [END swift_mock_lro_error_function]
  // snippet.handler [START swift_mock_lro_error_handler]
  let mock = MockWorkflowsClient()

  // Configure the mock to return an operation that fails during execution.
  mock.createWorkflowHandler = { request, options in
    MockPollableOperation(result: .failure(WorkflowError.executionFailed("Quota exceeded")))
  }
  // snippet.end [END swift_mock_lro_error_handler]

  // snippet.call [START swift_mock_lro_error_call]
  let client: any Clients.WorkflowsProtocol = mock
  let operation = try await client.createWorkflowPollingUntilDone(
    parent: "projects/my-project/locations/us-central1",
    workflow: Workflow().with { $0.description = "New workflow" },
    workflowId: "my-wf"
  )
  // snippet.end [END swift_mock_lro_error_call]

  // snippet.wait [START swift_mock_lro_error_wait]
  do {
    _ = try await operation.wait()
    fatalError("Expected operation to fail, but it succeeded")
  } catch let error as WorkflowError {
    print("Mock LRO failed as expected: \(error)")
  }
  // snippet.end [END swift_mock_lro_error_wait]
}

// snippet.hide
@main struct SnippetRunner {
  static func main() async throws {
    try await testFailedWorkflowCreation()
  }
}

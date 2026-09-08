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

import Foundation
import GoogleCloudGax
import GoogleRpc
import Synchronization
import Testing

@Suite struct ServerErrorsPollingErrorPolicyTests {
  @Test func testServerErrorsOnError() {
    let mock = MockPollingPolicy(onError: { _, e in .permanent(e) })
    let policy = mock.continueOnServerErrors()

    #expect(
      policy.onError(state: PollingState(), error: internalServiceError())
        == .retry(internalServiceError()))
    #expect(
      policy.onError(state: PollingState(), error: unavailableServiceError())
        == .retry(unavailableServiceError()))
    #expect(
      policy.onError(state: PollingState(), error: httpError(500))
        == .retry(httpError(500)))
    #expect(
      policy.onError(state: PollingState(), error: httpError(501))
        == .retry(httpError(501)))
    #expect(
      policy.onError(state: PollingState(), error: httpError(502))
        == .retry(httpError(502)))
    #expect(
      policy.onError(state: PollingState(), error: httpError(503))
        == .retry(httpError(503)))
    #expect(
      policy.onError(state: PollingState(), error: httpError(429))
        == .permanent(httpError(429)))
    #expect(
      policy.onError(state: PollingState(), error: httpError(504))
        == .permanent(httpError(504)))
    #expect(policy.onError(state: PollingState(), error: permanent()) == .permanent(permanent()))
  }

  @Test func testServerErrorsOnInProgress() throws {
    let called = Mutex(false)
    let mock = MockPollingPolicy(onInProgress: { _ in
      called.withLock { $0 = true }
    })
    let policy = mock.continueOnServerErrors()

    try policy.onInProgress(state: PollingState())
    #expect(called.withLock { $0 })
  }

  // Helper functions

  private func internalServiceError() -> RequestError {
    .service(
      ServiceError(code: GoogleRpc.Code.`internal`, message: "INTERNAL")
    )
  }

  private func unavailableServiceError() -> RequestError {
    .service(
      ServiceError(code: GoogleRpc.Code.unavailable, message: "UNAVAILABLE")
    )
  }

  private func httpError(_ code: Int) -> RequestError {
    .http(HTTPDetails(http_status_code: code, headers: [:], payload: Data()))
  }

  private func permanent() -> RequestError {
    .service(ServiceError(code: GoogleRpc.Code.permissionDenied, message: "PERMISSION_DENIED"))
  }
}

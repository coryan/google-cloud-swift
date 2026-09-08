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
import Testing

@Suite struct ServerErrorsRetryPolicyTests {
  @Test func testServerErrorsOnError() {
    let policy = NeverRetry().retryOnServerErrors()
    let state = RetryState(idempotent: true)

    #expect(
      policy.onError(state: state, error: internalServiceError())
        == .retry(internalServiceError()))
    #expect(
      policy.onError(state: state, error: unavailableServiceError())
        == .retry(unavailableServiceError()))
    #expect(policy.onError(state: state, error: httpError(500)) == .retry(httpError(500)))
    #expect(policy.onError(state: state, error: httpError(501)) == .retry(httpError(501)))
    #expect(policy.onError(state: state, error: httpError(502)) == .retry(httpError(502)))
    #expect(policy.onError(state: state, error: httpError(503)) == .retry(httpError(503)))

    #expect(policy.onError(state: state, error: httpError(429)) == .exhausted(httpError(429)))
    #expect(policy.onError(state: state, error: httpError(504)) == .exhausted(httpError(504)))
    #expect(policy.onError(state: state, error: permanent()) == .exhausted(permanent()))
  }

  @Test func testServerErrorsExt() {
    let policy = NeverRetry().retryOnServerErrors()
    let state = RetryState(idempotent: true)

    #expect(
      policy.onError(state: state, error: internalServiceError())
        == .retry(internalServiceError()))
    #expect(policy.onError(state: state, error: httpError(500)) == .retry(httpError(500)))
    #expect(policy.onError(state: state, error: permanent()) == .exhausted(permanent()))
  }

  @Test func testServerErrorsForwards() {
    let mock = MockPolicy(
      onError: { _, e in .permanent(e) },
      onThrottle: { _, e in .exhausted(e) },
      remainingTime: { _ in nil }
    )

    let policy = ServerErrors(inner: mock)
    let state = RetryState(idempotent: true)

    #expect(policy.onError(state: state, error: permanent()) == .permanent(permanent()))
    #expect(
      policy.onError(state: state, error: internalServiceError())
        == .retry(internalServiceError()))

    #expect(policy.onThrottle(state: state, error: permanent()) == .exhausted(permanent()))
    #expect(
      policy.onThrottle(state: state, error: internalServiceError())
        == .exhausted(internalServiceError()))

    #expect(policy.remainingTime(state: state) == nil)
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

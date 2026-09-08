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

extension ServerErrors: PollingErrorPolicy where P: PollingErrorPolicy {
  public func onError(state: PollingState, error: RequestError) -> PollingResult {
    if isServerError(error) {
      return .retry(error)
    }
    return inner.onError(state: state, error: error)
  }

  public func onInProgress(state: PollingState) throws {
    try inner.onInProgress(state: state)
  }
}

extension PollingErrorPolicy {
  /// Decorate a ``PollingErrorPolicy`` to continue on server errors.
  ///
  /// This policy decorates an inner policy and continues on errors with HTTP status code
  /// 500, 501, 502, or 503 **or** where the service returns an error with code
  /// `internal` or `unavailable`.
  ///
  /// For other errors it returns the same value as the inner policy.
  public func continueOnServerErrors() -> ServerErrors<Self> {
    ServerErrors(inner: self)
  }
}

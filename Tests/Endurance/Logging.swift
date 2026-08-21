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

struct StructuredLog: Codable, Sendable {
  let severity: String
  let labels: [String: String]
  let message: String
}

func reportError(_ error: any Error, task: String) {
  let log = StructuredLog(
    severity: "error",
    labels: [
      "application": "endurance-test",
      "version": "0.1.0",
      "task": task,
    ],
    message: "\(error)"
  )
  if let data = try? JSONEncoder().encode(log),
    let jsonString = String(data: data, encoding: .utf8)
  {
    FileHandle.standardError.write(Data((jsonString + "\n").utf8))
  } else {
    FileHandle.standardError.write(Data("{\"severity\":\"error\",\"message\":\"\(error)\"}\n".utf8))
  }
}

func reportInfo(_ message: String, task: String) {
  let log = StructuredLog(
    severity: "info",
    labels: [
      "application": "endurance-test",
      "version": "0.1.0",
      "task": task,
    ],
    message: message
  )
  if let data = try? JSONEncoder().encode(log),
    let jsonString = String(data: data, encoding: .utf8)
  {
    FileHandle.standardOutput.write(Data((jsonString + "\n").utf8))
  } else {
    print("{\"severity\":\"info\",\"message\":\"\(message)\"}")
  }
}

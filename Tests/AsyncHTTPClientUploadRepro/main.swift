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

import ArgumentParser
import AsyncHTTPClient
import Foundation
import GoogleCloudAuth
import NIOCore

actor ReproCounters {
  private(set) var successes: UInt64 = 0
  private(set) var failures: UInt64 = 0
  private(set) var activeTasks: UInt64 = 0

  func taskStarted() {
    activeTasks &+= 1
  }

  func taskFinished() {
    activeTasks &-= 1
  }

  func recordSuccess() {
    successes &+= 1
  }

  func recordFailure() {
    failures &+= 1
  }

  func snapshot() -> (successes: UInt64, failures: UInt64, activeTasks: UInt64) {
    (successes, failures, activeTasks)
  }
}

@main
struct AsyncHTTPClientUploadRepro: AsyncParsableCommand, Sendable {
  @Option(name: .customLong("bucket-name"), help: "Target GCS bucket name.")
  var bucketName: String

  @Option(name: .customLong("task-count"), help: "Number of concurrent worker tasks.")
  var taskCount: Int = 768

  @Option(name: .customLong("iterations"), help: "Iterations per worker task.")
  var iterations: Int = 100_000

  @Option(name: .customLong("object-size"), help: "Payload size in bytes (buffered).")
  var objectSize: Int = 32 * 1024

  @Option(name: .customLong("client-count"), help: "Number of AsyncHTTPClient instances.")
  var clientCount: Int = 1

  func run() async throws {
    let credentials = try Credentials()
    let clients: [HTTPClient] = (0..<clientCount).map { _ in
      HTTPClient(eventLoopGroupProvider: .singleton)
    }
    defer {
      Task { [clients] in
        for client in clients {
          try? await client.shutdown()
        }
      }
    }

    var tempBuffer = ByteBufferAllocator().buffer(capacity: objectSize)
    tempBuffer.writeRepeatingByte(0x42, count: objectSize)
    let buffer = tempBuffer

    let counters = ReproCounters()
    let startTime = ContinuousClock.now

    let monitorTask = Task {
      var lastSuccesses: UInt64 = 0
      var lastTime = ContinuousClock.now
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        if Task.isCancelled { break }
        let now = ContinuousClock.now
        let (successes, failures, activeTasks) = await counters.snapshot()
        let elapsedTotal = startTime.duration(to: now)
        let elapsedInterval = lastTime.duration(to: now)
        let deltaSuccesses = successes - lastSuccesses
        let intervalSeconds = Double(elapsedInterval.components.seconds) + Double(elapsedInterval.components.attoseconds) / 1e18
        let rate = intervalSeconds > 0 ? Double(deltaSuccesses) / intervalSeconds : 0.0
        let rss = Self.readRssAnon()

        logToStderr(
          "[Elapsed: \(Int(elapsedTotal.components.seconds))s] [\(rss)] [Active: \(activeTasks)] [Success: \(successes)] [Fail: \(failures)] [Rate: \(String(format: "%.1f", rate)) ops/s]"
        )

        lastSuccesses = successes
        lastTime = now
      }
    }
    defer {
      monitorTask.cancel()
    }

    logToStderr("Starting repro with \(taskCount) tasks, \(clientCount) clients, \(objectSize) bytes payload...")

    try await withThrowingTaskGroup(of: Void.self) { group in
      for taskIndex in 0..<taskCount {
        let client = clients[taskIndex % clients.count]
        group.addTask {
          await self.runWorker(
            taskIndex: taskIndex,
            client: client,
            credentials: credentials,
            buffer: buffer,
            counters: counters
          )
        }
      }
      try await group.waitForAll()
    }

    let (finalSuccesses, finalFailures, _) = await counters.snapshot()
    let totalElapsed = startTime.duration(to: ContinuousClock.now)
    logToStderr(
      "DONE in \(Int(totalElapsed.components.seconds))s. Success: \(finalSuccesses), Failures: \(finalFailures)"
    )
  }

  private func runWorker(
    taskIndex: Int,
    client: HTTPClient,
    credentials: Credentials,
    buffer: NIOCore.ByteBuffer,
    counters: ReproCounters
  ) async {
    await counters.taskStarted()
    defer {
      Task { await counters.taskFinished() }
    }

    let baseURL = "https://storage.googleapis.com/upload/storage/v1/b/\(bucketName)/o"

    for _ in 0..<iterations {
      let objectName = Self.randomObjectName()
      guard let url = URL(string: "\(baseURL)?uploadType=media&name=\(objectName)") else {
        await counters.recordFailure()
        continue
      }

      do {
        let authHeaders = try await credentials.headers()
        var request = HTTPClientRequest(url: url.absoluteString)
        request.method = .POST
        for (name, value) in authHeaders {
          request.headers.add(name: name, value: value)
        }
        request.headers.add(name: "Content-Type", value: "application/octet-stream")
        request.body = .bytes(buffer)

        let response = try await client.execute(request, timeout: .seconds(30))
        for try await _ in response.body {}

        if (200..<300).contains(response.status.code) {
          await counters.recordSuccess()
        } else {
          await counters.recordFailure()
        }
      } catch {
        await counters.recordFailure()
      }
    }
  }

  private static func randomObjectName() -> String {
    let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "repro-" + String((0..<32).map { _ in charset.randomElement()! })
  }

  private static func readRssAnon() -> String {
    guard let content = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else {
      return "RssAnon: unknown"
    }
    for line in content.split(separator: "\n") {
      if line.hasPrefix("RssAnon:") {
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return "RssAnon: unknown"
  }
}

private func logToStderr(_ message: String) {
  let line = message.hasSuffix("\n") ? message : message + "\n"
  if let data = line.data(using: .utf8) {
    FileHandle.standardError.write(data)
  }
}

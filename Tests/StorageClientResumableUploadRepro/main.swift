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
import Foundation
import GoogleCloudAuth
import GoogleCloudStorage
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

struct ChunkSequence: AsyncSequence, Sendable {
  typealias Element = NIOCore.ByteBuffer

  let buffer: NIOCore.ByteBuffer
  let chunkSize: Int

  struct AsyncIterator: AsyncIteratorProtocol {
    var buffer: NIOCore.ByteBuffer
    let chunkSize: Int

    mutating func next() async throws -> NIOCore.ByteBuffer? {
      if buffer.readableBytes == 0 { return nil }
      let count = Swift.min(chunkSize, buffer.readableBytes)
      return buffer.readSlice(length: count)
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(buffer: buffer, chunkSize: chunkSize)
  }
}

@main
struct StorageClientResumableUploadRepro: AsyncParsableCommand, Sendable {
  @Option(name: .customLong("bucket-name"), help: "Target GCS bucket name.")
  var bucketName: String

  @Option(name: .customLong("task-count"), help: "Number of concurrent worker tasks.")
  var taskCount: Int = 256

  @Option(name: .customLong("iterations"), help: "Iterations per worker task.")
  var iterations: Int = 2000

  @Option(name: .customLong("object-size"), help: "Payload size in bytes.")
  var objectSize: Int = 32 * 1024

  @Option(name: .customLong("client-count"), help: "Number of StorageClient instances.")
  var clientCount: Int = 1

  @Flag(name: .customLong("stream-body"), help: "Stream body via StreamSource instead of BytesSource.")
  var streamBody: Bool = false

  func run() async throws {
    let credentials = try Credentials()
    var storageClients: [StorageClient] = []
    for _ in 0..<clientCount {
      storageClients.append(
        try StorageClient(
          .init().with {
            $0.client = .init().with { $0.credentials = credentials }
          }
        )
      )
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

    let streamBody = self.streamBody
    logToStderr(
      "Starting StorageClientResumableUploadRepro with \(taskCount) tasks, \(clientCount) clients, \(objectSize) bytes payload, streaming: \(streamBody), resumable: true..."
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      for taskIndex in 0..<taskCount {
        let client = storageClients[taskIndex % storageClients.count]
        group.addTask {
          await self.runWorker(
            taskIndex: taskIndex,
            client: client,
            buffer: buffer,
            streamBody: streamBody,
            counters: counters
          )
        }
      }
      try await group.waitForAll()
    }

    // Allow background activities to settle
    try? await Task.sleep(for: .milliseconds(200))

    let (finalSuccesses, finalFailures, _) = await counters.snapshot()
    let totalElapsed = startTime.duration(to: ContinuousClock.now)
    logToStderr(
      "DONE in \(Int(totalElapsed.components.seconds))s. Success: \(finalSuccesses), Failures: \(finalFailures)"
    )
  }

  private func runWorker(
    taskIndex: Int,
    client: StorageClient,
    buffer: NIOCore.ByteBuffer,
    streamBody: Bool,
    counters: ReproCounters
  ) async {
    await counters.taskStarted()
    defer {
      Task { await counters.taskFinished() }
    }

    // Force resumable upload for all payloads by setting threshold to 0.
    let options = UploadOptions().with {
      $0.resumableUploadThreshold = 0
      $0.chunkSize = 32 * 1024 * 1024
    }

    for _ in 0..<iterations {
      let objectName = Self.randomObjectName()
      do {
        if streamBody {
          let stream = ChunkSequence(buffer: buffer, chunkSize: 16 * 1024)
          let source = StreamSource(sequence: stream, totalSize: Int64(buffer.readableBytes))
          let _ = try await client.upload(source, to: bucketName, as: objectName, options: options)
        } else {
          let source = BytesSource(buffer: .init(buffer))
          let _ = try await client.upload(source, to: bucketName, as: objectName, options: options)
        }
        await counters.recordSuccess()
      } catch {
        logToStderr("Upload request threw error: \(error)")
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

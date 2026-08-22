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

@main
struct StorageW1R3: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "StorageW1R3",
    abstract: "W1R3 Benchmark for Google Cloud Storage Swift client library.",
    discussion: """
      Benchmarks the Cloud Storage client library. The benchmark uploads an object and
      reads it multiple times (default 3), reporting single-stream upload and download bandwidth.
      """
  )

  @Option(
    name: .customLong("bucket-name"),
    help: "The name of the GCS bucket used by the benchmark."
  )
  var bucketName: String

  @Option(
    name: .customLong("min-object-size"),
    help: "The minimum object size (e.g. 0, 128KiB, 1MiB).",
    transform: SizeParser.parse
  )
  var minObjectSize: Int = 0

  @Option(
    name: .customLong("max-object-size"),
    help: "The maximum object size (e.g. 128KiB, 1MiB, 16MiB).",
    transform: SizeParser.parse
  )
  var maxObjectSize: Int = 0

  @Option(
    name: .customLong("task-count"),
    help: "The number of concurrent tasks running the benchmark."
  )
  var taskCount: Int = 1

  @Option(
    name: .customLong("iterations"),
    help: "The number of iterations for each task."
  )
  var iterations: Int = 1

  @Option(
    name: .customLong("min-delete-batch"),
    help: "The minimum size for the delete batch."
  )
  var minDeleteBatch: Int = 20

  @Option(
    name: .customLong("max-delete-batch"),
    help: "The maximum size for the delete batch."
  )
  var maxDeleteBatch: Int = 20

  @Option(
    name: .customLong("retry-timeout"),
    help: "The maximum time for the retry loop (e.g. 900s).",
    transform: DurationParser.parse
  )
  var retryTimeout: Duration?

  @Option(
    name: .customLong("attempt-timeout"),
    help: "The maximum time for each attempt (e.g. 30s).",
    transform: DurationParser.parse
  )
  var attemptTimeout: Duration = .seconds(30)

  @Option(
    name: .customLong("rampup-period"),
    help: "The rampup period between new tasks (e.g. 500ms).",
    transform: DurationParser.parse
  )
  var rampupPeriod: Duration = .milliseconds(500)

  @Option(
    name: .customLong("read-count"),
    help: "Sets the number of reads on each object."
  )
  var readCount: Int = 3

  @Flag(
    name: .customLong("no-delete"),
    help: "Skip deleting objects after the test."
  )
  var noDelete: Bool = false

  @Flag(
    name: .customLong("debug-retry"),
    help: "Enable debug logs for retry policies."
  )
  var debugRetry: Bool = false

  func validate() throws {
    guard minObjectSize <= maxObjectSize else {
      throw ValidationError(
        "Invalid object size range: min (\(minObjectSize)) > max (\(maxObjectSize))")
    }
    guard minDeleteBatch <= maxDeleteBatch else {
      throw ValidationError(
        "Invalid delete batch size range: min (\(minDeleteBatch)) > max (\(maxDeleteBatch))")
    }
    guard taskCount >= 1 else {
      throw ValidationError("task-count must be at least 1")
    }
    guard iterations >= 1 else {
      throw ValidationError("iterations must be at least 1")
    }
    guard readCount >= 0 else {
      throw ValidationError("read-count must be non-negative")
    }
  }

  func run() async throws {
    let runner = BenchmarkRunner(
      bucketName: bucketName,
      minObjectSize: minObjectSize,
      maxObjectSize: maxObjectSize,
      taskCount: taskCount,
      iterations: iterations,
      minDeleteBatch: minDeleteBatch,
      maxDeleteBatch: maxDeleteBatch,
      rampupPeriod: rampupPeriod,
      readCount: readCount,
      noDelete: noDelete
    )
    try await runner.execute()
  }
}

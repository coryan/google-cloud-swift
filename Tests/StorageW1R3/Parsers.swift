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

enum SizeParser {
  /// Parses size strings such as "128KiB", "1MiB", "10MB", "1024", "0" into bytes.
  static func parse(_ input: String) throws -> Int {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw ValidationError("Size cannot be empty")
    }

    if let direct = Int(trimmed) {
      guard direct >= 0 else {
        throw ValidationError("Size cannot be negative: \(input)")
      }
      return direct
    }

    let units: [(suffix: String, multiplier: Int)] = [
      ("tib", 1024 * 1024 * 1024 * 1024),
      ("tb", 1000 * 1000 * 1000 * 1000),
      ("gib", 1024 * 1024 * 1024),
      ("gb", 1000 * 1000 * 1000),
      ("g", 1024 * 1024 * 1024),
      ("mib", 1024 * 1024),
      ("mb", 1000 * 1000),
      ("m", 1024 * 1024),
      ("kib", 1024),
      ("kb", 1000),
      ("k", 1024),
      ("b", 1),
    ]

    let lower = trimmed.lowercased()
    for unit in units {
      if lower.hasSuffix(unit.suffix) {
        let numericPart = String(trimmed.dropLast(unit.suffix.count))
          .trimmingCharacters(in: .whitespaces)
        if let value = Double(numericPart) {
          guard value >= 0 else {
            throw ValidationError("Size cannot be negative: \(input)")
          }
          return Int(value * Double(unit.multiplier))
        }
      }
    }

    throw ValidationError(
      "Invalid size format: '\(input)'. Expected values like '128KiB', '1MiB', '10MB', etc.")
  }
}

enum DurationParser {
  /// Parses duration strings such as "500ms", "30s", "5m", "1h" into `Duration`.
  static func parse(_ input: String) throws -> Duration {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw ValidationError("Duration cannot be empty")
    }

    let lower = trimmed.lowercased()
    if lower.hasSuffix("ms") {
      let numStr = String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces)
      guard let ms = Double(numStr), ms >= 0 else {
        throw ValidationError("Invalid millisecond duration: \(input)")
      }
      return .milliseconds(ms)
    } else if lower.hasSuffix("s") {
      let numStr = String(trimmed.dropLast(1)).trimmingCharacters(in: .whitespaces)
      guard let s = Double(numStr), s >= 0 else {
        throw ValidationError("Invalid second duration: \(input)")
      }
      return .seconds(s)
    } else if lower.hasSuffix("m") {
      let numStr = String(trimmed.dropLast(1)).trimmingCharacters(in: .whitespaces)
      guard let m = Double(numStr), m >= 0 else {
        throw ValidationError("Invalid minute duration: \(input)")
      }
      return .seconds(m * 60)
    } else if lower.hasSuffix("h") {
      let numStr = String(trimmed.dropLast(1)).trimmingCharacters(in: .whitespaces)
      guard let h = Double(numStr), h >= 0 else {
        throw ValidationError("Invalid hour duration: \(input)")
      }
      return .seconds(h * 3600)
    } else if let s = Double(trimmed), s >= 0 {
      return .seconds(s)
    }

    throw ValidationError(
      "Invalid duration format: '\(input)'. Expected values like '500ms', '30s', '5m', etc.")
  }
}

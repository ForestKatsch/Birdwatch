//
//  RetryPolicy.swift
//  Birdwatch
//
//  Created by Forest Katsch on 8/12/25.
//

import Foundation

/// Defines a retry policy for queries.
public struct RetryPolicy: Sendable {
  public var maxAttempts: Int

  /// Called after each consecutive failure with the attempt number (1-based).
  /// Return the number of seconds to wait before retrying. Return `nil` to stop retrying.
  public var delaySeconds: (@Sendable (Int) -> TimeInterval?)?

  /// Default to 3 retries and exponential backoff, capped at 30s.
  public static let `default` = RetryPolicy(maxAttempts: 3) { attempt in
    min(30, pow(2.0, Double(attempt)))
  }

  public static let never = RetryPolicy(maxAttempts: 0)

  public init(maxAttempts: Int, delaySeconds: (@Sendable (Int) -> TimeInterval?)? = nil) {
    self.maxAttempts = maxAttempts
    self.delaySeconds = delaySeconds
  }
}

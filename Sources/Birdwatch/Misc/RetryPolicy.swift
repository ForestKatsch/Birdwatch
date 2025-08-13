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
    
    /// This function is called by the query client after each consecutive failure, passing in the number of consecutive failures; then waits for the returned duration. If `nil` is returned, the query will not be retried.
    public var delay: (@Sendable (Int) -> Duration?)?
    
    /// Default to 3 retries and exponential backoff.
    public static let `default` = RetryPolicy(maxAttempts: 3) { attempt in
            .seconds(Int64(min(30, pow(2.0, Double(attempt))) ))
    }
    
    public static let never = RetryPolicy(maxAttempts: 0)
}

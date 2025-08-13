//
//  QueryConfig.swift
//  Birdwatch
//
//  Created by Forest Katsch on 8/12/25.
//

import Foundation

public struct QueryConfig: Sendable {
    /// How long it takes for a query to become stale. After this time, it will be refetched if a new query makes use of it.
    public var staleTime: TimeInterval = 30
    
    /// How long the data for a query will remain in memory after the last query makes use of it.
    public var cacheTime: TimeInterval = 300
    
    ///
    public var retry: RetryPolicy = .default
    
    /// Automatically refetch all stale queries immediately when the app returns to the foreground. TODO
    public var refetchOnFocus: Bool = true

    public init(staleTime: TimeInterval = 30, cacheTime: TimeInterval = 300, retry: RetryPolicy = .default, refetchOnFocus: Bool = true) {
        self.staleTime = staleTime
        self.cacheTime = cacheTime
        self.retry = retry
        self.refetchOnFocus = refetchOnFocus
    }
}

//
//  QueryStatus.swift
//  Birdwatch
//
//  Created by Forest Katsch on 8/12/25.
//

public enum QueryStatus: Equatable, Sendable {
    /// The query has been created, but has no data and is not loading.
    case idle
    
    /// The query has started fetching but there is no data yet. This includes all retries, if configured.
    case loading
    
    /// The query has successfully fetched.
    case success
    
    /// The query was retried (using the specified retry policy) and was not successful.
    case error
}

//
//  QueryFetcher.swift
//  Birdwatch
//
//  Created by Forest Katsch on 8/12/25.
//

public protocol QueryFetcher: Sendable {
    associatedtype Output: Sendable
    associatedtype Key: Hashable & Sendable
    func fetch(for key: Key) async throws -> Output
}

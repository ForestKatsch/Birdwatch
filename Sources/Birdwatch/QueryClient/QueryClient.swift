//
//  QueryClient.swift
//  Birdwatch
//
//  Created by Forest Katsch on 8/12/25.
//

import Foundation

@MainActor
public final class QueryClient<Key: Hashable & Sendable, Output: Sendable> {
    public let config: QueryConfig
    private let cache = QueryCache<Key, Output>()
    private let inFlight = InFlight<Key, Output>()
    private let fetcher: @Sendable (Key) async throws -> Output
    
    public init(config: QueryConfig = .init(), fetcher: @escaping @Sendable (Key) async throws -> Output) {
        self.config = config
        self.fetcher = fetcher
        startGC()
    }
    
    public func ensureQuery(_ key: Key, force: Bool = false) async {
        // Decide if we need to fetch
        let now = Date()
        let stale = await cache.get(key).map { now.timeIntervalSince($0.updatedAt) > config.staleTime } ?? true
        if force || stale {
            await fetch(key)
        }
    }
    
    public func read(_ key: Key) async -> QueryCache<Key,Output>.Record? {
        await cache.get(key)
    }
    
    /*
     public func invalidate(_ predicate: (Key) -> Bool) async {
     // Mark stale by setting updatedAt far in past
     // and optionally trigger refetch for observed records
     // (implementation detail omitted for brevity)
     }
     */
    
    private func fetch(_ key: Key) async {
        if let existing = await inFlight.get(key) {
            _ = try? await existing.value; return
        }
        await cache.set(key, .init(data:nil, error:nil, status:.loading, updatedAt: Date(), observers: (await cache.get(key))?.observers ?? 0))
        let task = Task(priority: .userInitiated) { [fetcher, config] () async throws -> Output in
            var lastError: Error?
            for attempt in 1...max(1, config.retry.maxAttempts) {
                do { return try await fetcher(key) }
                catch {
                    lastError = error
                    if attempt == config.retry.maxAttempts { throw error }
                    if let delayClosure = config.retry.delay, let duration = delayClosure(attempt) {
                        try? await Task.sleep(for: duration)
                    }
                }
            }
            throw lastError! // unreachable
        }
        await inFlight.set(key, task: task)
        do {
            let data = try await task.value
            await cache.set(key, .init(data: data, error: nil, status: .success, updatedAt: Date(), observers: (await cache.get(key))?.observers ?? 0))
        } catch {
            await cache.set(key, .init(data: nil, error: error, status: .error, updatedAt: Date(), observers: (await cache.get(key))?.observers ?? 0))
        }
        await inFlight.clear(key)
    }
    
    private func startGC() {
        Task.detached { [weak self] in
            guard let self else { return }
            while true {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.cache.removeIfExpired(now: Date(), cacheTime: self.config.cacheTime)
            }
        }
    }
    
    // In QueryClient
    public func updates(for key: Key) async -> AsyncStream<QueryCache<Key, Output>.Record> {
        await cache.updates(for: key)
    }
    
    public func appReachedForeground() {
        Task { @MainActor in
            let keysToRefetch = await cache.refetchAllStale()
            
            // Fetch each key in parallel
            await withTaskGroup(of: Void.self) { group in
                for key in keysToRefetch {
                    group.addTask { await self.fetch(key) }
                }
            }
        }
    }
}


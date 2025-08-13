//
//  QueryCache.swift
//  Birdwatch
//
//  Created by Forest Katsch on 8/12/25.
//

import Foundation

public actor QueryCache<Key: Hashable & Sendable, Output: Sendable> {
    public struct Record: @unchecked Sendable {
        // Error isn’t Sendable, so we use @unchecked Sendable here.
        var data: Output?
        var error: Error?
        var status: QueryStatus
        var updatedAt: Date
        var observers: Int
    }
    
    private var storage: [Key: Record] = [:]
    private var subscribers: [Key: [UUID: AsyncStream<Record>.Continuation]] = [:]
    
    func get(_ key: Key) -> Record? { storage[key] }
    func set(_ key: Key, _ record: Record) {
        storage[key] = record
        if let dict = subscribers[key] {
            for (_, cont) in dict { cont.yield(record) }
        }
    }
    
    func removeIfExpired(now: Date, cacheTime: TimeInterval) {
        let keysToRemove = storage.filter { (_, rec) in
            now.timeIntervalSince(rec.updatedAt) > cacheTime && rec.observers == 0
        }.map { $0.key }
        
        for key in keysToRemove {
            storage.removeValue(forKey: key)
            if let dict = subscribers[key] {
                for (_, cont) in dict { cont.finish() }
                subscribers[key] = nil
            }
        }
    }
    
    /// Increments the observer count for the specified key in the cache.
    ///
    /// If no record exists for the given key, a new record is created with an initial observer count of 1
    /// and default values for other properties.
    ///
    /// - Parameter key: The key for which the observer count should be incremented or created.
    func retain(_ key: Key) {
        storage[key, default: .init(data: nil, error: nil, status: .idle, updatedAt: .distantPast, observers: 0)].observers += 1
    }
    
    /// Decrements the observer count for the specified key in the cache.
    ///
    /// This method reduces the `observers` property of the `Record` associated with the given key by 1,
    /// ensuring that the count does not fall below zero.
    /// If the key does not exist in the storage, this method has no effect.
    ///
    /// - Parameter key: The key whose observer count should be decremented.
    func release(_ key: Key) { storage[key]?.observers = max(0, (storage[key]?.observers ?? 0) - 1) }
    
    func updates(for key: Key) -> AsyncStream<Record> {
        let id = UUID()
        return AsyncStream { continuation in
            // Immediately emit current value if present
            if let rec = storage[key] {
                continuation.yield(rec)
            }
            var bucket = subscribers[key] ?? [:]
            bucket[id] = continuation
            subscribers[key] = bucket
            
            continuation.onTermination = { [weak self] _ in
                Task { await self?.unsubscribe(key: key, id: id) }
            }
        }
    }
    
    private func unsubscribe(key: Key, id: UUID) {
        subscribers[key]?[id] = nil
        if subscribers[key]?.isEmpty == true { subscribers[key] = nil }
    }
    
    func refetchAllStale() -> [Key] {
        let now = Date()
        return storage.filter { key, rec in
            rec.observers > 0 && rec.updatedAt.addingTimeInterval(1) < now
        }.map(\.key)
    }
}

public actor InFlight<Key: Hashable & Sendable, Output: Sendable> {
    private var tasks: [Key: Task<Output, Error>] = [:]
    func get(_ key: Key) -> Task<Output, Error>? { tasks[key] }
    func set(_ key: Key, task: Task<Output, Error>) { tasks[key] = task }
    func clear(_ key: Key) { tasks[key] = nil }
}

//
//  AnyQueryRecord.swift
//  Birdwatch
//
//  Created by Forest Katsch on 8/12/25.
//

import Foundation

// MARK: - Sendable erasers

/// Type-erased box for values that need to cross actor boundaries.
/// Use only for values you treat immutably.
public struct AnySendable: @unchecked Sendable {
  public let base: Any
  public init(_ base: Any) { self.base = base }
}

/// Type-erased, Sendable Error wrapper.
public struct AnySendableError: Error, @unchecked Sendable {
  public let base: any Error
  public init(_ base: any Error) { self.base = base }
}

// MARK: - Record used by the type-erased client

public struct AnyQueryRecord: @unchecked Sendable {
  public let data: AnySendable?
  public let error: AnySendableError?
  public let status: QueryStatus

  public init(data: Any?, error: (any Error)?, status: QueryStatus) {
    self.data = data.map(AnySendable.init)
    self.error = error.map(AnySendableError.init)
    self.status = status
  }
}

// MARK: - Type-erased client surface for SwiftUI environment

public protocol AnyQueryClient: Sendable {
  func readAny(_ key: AnyHashable) async -> AnyQueryRecord?
  func ensureQueryAny(_ key: AnyHashable) async
  func updatesAny(for key: AnyHashable) -> AsyncStream<AnyQueryRecord>
  func retainAny(_ key: AnyHashable) async
  func releaseAny(_ key: AnyHashable) async
}

// MARK: - Adapter over your generic QueryClient

/// Bridges any concrete `QueryClient<K, V>` into the type-erased surface.
/// This allows users to use QueryClient with their specific types and still work with SwiftUI environment.
/// Note: We mark this `@unchecked Sendable` because it holds a reference type. The
/// underlying client should be actor-contained and safe to share.
public final class QueryClientAdapter<K: Hashable & Sendable, V: Sendable>: AnyQueryClient, @unchecked Sendable {
  private let client: QueryClient<K, V>
  public init(_ client: QueryClient<K, V>) { self.client = client }

  public func readAny(_ key: AnyHashable) async -> AnyQueryRecord? {
    guard let k = key as? K, let rec = await client.read(k) else { return nil }
    return AnyQueryRecord(data: rec.data, error: rec.error, status: rec.status)
  }

  public func ensureQueryAny(_ key: AnyHashable) async {
    guard let k = key as? K else { return }
    await client.ensureQuery(k)
  }

  public func updatesAny(for key: AnyHashable) -> AsyncStream<AnyQueryRecord> {
    guard let k = key as? K else { return AsyncStream { $0.finish() } }
    return AsyncStream { cont in
      Task {
        let stream = await client.updates(for: k)
        for await rec in stream {
          cont.yield(AnyQueryRecord(data: rec.data, error: rec.error, status: rec.status))
        }
        cont.finish()
      }
    }
  }

  public func retainAny(_ key: AnyHashable) async {
    guard let k = key as? K else { return }
    await client.retain(k)
  }

  public func releaseAny(_ key: AnyHashable) async {
    guard let k = key as? K else { return }
    await client.release(k)
  }
}

// MARK: - Convenience extension for easy adapter creation

extension QueryClient {
  /// Creates a type-erased adapter for this query client that can be used with SwiftUI environment.
  public func eraseToAnyQueryClient() -> QueryClientAdapter<Key, Output> {
    QueryClientAdapter(self)
  }
}

// MARK: - No-op default client for environment fallback

public struct DefaultQueryClient: AnyQueryClient, Sendable {
  public init() {}
  public func readAny(_ key: AnyHashable) async -> AnyQueryRecord? { nil }
  public func ensureQueryAny(_ key: AnyHashable) async {}
  public func updatesAny(for key: AnyHashable) -> AsyncStream<AnyQueryRecord> {
    AsyncStream { $0.finish() }
  }
  public func retainAny(_ key: AnyHashable) async {}
  public func releaseAny(_ key: AnyHashable) async {}
}

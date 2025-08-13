//
//  Query.swift
//  Birdwatch
//
//  Created by Forest Katsch on 8/12/25.
//

import SwiftUI

// MARK: - Environment key for a type-erased query client

public struct QueryClientEnvironmentKey: EnvironmentKey {
  public static let defaultValue: any AnyQueryClient = DefaultQueryClient()
}

extension EnvironmentValues {
  public var queryClient: any AnyQueryClient {
    get { self[QueryClientEnvironmentKey.self] }
    set { self[QueryClientEnvironmentKey.self] = newValue }
  }
}

// MARK: - UI-facing query state

public enum QueryPhase<Output> {
  case idle
  case loading
  case success(Output)
  case error(any Error)
}

public struct QueryState<Output> {
  public var phase: QueryPhase<Output>
  public init(_ phase: QueryPhase<Output> = .idle) { self.phase = phase }
  public var data: Output? {
    if case let .success(value) = phase { return value }
    return nil
  }
  public var error: (any Error)? {
    if case let .error(err) = phase { return err }
    return nil
  }
  public var isLoading: Bool {
    if case .loading = phase { return true }
    return false
  }
}

// MARK: - @Query property wrapper

@propertyWrapper
public struct Query<Key: Hashable & Sendable, Output: Sendable>: DynamicProperty {
  private let key: Key
  @Environment(\ ..queryClient) private var client
  @State private var state: QueryState<Output> = .init(.idle)
  @State private var subscriptionTask: Task<Void, Never>? = nil
  @State private var lastKeyHash: AnyHashable? = nil

  public init(_ key: Key) {
    self.key = key
  }

  public var wrappedValue: QueryState<Output> { state }

  public mutating func update() {
    let anyKey = AnyHashable(key)
    // Re-subscribe if key changed
    if lastKeyHash != anyKey {
      lastKeyHash = anyKey
      subscriptionTask?.cancel()
      state = .init(.idle)
      subscriptionTask = Task { @MainActor in
        // Seed with existing cache value if present
        if let existing = await client.readAny(anyKey) {
          apply(record: existing)
        }
        // Ensure a fetch occurs if needed
        await client.ensureQueryAny(anyKey)
        // Stream updates
        for await record in client.updatesAny(for: anyKey) {
          apply(record: record)
        }
      }
    }
  }

  @MainActor
  private func apply(record: AnyQueryRecord) {
    switch record.status {
    case .idle:
      state = .init(.idle)
    case .loading:
      state = .init(.loading)
    case .success:
      if let boxed = record.data?.base as? Output {
        state = .init(.success(boxed))
      } else {
        state = .init(
          .error(
            NSError(
              domain: "Birdwatch", code: 1,
              userInfo: [NSLocalizedDescriptionKey: "Type mismatch for query data"])))
      }
    case .error:
      if let err = record.error?.base {
        state = .init(.error(err))
      } else {
        state = .init(
          .error(
            NSError(
              domain: "Birdwatch", code: 2,
              userInfo: [NSLocalizedDescriptionKey: "Unknown query error"])))
      }
    }
  }
}

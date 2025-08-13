//
//  Query.swift
//  Birdwatch
//
//  Created by Forest Katsch on 8/12/25.
//

import Foundation
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

// MARK: - Internal coordinator

final class QueryCoordinator<Output>: ObservableObject {
  @Published var state: QueryState<Output> = .init(.idle)
  private var task: Task<Void, Never>? = nil
  private var currentKey: AnyHashable? = nil
  private var client: (any AnyQueryClient)? = nil

  func update(client: any AnyQueryClient, key: AnyHashable) {
    self.client = client
    guard currentKey != key else { return }
    task?.cancel()
    currentKey = key
    state = .init(.idle)
    let keyForTask = key
    task = Task { [weak self] in
      await client.retainAny(keyForTask)
      defer { Task { await client.releaseAny(keyForTask) } }
      if let existing = await client.readAny(keyForTask) {
        await MainActor.run { self?.state = Self.makeState(from: existing) }
      }
      await client.ensureQueryAny(keyForTask)
      for await record in client.updatesAny(for: keyForTask) {
        await MainActor.run { self?.state = Self.makeState(from: record) }
      }
    }
  }

  private static func makeState(from record: AnyQueryRecord) -> QueryState<Output> {
    switch record.status {
    case .idle:
      return .init(.idle)
    case .loading:
      return .init(.loading)
    case .success:
      if let boxed = record.data?.base as? Output {
        return .init(.success(boxed))
      } else {
        return .init(
          .error(
            NSError(
              domain: "Birdwatch", code: 1,
              userInfo: [NSLocalizedDescriptionKey: "Type mismatch for query data"])))
      }
    case .error:
      if let err = record.error?.base {
        return .init(.error(err))
      } else {
        return .init(
          .error(
            NSError(
              domain: "Birdwatch", code: 2,
              userInfo: [NSLocalizedDescriptionKey: "Unknown query error"])))
      }
    }
  }
}

// MARK: - @Query property wrapper

@propertyWrapper
public struct Query<Key: Hashable & Sendable, Output: Sendable> {
  private let key: Key
  @Environment(\.queryClient) private var client
  @StateObject private var coordinator: QueryCoordinator<Output>

  public init(_ key: Key) {
    self.key = key
    _coordinator = StateObject(wrappedValue: QueryCoordinator<Output>())
  }

}

@MainActor
extension Query: DynamicProperty {
  public var wrappedValue: QueryState<Output> { coordinator.state }
  public mutating func update() { coordinator.update(client: client, key: AnyHashable(key)) }
}

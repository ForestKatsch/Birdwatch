import Testing
import SwiftUI
@testable import Birdwatch

// Test the API as documented in README
enum MyQueryKey: Hashable, Sendable {
    case user(id: Int)
    case feed
    case articles(tag: String, page: Int)
}

struct User: Sendable, Codable {
    let id: Int
    let name: String
}

struct MyApi {
    static func fetchUser(id: Int) async throws -> User {
        User(id: id, name: "User \(id)")
    }
    
    static func fetchFeed() async throws -> [String] {
        ["Post 1", "Post 2"]
    }
    
    static func fetchArticles(tag: String, page: Int) async throws -> [String] {
        ["Article \(tag):\(page)"]
    }
}

@MainActor
@Test func apiSurfaceWorksAsDocumented() async throws {
    // Test QueryClient creation as shown in README
    let queryClient = QueryClient<MyQueryKey, AnySendable>(
        config: .init(staleTime: 60, cacheTime: 600),
        fetcher: { (key: MyQueryKey) in
            switch key {
            case .user(let id): return AnySendable(try await MyApi.fetchUser(id: id))
            case .feed: return AnySendable(try await MyApi.fetchFeed())
            case .articles(let tag, let p): return AnySendable(try await MyApi.fetchArticles(tag: tag, page: p))
            }
        }
    )
    
    // Test that we can create type-erased client for SwiftUI
    let anyClient = queryClient.eraseToAnyQueryClient()
    
    // Test basic query operations
    await queryClient.ensureQuery(MyQueryKey.user(id: 42))
    let record = await queryClient.read(MyQueryKey.user(id: 42))
    #expect(record != nil)
    #expect(record?.status == .success)
    
    if let user = record?.data?.base as? User {
        #expect(user.id == 42)
        #expect(user.name == "User 42")
    }
}

@Test func queryConfigurationWorks() async throws {
    let config = QueryConfig(
        staleTime: 30,
        cacheTime: 300,
        retry: .default,
        refetchOnFocus: true
    )
    
    #expect(config.staleTime == 30)
    #expect(config.cacheTime == 300)
    #expect(config.refetchOnFocus == true)
}

@Test func retryPolicyWorks() async throws {
    let defaultPolicy = RetryPolicy.default
    #expect(defaultPolicy.maxAttempts == 3)
    
    let neverPolicy = RetryPolicy.never
    #expect(neverPolicy.maxAttempts == 0)
    
    let customPolicy = RetryPolicy(maxAttempts: 5) { attempt in
        Double(attempt)
    }
    #expect(customPolicy.maxAttempts == 5)
    #expect(customPolicy.delaySeconds?(2) == 2.0)
}

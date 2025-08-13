
# Birdwatch

A reimagining of React Query for native Swift apps.

## Usage

```swift
@MainActor
import Birdwatch

// 1. Define your query keys
enum MyQueryKey: Hashable, Sendable {
    case user(id: Int)
    case feed
    case articles(tag: String, page: Int)
}

// 2. Create your query client
let queryClient = QueryClient(
  config: .init(staleTime: .seconds(60), cacheTime: .minutes(10))
) { key in
  switch key {
  case .user(let id):              return try await MyApi.fetchUser(id: id)
  case .feed:                      return try await MyApi.fetchFeed()
  case .articles(let tag, let p):  return try await MyApi.fetchArticles(tag: tag, page: p)
  }
}

// 3. Inject your client into the environment
@main struct AppMain: App {
  var body: some Scene {
    WindowGroup {
      RootView().environment(\.queryClient, queryClient)
    }
  }
}

// 4. Simple query using the @Query decorator
struct MyView: View {
  @Query(MyQueryKey.user(id: 42))
  var user: QueryState<User>

  var body: some View {
    switch user.phase {
      case .loading: ProgressView()
      case .error(let e): Text("Error: \(e.localizedDescription)")
      case .success(let data): Text(data.name)
      case .idle: EmptyView()
    }
  }
}

```

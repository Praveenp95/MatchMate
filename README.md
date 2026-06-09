# MatchMate — Technical Overview

---

## 1. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          PRESENTATION LAYER                         │
│                                                                     │
│   MatchListView                    MatchCardView                    │
│   ┌───────────────────┐            ┌──────────────────────────┐    │
│   │ • Profile List    │            │ • Avatar image           │    │
│   │ • Offline banner  │            │ • Name / city / company  │    │
│   │ • Pull-to-refresh │            │ • Accept / Decline btns  │    │
│   │ • Swipe actions   │            │ • Status banner          │    │
│   └────────┬──────────┘            └──────────────────────────┘    │
└────────────│────────────────────────────────────────────────────────┘
             │ @StateObject / @Published bindings
             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          VIEWMODEL LAYER                            │
│                                                                     │
│   MatchListViewModel  (@MainActor, ObservableObject)                │
│   ┌─────────────────────────────────────────────────────────┐      │
│   │  @Published profiles: [UserProfile]                      │      │
│   │  @Published isLoading / errorMessage / showErrorAlert    │      │
│   │                                                           │      │
│   │  loadInitialData()   ──▶  load cache, then fetch API     │      │
│   │  fetchFromAPI()      ──▶  merge statuses, save to DB     │      │
│   │  updateMatchStatus() ──▶  update memory + DB             │      │
│   └─────────────────────────────────────────────────────────┘      │
└─────────┬──────────────────┬────────────────────┬───────────────────┘
          │                  │                    │
          ▼                  ▼                    ▼
┌──────────────┐  ┌─────────────────┐  ┌──────────────────────┐
│  APIService  │  │ DatabaseService │  │   NetworkMonitor      │
│              │  │   (actor)       │  │  (NWPathMonitor)      │
│  URLSession  │  │                 │  │                       │
│  async/await │  │  SQLite3 (WAL)  │  │  @Published           │
│              │  │  openIfNeeded() │  │  isConnected: Bool    │
│  fetchUsers()│  │  saveUsers()    │  │  connectionType       │
│              │  │  loadUsers()    │  │                       │
│  ─────────── │  │  updateStatus() │  │  Combine sink →       │
│  JSON →      │  │                 │  │  re-fetch on          │
│  [UserProfile│  │  ─────────────  │  │  reconnect            │
│  ]           │  │  NSCache(L1) +  │  └──────────────────────┘
└──────────────┘  │  Disk (L2)      │
                  │  ImageCache     │
                  └─────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │  SQLite File    │
                  │  MatchMate.db   │
                  │  (Documents/)   │
                  └─────────────────┘
```

### Layer responsibilities

| Layer | Responsibility | Runs on |
|---|---|---|
| **View** | Render UI, forward user gestures | `@MainActor` (main thread) |
| **ViewModel** | Business logic, state ownership | `@MainActor` |
| **APIService** | Network fetch, JSON decode | Cooperative thread pool |
| **DatabaseService** | SQLite read/write | Actor's serial executor (background) |
| **NetworkMonitor** | Observe connectivity | Background dispatch queue → publishes on main |
| **ImageCache** | NSCache + disk I/O | Cooperative thread pool |

---

## 2. Features

### Profile Card Display
Each card renders a user profile fetched from `https://jsonplaceholder.typicode.com/users` with:
- **Avatar** — loaded from `pravatar.cc` using a two-tier cache (NSCache + disk)
- **Name, city, company, email** — mapped from the API response
- **Action area** — shows Accept/Decline buttons when status is `.none`, or a coloured status banner once decided

### Accept / Decline (Two interaction paths)

**Path A — Button tap on card**
```
User taps ✓ or ✗
    → onAccept / onDecline closure
    → MatchListViewModel.updateMatchStatus()
    → profiles[idx].matchStatus updated in-memory (UI updates instantly)
    → Task { await DatabaseService.updateMatchStatus() }  (persisted async)
```

**Path B — Row swipe action**
```
User swipes left  → Accept action fires
User swipes right → Decline action fires
    → withAnimation { viewModel.updateMatchStatus() }
    → same persistence path as above
```

### Offline Mode
- On launch, `DatabaseService.loadUsers()` is called **before** the API call — cached profiles appear instantly
- `NetworkMonitor` publishes `isConnected`; an orange offline banner animates in when disconnected
- Accept/Decline decisions work offline — `updateMatchStatus()` writes to local SQLite immediately
- On reconnect, `setupNetworkObserver()` Combine sink auto-triggers `fetchFromAPI()` to sync fresh data

### Image Caching (Two-tier)
```
Request image URL
    │
    ├─ NSCache hit  ──▶  return UIImage (zero I/O, < 1ms)
    │
    ├─ Disk hit     ──▶  load from ~/Caches/ImageCache/
    │                    promote to NSCache
    │                    return UIImage (no network)
    │
    └─ Cache miss   ──▶  URLSession.data(from:)
                         store in NSCache + write JPEG to disk
                         return UIImage
```
Images survive app restarts (disk L2) and work offline once downloaded.

### Pull to Refresh
`.refreshable { await viewModel.fetchFromAPI() }` on the `List` — the system spinner appears during the async fetch and disappears on completion.

### Swipe Actions
`.swipeActions` attached to each `List` row:

| Gesture | Edge | Action |
|---|---|---|
| Swipe left | `.trailing` | ✓ Accept (teal) |
| Swipe right | `.leading` | ✗ Decline (grey) |

`allowsFullSwipe: true` means a full-length swipe fires the action immediately without requiring a tap on the revealed button.

---

## 3. Async/Await & Background Thread Handling

### Threading model

```
Main Thread (@MainActor)
│
│  MatchListViewModel — owns all @Published state
│  UI reads state here; state mutations here trigger SwiftUI redraws
│
│  await ──────────────────────────────────────────▶ Cooperative Thread Pool
│                                                     │
│                                                     │  APIService.fetchUsers()
│                                                     │  URLSession.data(from:)
│                                                     │  JSONDecoder.decode()
│                                                     │
│  ◀────────────────────────── resumes on @MainActor─┘
│
│  await ──────────────────────────────────────────▶ DatabaseService actor executor
│                                                     │  (serial background thread)
│                                                     │  sqlite3_prepare / step / finalize
│                                                     │
│  ◀────────────────────────── resumes on @MainActor─┘
```

### Key patterns used

**`@MainActor` ViewModel**
```swift
@MainActor
final class MatchListViewModel: ObservableObject {
    @Published var profiles: [UserProfile] = []
    // All @Published mutations happen on main thread automatically
}
```
No manual `DispatchQueue.main.async {}` calls needed — the compiler enforces main-thread execution.

---

**`actor` for SQLite isolation**
```swift
actor DatabaseService {
    private var db: OpaquePointer?

    // openIfNeeded() is called inside every public method.
    // Because all methods are actor-isolated, the DB connection is
    // always opened AND used on the same serial executor thread.
    // This eliminates SQLITE_BUSY (code 5) cross-thread conflicts.
    private func openIfNeeded() { ... }

    func saveUsers(_ users: [UserProfile]) {
        openIfNeeded()
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        // ... batch insert
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }
}
```
Why `actor` instead of `DispatchQueue.sync`?
- No risk of deadlock
- Compiler-checked isolation — calling from the wrong context is a compile error
- Cooperative with Swift's thread pool (no blocked threads)

---

**`async/await` API call**
```swift
func fetchFromAPI() async {
    guard !isLoading else { return }      // re-entrancy guard
    isLoading = true

    do {
        // Suspension point 1: network I/O (frees main thread)
        let apiUsers = try await apiService.fetchUsers()

        // Suspension point 2: actor hop to DatabaseService executor
        let stored = await dbService.loadUsers()

        // Back on @MainActor — synchronous, no suspension
        let merged = buildMerged(apiUsers, stored)
        profiles = merged                // UI updates here

        // Suspension point 3: actor hop for batch write
        await dbService.saveUsers(merged)

    } catch { ... }

    isLoading = false
}
```
Between each `await`, the main thread is **completely free** for UI gestures and animations — there is zero blocking.

---

**Combine network observer**
```swift
networkMonitor.$isConnected
    .removeDuplicates()
    .dropFirst()                      // ignore the initial emission at startup
    .sink { [weak self] isConnected in
        guard let self, isConnected else { return }
        Task { await self.fetchFromAPI() }   // re-fetch when reconnected
    }
    .store(in: &cancellables)
```

---

**Task cancellation in ImageLoader**
```swift
@MainActor
final class ImageLoader: ObservableObject {
    private var task: Task<Void, Never>?

    func load() {
        task = Task {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }  // check before writing state
            image = UIImage(data: data)
        }
    }

    deinit { task?.cancel() }   // cancel in-flight download when view disappears
}
```
Prevents stale image assignments after the view is recycled by `List`.

---

**SQLite WAL mode**
```swift
sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
```
Write-Ahead Logging ensures readers never block writers. Combined with actor isolation, this means `loadUsers()` (SELECT) and `saveUsers()` (INSERT) can be queued back-to-back without deadlocking.

---

## 4. AI (GitHub Copilot) Usage

### What was AI-generated

| Component | AI contribution |
|---|---|
| Full MVVM skeleton | Generated `MatchListViewModel`, all `@Published` properties, `init`, task structure |
| `DatabaseService` actor | Generated complete SQLite3 CRUD with actor isolation |
| `NetworkMonitor` | Generated `NWPathMonitor` setup and Combine publisher |
| `APIService` | Generated `async/await` URLSession fetch + JSON decode |
| `ImageCache` two-tier design | AI designed and implemented NSCache + FileManager layering |
| `CachedAsyncImage` SwiftUI view | Generated loader + placeholder + image states |
| README & documentation | Generated architecture diagrams, tables, code explanations |

### What AI diagnosed and fixed

| Symptom reported | Root cause found by AI | Fix applied |
|---|---|---|
| `SQLITE_BUSY (5)` on every write | Actor `init()` runs on **caller's thread**, not actor's executor — DB opened on main thread, used on background | Moved DB open to lazy `openIfNeeded()` called inside actor-isolated methods |
| Duplicate bind+step in saveUsers | `replace_string_in_file` tool doubled the loop body | Removed duplicate block |
| Swipe left causes list glitch | (1) `Button(role: .destructive)` triggers SwiftUI's built-in row-deletion animation on top of status change; (2) list-level `.animation(…, value:)` fires on all rows mid-gesture | Removed `role: .destructive`; removed list-level animation |
| Accept/Decline buttons miss taps | `Circle().strokeBorder(...)` only the stroke ring is hit-testable; transparent interior ignored by SwiftUI | Added `.contentShape(Circle())` to make full circle tappable |
| First Accept/Decline not persisting | `fetchFromAPI` loaded stale DB snapshot while the DB `updateMatchStatus` Task was still queued — then `profiles = merged` overwrote the in-memory tap | In merge step, prefer live in-memory `profiles` status over DB snapshot |

### AI development workflow

```
1. Human defines requirement
        │
        ▼
2. AI generates implementation
        │
        ▼
3. Human builds & tests in Xcode
        │
        ├── Works ──▶ next feature
        │
        └── Bug ──▶ Human describes symptom (e.g., "database is locked")
                        │
                        ▼
                   AI analyses call stack, threading model,
                   Swift concurrency semantics
                        │
                        ▼
                   AI explains root cause + applies targeted fix
                        │
                        ▼
                   Back to step 3
```

### Value delivered by AI

- **Speed** — Full project scaffold (models, services, viewmodel, views) generated in minutes vs hours
- **Deep diagnosis** — Non-obvious bugs like SQLite actor-threading conflicts and SwiftUI gesture animation conflicts were diagnosed from a one-line symptom description
- **No documentation lookup** — Swift concurrency edge cases (`actor init` threading, `Task.isCancelled`, `@MainActor` inference) applied correctly without manual research
- **Iterative safety** — Each fix was scoped and explained, so the human understood every change rather than accepting a black-box patch

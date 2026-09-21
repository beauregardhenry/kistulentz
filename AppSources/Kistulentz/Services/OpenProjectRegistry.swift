import Foundation

/// Tracks every currently open `WritingProjectStore` so app termination can flush pending
/// chapter, Bible, and outline saves directly, as a backstop alongside each window's own
/// `EditorWorkspace.onDisappear` -> `saveNow()` teardown path. Each entry holds only a plain
/// Swift `weak var` (deliberately not `NSHashTable.weakObjects()` -- confirmed by hand that an
/// `NSHashTable` entry measurably delays a store's deallocation, enough to break an unrelated
/// existing test asserting a *different* store deallocates synchronously once its own last
/// strong reference is dropped). A store's real lifetime is owned by its window's
/// `@StateObject`, never by this registry, so a closed window's store still deallocates
/// normally and its entry is pruned the next time `flushAll()` runs.
@MainActor
final class OpenProjectRegistry {
    static let shared = OpenProjectRegistry()

    private struct Entry {
        weak var store: WritingProjectStore?
    }

    private var entries: [UUID: Entry] = [:]

    func register(_ store: WritingProjectStore) {
        entries[UUID()] = Entry(store: store)
    }

    /// Saves every still-live registered store's current chapter, Bible, and outline -- the
    /// same trio `openProject`/`closeProject` already flush together -- regardless of whether
    /// that store's own window has torn down yet. Each call is guarded/idempotent on the store
    /// side, so calling this ahead of (or in addition to) a window's own teardown is safe.
    func flushAll() {
        for (id, entry) in entries {
            guard let store = entry.store else {
                entries[id] = nil
                continue
            }
            store.saveNow()
            store.saveBibleNow()
            store.saveOutlineNow()
        }
    }
}

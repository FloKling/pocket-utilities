import Testing
import Foundation

@testable import UtilityCore

final class ClipboardPolicyTests {
    @Test func testSensitiveMarkersAndExclusionsAreRejected() {
        for marker in ClipboardPrivacyFilter.sensitiveTypes {
            expectFalse(ClipboardPrivacyFilter.allows(types: ["public.utf8-plain-text", marker], source: nil, exclusions: []))
        }
        for bundle in ClipboardPrivacyFilter.defaultExclusions {
            expectFalse(ClipboardPrivacyFilter.allows(types: [], source: bundle, exclusions: Set(ClipboardPrivacyFilter.defaultExclusions)))
        }
        expectFalse(ClipboardPrivacyFilter.allows(types: [], source: "my.bank", exclusions: ["my.bank"]))
        expectTrue(ClipboardPrivacyFilter.allows(types: ["public.png"], source: "com.apple.Preview", exclusions: []))
    }
    @Test func testUnknownSourceIsExplicitlyBestEffort() {
        expectTrue(ClipboardPrivacyFilter.allows(types: ["public.utf8-plain-text"], source: nil, exclusions: ["my.bank"]))
    }
    @Test func testPruningPinsAgeSizeAndOrdering() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func item(_ name: String, age: TimeInterval = 0, pin: Bool = false, size: Int = 10) -> ClipboardItem {
            ClipboardItem(date: now.addingTimeInterval(-age), pinned: pin, preview: name, kind: "Text", digest: name, byteCount: size)
        }
        let input = [item("new"), item("old", age: 100), item("pin", age: 500, pin: true), item("expiredPin", age: 86401, pin: true), item("oversized", pin: true, size: 101)]
        let kept = HistoryPolicy.retained(input, limit: 2, maxAgeDays: 1, maxBytes: 100, now: now)
        expectEqual(kept.map(\.preview), ["pin", "new"])
        expectTrue(HistoryPolicy.retained([], limit: 100, maxAgeDays: 7, maxBytes: 100, now: now).isEmpty)
    }
    @Test func testShortcutConflictIgnoresDisplayLabel() {
        expectTrue(Shortcut(keyCode: 1, modifiers: 8, label: "S").matches(Shortcut(keyCode: 1, modifiers: 8, label: "s")))
        expectFalse(Shortcut(keyCode: 1, modifiers: 8, label: "S").matches(Shortcut(keyCode: 1, modifiers: 9, label: "S")))
    }
    @Test func testAggregateBudgetAlsoAppliesToPins() {
        let items = (0..<4).map { index in
            ClipboardItem(date: Date().addingTimeInterval(-Double(index)), pinned: true, preview: "Item", kind: "Image", digest: String(index), byteCount: 20)
        }
        let kept = HistoryPolicy.retained(items, limit: 100, maxAgeDays: 7, maxBytes: 100, totalByteBudget: 45)
        expectEqual(kept.count, 2)
        expectEqual(kept.map(\.digest), ["0", "1"])
    }
}

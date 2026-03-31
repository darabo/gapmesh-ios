# Adopt Apple HIG Split View Sidebar for iPad

The user requested that the "People" sidebar be updated to fully comply with Apple's Human Interface Guidelines for sidebars, noting that we should "not be afraid to change the entire thing to make it possible."

According to the linked [Apple HIG on Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), a true sidebar belongs on the **leading edge** (left side) and acts as the primary navigational anchor for the app. The current implementation uses a custom sliding drawer on the trailing edge (which functions more like an Inspector) and relies on modal sheets for private chats.

To make the app truly native and compliant with these guidelines, we will undertake a major architectural upgrade for the iPad version using SwiftUI's native `NavigationSplitView`.

## User Review Required

> [!IMPORTANT]
> **Major Layout Change for iPad:**
> This plan will fundamentally change how Gap Mesh looks and feels on the iPad. Instead of a floating top tab bar and a custom right-side drawer, the iPad will adopt a professional, fully native split-view layout (similar to Apple Messages or Discord). 
> 
> The iPhone layout will remain exactly the same (bottom Tab bar). Please approve to proceed!

## Proposed Changes

---

### `bitchat/Views/Tabs/MainTabView.swift`

We will fork the layout logic based on the device idiom:
- **iPhone**: Retains the standard `TabView` structure.
- **iPad**: Adopts a pure `NavigationSplitView`.

#### [MODIFY] `MainTabView.swift`
- Check `UIDevice.current.userInterfaceIdiom`.
- If iPad, construct a `NavigationSplitView`.
- **Sidebar Column**: 
  - A `List` acting as the main navigational hierarchy.
  - Section 1: "App" - Contains `Public Chat`, `Map / Locations`, and `Settings`.
  - Section 2: "Active Peers" - Contains the list of online users (migrated from `PeopleTabView`).
- **Detail Column**:
  - Dynamically updates based on the sidebar selection.
  - Selecting an active peer will display their private chat natively in this detail pane, eliminating the need for `PrivateChatSheetView` modals on iPad.

---

### `bitchat/Views/Tabs/ChatTabView.swift`

We will completely remove the custom sliding drawer logic that we just built, as the system will now handle the sidebar natively.

#### [MODIFY] `ChatTabView.swift`
- Delete `peopleSidebarOverlay`, the outer `ZStack`, and the strict `GeometryReader` sandbox.
- Remove the "People" toggle button from the header, as the sidebar is now controlled by the system's leading edge navigation split view.
- The view will return to being a simple, clean, 100%-width Chat interface that lives happily inside the `NavigationSplitView` detail column.

---

### `bitchat/Views/Tabs/PeopleTabView.swift`

The standalone `PeopleTabView` will be integrated directly into the new `NavigationSplitView` sidebar architecture on iPad, while remaining a standalone tab on iPhone.

#### [MODIFY] `PeopleTabView.swift`
- Refactor the row components (`meshPeerRow`, `geohashPersonRow`) so they can be reused effectively inside the new `NavigationSplitView` list.

---

## Open Questions

> [!WARNING]
> **Private Chat Display**
> Currently, tapping a user in the People list opens a `PrivateChatSheetView` modal. In the new Split View model, tapping a user in the leading sidebar will display the private chat natively in the main large window (the detail view). Let me know if you would prefer to keep private chats as modal popups on iPad, or if native inline detail viewing is perfect.

## Verification Plan

### Automated Tests
- N/A

### Manual Verification
1. Compile and run the app on an iPad simulator.
2. Verify the new leading-edge sidebar contains App sections (Chat, Map, Settings) and the list of Active Peers.
3. Verify that selecting an item in the sidebar immediately and securely updates the large detail view.
4. Verify the iPhone interface remains unharmed as a standard bottom tab bar.

import SwiftUI

/// Reload action published by the focused document window so the global
/// Cmd+R menu command can target whichever window is frontmost.
struct ReloadActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var reloadAction: ReloadActionKey.Value? {
        get { self[ReloadActionKey.self] }
        set { self[ReloadActionKey.self] = newValue }
    }
}

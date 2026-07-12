// SPDX-License-Identifier: Apache-2.0
import Foundation
import Observation

/// Top-level navigation sections (SPEC §5.7). Sessions and History join in
/// their own milestones; unimplemented sections are not shown.
enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case activeResources
    case storage
    case settings

    var id: String { rawValue }
}

/// Tabs inside Active Resources (SPEC §5.7).
enum ActiveResourceTab: String, CaseIterable, Identifiable {
    case ports
    case processes
    case containers
    case services

    var id: String { rawValue }
}

/// Tabs inside Storage.
enum StorageTab: String, CaseIterable, Identifiable {
    case projects
    case toolCaches
    case docker

    var id: String { rawValue }
}

/// Shell-level navigation and search state, shared between the scene commands
/// (⌘1-3, ⌘K) and the split view.
@MainActor
@Observable
final class ShellModel {
    var section: SidebarSection? = .overview
    var activeResourceTab: ActiveResourceTab = .processes
    var storageTab: StorageTab = .projects
    /// Current-page filter text (SPEC §5.7 — global search arrives with M11).
    var searchText = ""
    /// Incremented by the ⌘K command; the shell view reacts by focusing search.
    var searchFocusRequest = 0

    func open(_ section: SidebarSection) {
        self.section = section
    }

    /// Navigation helper for dashboard "review" jumps.
    func openStorage(tab: StorageTab) {
        storageTab = tab
        section = .storage
    }

    func openActiveResources(tab: ActiveResourceTab) {
        activeResourceTab = tab
        section = .activeResources
    }
}

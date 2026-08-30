//
//  LayoutItemInfo.swift
//  Ice
//

import Cocoa

struct LayoutItemInfo: Identifiable, Hashable {
    let id = UUID()
    let windowID: CGWindowID
    let image: NSImage
    let ownerPID: pid_t
    let ownerName: String
    let frame: CGRect
    let title: String

    var isMovable: Bool { true }

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
    }

    static func == (lhs: LayoutItemInfo, rhs: LayoutItemInfo) -> Bool {
        lhs.windowID == rhs.windowID
    }
}

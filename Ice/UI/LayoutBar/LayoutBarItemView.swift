//
//  LayoutBarItemView.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
final class LayoutBarItemView: NSView {
    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    /// The item that the view represents.
    let item: MenuBarItem

    /// Temporary information that the item view retains when it is moved outside
    /// of a layout view.
    ///
    /// When the item view is dragged outside of a layout view, this property is set
    /// to hold the layout view's container view, as well as the index of the item
    /// view in relation to the container's other items. Upon being inserted into a
    /// new layout view, these values are removed. If the item is dropped outside of
    /// a layout view, these values are used to reinsert the item view in its original
    /// layout view.
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    /// A Boolean value that indicates whether the item view is currently inside a container.
    var hasContainer = false

    /// Fallback icon to display if captured window image is unavailable or transparent.
    private var fallbackImage: NSImage? {
        if let app = item.owningApplication, let icon = app.icon {
            return icon
        }
        if item.info.namespace == .controlCenter {
            let title = item.title?.lowercased() ?? ""
            if title.contains("wifi") || title.contains("wi-fi") {
                return NSImage(systemSymbolName: "wifi", accessibilityDescription: item.displayName)
            } else if title.contains("battery") {
                return NSImage(systemSymbolName: "battery.100", accessibilityDescription: item.displayName)
            } else if title.contains("clock") || title.contains("time") {
                return NSImage(systemSymbolName: "clock", accessibilityDescription: item.displayName)
            } else if title.contains("sound") || title.contains("volume") {
                return NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: item.displayName)
            } else {
                return NSImage(systemSymbolName: "switch.2", accessibilityDescription: item.displayName)
            }
        }
        return NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: item.displayName)
    }

    /// The image displayed inside the view.
    private var image: NSImage? {
        didSet {
            if
                let image,
                let screen = appState?.imageCache.screen
            {
                let width = max(image.size.width / screen.backingScaleFactor, 24)
                let height: CGFloat = 28
                setFrameSize(CGSize(width: width, height: height))
            } else {
                let initialWidth = max(item.frame.width > 0 ? item.frame.width : 28, 24)
                setFrameSize(CGSize(width: initialWidth, height: 28))
            }
            needsDisplay = true
        }
    }

    /// A Boolean value that indicates whether the item view is a dragging placeholder.
    ///
    /// If this value is `true`, the item view does not draw its image.
    var isDraggingPlaceholder = false {
        didSet {
            needsDisplay = true
        }
    }

    /// A Boolean value that indicates whether the view is enabled.
    var isEnabled = true {
        didSet {
            needsDisplay = true
        }
    }

    /// Creates a view that displays the given menu bar item.
    init(appState: AppState, item: MenuBarItem) {
        self.item = item
        self.appState = appState

        let initialWidth = max(item.frame.width > 0 ? item.frame.width : 28, 24)
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: initialWidth, height: 28)))
        unregisterDraggedTypes()

        self.toolTip = item.displayName
        self.isEnabled = item.isMovable

        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            appState.imageCache.$images
                .sink { [weak self] images in
                    guard
                        let self,
                        let cgImage = images[item.info]
                    else {
                        return
                    }
                    image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Provides an alert to display when the item view is disabled.
    func provideAlertForDisabledItem() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Menu bar item is not movable."
        alert.informativeText = "macOS prohibits \"\(item.displayName)\" from being moved."
        return alert
    }

    /// Provides an alert to display when a menu bar item is unresponsive.
    func provideAlertForUnresponsiveItem() -> NSAlert {
        let alert = provideAlertForDisabledItem()
        alert.informativeText = "\(item.displayName) is unresponsive. Until it is restarted, it cannot be moved. Movement of other menu bar items may also be affected until this is resolved."
        return alert
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isDraggingPlaceholder {
            let iconBounds = bounds.insetBy(dx: 2, dy: 4)
            if let fallbackImage {
                fallbackImage.draw(
                    in: iconBounds,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: isEnabled ? 0.9 : 0.5
                )
            }
            image?.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: isEnabled ? 1.0 : 0.67
            )
            if Bridging.responsivity(for: item.ownerPID) == .unresponsive {
                let warningImage = NSImage.warning
                let width: CGFloat = 15
                let scale = width / warningImage.size.width
                let size = CGSize(
                    width: width,
                    height: warningImage.size.height * scale
                )
                warningImage.draw(
                    in: CGRect(
                        x: bounds.maxX - size.width,
                        y: bounds.minY,
                        width: size.width,
                        height: size.height
                    )
                )
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        guard isEnabled else {
            let alert = provideAlertForDisabledItem()
            alert.runModal()
            return
        }

        guard Bridging.responsivity(for: item.ownerPID) != .unresponsive else {
            let alert = provideAlertForUnresponsiveItem()
            alert.runModal()
            return
        }

        let pasteboardItem = NSPasteboardItem()
        // contents of the pasteboard item don't matter here, as all needed information
        // is available directly from the dragging session; what matters is that the type
        // is set to `layoutBarItem`, as that is what the layout bar registers for
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: image)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

// MARK: LayoutBarItemView: NSDraggingSource
extension LayoutBarItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // make sure the container doesn't update its arranged views and that items
        // aren't arranged during a dragging session
        if let container = superview as? LayoutBarContainer {
            container.canSetArrangedViews = false
        }

        // prevent the dragging image from animating back to its original location
        session.animatesToStartingPositionsOnCancelOrFail = false

        // async to prevent the view from disappearing before the dragging image appears
        DispatchQueue.main.async {
            self.isDraggingPlaceholder = true
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer {
            // always remove container info at the end of a session
            oldContainerInfo = nil
        }

        // since the session's `animatesToStartingPositionsOnCancelOrFail` property was
        // set to false when the session began (above), there is no delay between the user
        // releasing the dragging item and this method being called; thus, `isDraggingPlaceholder`
        // only needs to be updated here; if we ever decide we want animation, it may also
        // need to be updated inside `performDragOperation(_:)` on `LayoutBarPaddingView`
        isDraggingPlaceholder = false

        // if the drop occurs outside of a container, reinsert the view into its original
        // container at its original index
        if !hasContainer {
            guard let (container, index) = oldContainerInfo else {
                return
            }
            container.shouldAnimateNextLayoutPass = false
            container.arrangedViews.insert(self, at: index)
        }
    }
}

extension LayoutBarItemView: NSAccessibilityLayoutItem { }

// MARK: Layout Bar Item Pasteboard Type
extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Constants.bundleIdentifier).layout-bar-item")
}

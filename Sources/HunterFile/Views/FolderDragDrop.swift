import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HunterFileCore

struct FolderDropFeedbackReset: NSViewRepresentable {
    var reset: () -> Void
    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) { view.reset = reset }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.stopMonitoring() }

    final class CaptureView: NSView {
        var reset: () -> Void = {}
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown]) { [weak self] event in
                if let self, event.window === self.window { self.reset() }
                return event
            }
        }
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
    }
}

struct FolderDragItem: Codable {
    static let type = UTType(exportedAs: "com.kevin.openeagle.folder-move", conformingTo: .data)
    var id: String
    var libraryPath: String

    var pasteboardItem: NSPasteboardItem {
        let item = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(self) { item.setData(data, forType: .init(Self.type.identifier)) }
        return item
    }
    @MainActor static func current(in store: AppStore) -> Self? {
        guard let data = NSPasteboard(name: .drag).data(forType: .init(type.identifier)),
              let item = try? JSONDecoder().decode(Self.self, from: data),
              item.libraryPath == store.repository?.root.path,
              store.folders.contains(where: { $0.id == item.id }) else { return nil }
        return item
    }
    @MainActor static func insert(at index: Int, into parentID: String?, in store: AppStore) {
        guard let item = current(in: store) else { return }
        let siblings = store.folders.filter { $0.parentID == parentID }
        let next = siblings.dropFirst(index).first(where: { $0.id != item.id })
        store.moveFolder(item.id, toParent: parentID, before: next?.id)
    }
}

// SwiftUI's List drag source can retain a selected-row snapshot after reparenting.
// Let AppKit own only the drag session; the List still owns selection and the tree.
struct FolderDragSource: NSViewRepresentable {
    var folder: LibraryFolder
    var libraryPath: String
    var select: () -> Void

    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.item = FolderDragItem(id: folder.id, libraryPath: libraryPath)
        view.select = select
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        let title = folder.name as NSString
        let size = NSSize(width: min(260, title.size(withAttributes: attributes).width + 42), height: 32)
        let icon = NSImage(systemSymbolName: folder.icon ?? "folder", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [NSColor(Color(hex: folder.color))]))
        view.preview = NSImage(size: size, flipped: false) { rect in
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            icon?.draw(in: NSRect(x: 8, y: 8, width: 16, height: 16))
            title.draw(in: NSRect(x: 32, y: 7, width: size.width - 40, height: 18), withAttributes: attributes)
            return true
        }
    }

    final class CaptureView: NSView, NSDraggingSource {
        var item: FolderDragItem?
        var preview = NSImage()
        var select: () -> Void = {}
        private var start: NSPoint?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) else { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            start = event.locationInWindow
            var ancestor = superview
            while let view = ancestor {
                if let table = view as? NSTableView { window?.makeFirstResponder(table); break }
                ancestor = view.superview
            }
            select()
        }
        override func mouseUp(with event: NSEvent) { start = nil }
        override func mouseDragged(with event: NSEvent) {
            guard let start, let item,
                  hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 else { return }
            self.start = nil
            let drag = NSDraggingItem(pasteboardWriter: item.pasteboardItem)
            let point = convert(event.locationInWindow, from: nil)
            drag.setDraggingFrame(NSRect(x: point.x - 12, y: point.y - 16, width: preview.size.width, height: preview.size.height), contents: preview)
            beginDraggingSession(with: [drag], event: event, source: self)
        }
        // List.onInsert proposes copy; both destinations perform the same folder move.
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .move] }
    }
}

struct FolderDropDelegate: DropDelegate {
    static let types = [FolderDragItem.type, UTType.utf8PlainText, .url]
    var store: AppStore
    var folder: LibraryFolder
    @Binding var targeted: Bool
    @Binding var expanded: Bool

    func validateDrop(info: DropInfo) -> Bool {
        if !info.hasItemsConforming(to: [FolderDragItem.type]) { return info.hasItemsConforming(to: [.utf8PlainText, .url]) }
        guard let item = FolderDragItem.current(in: store) else { return false }
        return canAccept(item.id)
    }
    func dropEntered(info: DropInfo) { targeted = validateDrop(info: info) }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let moving = info.hasItemsConforming(to: [FolderDragItem.type]) ||
            (!store.destinationFolderIDs.isEmpty && info.hasItemsConforming(to: [.utf8PlainText]))
        return DropProposal(operation: validateDrop(info: info) ? (moving ? .move : .copy) : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        defer { targeted = false }
        if info.hasItemsConforming(to: [FolderDragItem.type]) {
            guard let item = FolderDragItem.current(in: store), canAccept(item.id) else { return false }
            expanded = true
            store.moveFolder(item.id, toParent: folder.id)
        } else {
            let providers = info.itemProviders(for: [.utf8PlainText, .url])
            guard !providers.isEmpty, let repository = store.repository else { return false }
            let sourceFolderID = store.destinationFolderIDs.first, includeSubfolders = store.includeSubfolders
            Task {
                let assets = await Self.assets(from: providers)
                guard store.repository === repository else { return }
                if !assets.ids.isEmpty {
                    if let sourceFolderID { await store.moveAssets(ids: assets.ids, fromFolder: sourceFolderID, toFolder: folder.id, includeSubfolders: includeSubfolders) }
                    else { store.addToFolder(folder.id, ids: assets.ids) }
                }
                if !assets.urls.isEmpty { store.importURLs(assets.urls, into: [folder.id]) }
                if assets.ids.isEmpty && assets.urls.isEmpty { store.error = "无法读取拖入的素材，请重试。" }
            }
        }
        return true
    }
    static func assets(from providers: [NSItemProvider]) async -> (ids: Set<String>, urls: [URL]) {
        func data(from provider: NSItemProvider, type: UTType) async -> Data? {
            await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in continuation.resume(returning: data) }
            }
        }
        var ids = Set<String>(), urls: [URL] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier),
               let data = await data(from: provider, type: .utf8PlainText),
               let text = String(data: data, encoding: .utf8) {
                let values = text.components(separatedBy: ",").filter { UUID(uuidString: $0) != nil }
                if !values.isEmpty { ids.formUnion(values); continue }
            }
            let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL : .url
            if let data = await data(from: provider, type: type),
               let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
        }
        return (ids, urls)
    }
    func canAccept(_ id: String) -> Bool {
        var ancestor: String? = folder.id, visited = Set<String>()
        while let current = ancestor {
            guard current != id, visited.insert(current).inserted else { return false }
            ancestor = store.folders.first(where: { $0.id == current })?.parentID
        }
        return true
    }
}

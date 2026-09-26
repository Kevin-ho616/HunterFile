import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
import SwiftUI
import AVKit
import Quartz
import OpenEagleCore
@testable import OpenEagle

struct MediaTests {
    @MainActor @Test func newSiblingFolderUsesTargetsParentInsteadOfTarget() throws {
        let store = AppStore(openInitialLibrary: false)
        let root = LibraryFolder(name: "Root")
        let child = LibraryFolder(name: "Child", parentID: root.id)
        let grandchild = LibraryFolder(name: "Grandchild", parentID: child.id)
        store.folders = [root, child, grandchild]
        func draft() throws -> LibraryFolder {
            guard case .folder(let folder) = store.sheet else { throw CocoaError(.coderValueNotFound) }
            #expect(folder.name.isEmpty && !store.folders.contains { $0.id == folder.id })
            return folder
        }
        for target in store.folders {
            // Right-click creation must use its target even if another folder is selected.
            store.scope = .folder(grandchild.id)
            store.newSiblingFolder(of: target)
            #expect(try draft().parentID == target.parentID)
            // The menu and keyboard shortcut use the current folder.
            store.scope = .folder(target.id)
            store.newSiblingFolder()
            #expect(try draft().parentID == target.parentID)
        }
        store.scope = .all
        store.newSiblingFolder()
        #expect(try draft().parentID == nil)
    }
    @MainActor @Test func sidebarSelectionClearsPreviousFolderFeedback() async throws {
        _ = NSApplication.shared
        let store = AppStore(openInitialLibrary: false)
        let parent = LibraryFolder(name: "Parent"), other = LibraryFolder(name: "Other")
        let child = LibraryFolder(name: "Child", parentID: parent.id)
        store.folders = [parent, child, other]
        let host = NSHostingView(rootView: ContentView(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { store.refreshTask?.cancel(); window.close() }
        window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        var views: [NSView] = [host], outline: NSOutlineView?
        while let view = views.popLast() {
            if let table = view as? NSOutlineView { outline = table; break }
            views.append(contentsOf: view.subviews)
        }
        let table = try #require(outline)
        let allRow = table.selectedRow
        #expect(allRow >= 0)
        func click(_ point: NSPoint) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                NSApp.sendEvent(event)
            }
        }
        for folder in [parent, child, other] {
            store.navigate(.folder(folder.id))
            try await Task.sleep(for: .milliseconds(50))
            let folderRow = table.selectedRow
            #expect(folderRow >= 0 && folderRow != allRow)
            store.folderDropTargetID = parent.id
            store.navigate(.all)
            try await Task.sleep(for: .milliseconds(50))
            #expect(store.scope == .all && store.folderDropTargetID == nil)
            #expect(table.selectedRowIndexes == IndexSet(integer: allRow))
            #expect(table.rowView(atRow: folderRow, makeIfNecessary: true)?.isSelected == false)
        }
        store.folderDropTargetID = other.id
        try click(NSPoint(x: 500, y: 450))
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.folderDropTargetID == nil)
        store.folderDropTargetID = parent.id
        store.select(Asset(name: "Selected asset", ext: "png"))
        #expect(store.folderDropTargetID == nil)
    }
    @MainActor @Test func nativeFolderDragPreservesClickAndTransferIdentity() throws {
        _ = NSApplication.shared
        let item = FolderDragItem(id: UUID().uuidString, libraryPath: "/Pictures/测试 资源库.openeagle")
        let data = try #require(item.pasteboardItem.data(forType: .init(FolderDragItem.type.identifier)))
        let decoded = try JSONDecoder().decode(FolderDragItem.self, from: data)
        #expect(decoded.id == item.id && decoded.libraryPath == item.libraryPath)
        let view = FolderDragSource.CaptureView()
        view.item = item
        var clicks = 0
        view.select = { clicks += 1 }
        func event(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, .zero))
        view.mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 1, y: 1)))
        view.mouseUp(with: try event(.leftMouseUp, NSPoint(x: 1, y: 1)))
        view.mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 100, y: 100)))
        #expect(clicks == 1)
    }
    @MainActor @Test func folderDropsPreferAssetIDsAndKeepExternalFiles() async {
        let first = UUID().uuidString, second = UUID().uuidString
        let internalURL = URL(fileURLWithPath: "/Library/original.png")
        let provider = NSItemProvider(object: internalURL as NSURL)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(Data("\(first),\(second)".utf8), nil); return nil
        }
        let externalURL = URL(fileURLWithPath: "/Pictures/New image.png")
        let result = await FolderDropDelegate.assets(from: [provider, NSItemProvider(object: externalURL as NSURL)])
        #expect(result.ids == [first, second])
        #expect(result.urls == [externalURL])
        let invalid = await FolderDropDelegate.assets(from: [NSItemProvider(object: "not-an-asset" as NSString)])
        #expect(invalid.ids.isEmpty && invalid.urls.isEmpty)
    }
    @MainActor @Test func folderDropRejectsSelfAndDescendants() {
        let store = AppStore(openInitialLibrary: false)
        let a = LibraryFolder(name: "A"), b = LibraryFolder(name: "B")
        let child = LibraryFolder(name: "Child", parentID: b.id)
        store.folders = [a, b, child]
        var drop = FolderDropDelegate(store: store, folder: b, targeted: .constant(false), expanded: .constant(false))
        #expect(drop.canAccept(a.id))
        #expect(!drop.canAccept(b.id))
        drop.folder = child
        #expect(!drop.canAccept(b.id))
        #expect(!drop.canAccept(child.id))
        #expect(drop.canAccept(a.id))
    }
    @MainActor @Test func assetClickSelectsBeforeDoubleClickTimeoutAndClosesHover() async throws {
        _ = NSApplication.shared
        let store = AppStore(openInitialLibrary: false)
        let asset = Asset(name: "Click timing", ext: "png")
        store.assets = [asset]
        var hover: Asset? = asset
        let host = NSHostingView(rootView: AssetCard(store: store, asset: asset, height: 200,
            hoverPreview: Binding(get: { hover }, set: { hover = $0 })))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        func click(_ count: Int) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 130), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: count, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0))
                NSApp.sendEvent(event)
            }
        }
        try click(1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.selection == [asset.id])
        #expect(hover == nil)
        #expect(!store.showPreview)
        try click(2)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.showPreview && store.selectedAsset?.id == asset.id)
    }
    @MainActor @Test func magnifierClickOpensInlinePreviewAndClearsHover() async throws {
        _ = NSApplication.shared
        let store = AppStore(openInitialLibrary: false)
        let asset = Asset(name: "Magnifier", ext: "png")
        store.assets = [asset]
        var hover: Asset? = asset
        let host = NSHostingView(rootView: AssetCard(store: store, asset: asset, height: 200,
            hoverPreview: Binding(get: { hover }, set: { hover = $0 })))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        // The new 28-point button sits eight points inside the thumbnail's lower-right corner.
        let point = host.convert(NSPoint(x: host.bounds.maxX - 22, y: 178), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            NSApp.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.showPreview && store.selection == [asset.id])
        #expect(hover == nil)
    }
    @MainActor @Test func scrollWheelZoomTracksDirectionPrecisionAndBounds() {
        let enlarged = ScrollWheelZoom.adjustedZoom(1, delta: 1, precise: false)
        #expect(abs(enlarged - 1.1) < 0.000001)
        #expect(abs(ScrollWheelZoom.adjustedZoom(enlarged, delta: -1, precise: false) - 1) < 0.000001)
        #expect(ScrollWheelZoom.adjustedZoom(1, delta: 20, precise: true) == enlarged)
        #expect(ScrollWheelZoom.adjustedZoom(1, delta: 0, precise: false) == 1)
        #expect(ScrollWheelZoom.adjustedZoom(4, delta: 3, precise: false) == 4)
        #expect(ScrollWheelZoom.adjustedZoom(0.25, delta: -3, precise: false) == 0.25)
        #expect(ScrollWheelZoom.adjustedZoom(1, delta: 1000, precise: true) < 1.5)
        #expect(abs(ScrollWheelZoom.adjustedZoom(190, delta: 1, precise: false, limits: AppStore.thumbnailSizeRange) - 209) < 0.000001)
        #expect(ScrollWheelZoom.adjustedZoom(335, delta: 4, precise: false, limits: AppStore.thumbnailSizeRange) == 340)
        #expect(ScrollWheelZoom.adjustedZoom(125, delta: -4, precise: false, limits: AppStore.thumbnailSizeRange) == 120)
    }
    @MainActor @Test func marqueeSelectsIntersectingCardsWithoutTakingFileDrags() async throws {
        _ = NSApplication.shared
        let store = AppStore(openInitialLibrary: false)
        store.assets = (1...3).map { Asset(name: "Marquee \($0)", ext: "png") }
        store.thumbnailSize = 140
        let ids = store.assets.map(\.id)
        let host = NSHostingView(rootView: AssetBrowser(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        func receiver() -> MarqueeSelection.CaptureView? {
            var views: [NSView] = [host]
            while let view = views.popLast() {
                if let capture = view as? MarqueeSelection.CaptureView { return capture }
                views.append(contentsOf: view.subviews)
            }
            return nil
        }
        for layout in ["grid", "waterfall"] {
            store.layout = layout; host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let view = try #require(receiver())
            let first = try #require(view.frames[ids[0]]), second = try #require(view.frames[ids[1]])
            func event(_ type: NSEvent.EventType, _ point: CGPoint, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
            }
            let start = CGPoint(x: second.maxX + 4, y: max(first.maxY, second.maxY) + 25)
            let end = CGPoint(x: first.minX + 2, y: first.minY + 2)
            let onFile = try event(.leftMouseDown, CGPoint(x: first.midX, y: first.midY))
            #expect(view.handle(onFile) === onFile)
            store.selection = [ids[2]]
            #expect(view.handle(try event(.leftMouseDown, start)) == nil)
            #expect(store.selection.isEmpty)
            #expect(view.handle(try event(.leftMouseDragged, end)) == nil)
            #expect(store.selection == Set(ids.prefix(2)) && view.marquee != nil)
            _ = view.handle(try event(.leftMouseDragged, CGPoint(x: second.midX, y: second.midY)))
            #expect(store.selection == [ids[1]])
            _ = view.handle(try event(.leftMouseUp, end))
            #expect(view.marquee == nil)
            for modifiers in [NSEvent.ModifierFlags.command, .shift] {
                store.selection = [ids[2]]
                _ = view.handle(try event(.leftMouseDown, start, modifiers: modifiers))
                _ = view.handle(try event(.leftMouseDragged, end, modifiers: modifiers))
                #expect(store.selection == Set(ids))
                _ = view.handle(try event(.leftMouseUp, end, modifiers: modifiers))
            }
            _ = view.handle(try event(.leftMouseDown, start))
            let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            #expect(view.handle(escape) == nil && store.selection == Set(ids))
            view.enabled = false
            let disabled = try event(.leftMouseDown, start)
            #expect(view.handle(disabled) === disabled)
        }
    }
    @MainActor @Test func optionScrollResizesThumbnailsOnlyInBrowser() async throws {
        final class ScrollEvent: NSEvent {
            var target: NSWindow?
            var point = NSPoint(x: 400, y: 350)
            var delta = 1.0
            var modifiers: NSEvent.ModifierFlags = .option
            override var window: NSWindow? { target }
            override var locationInWindow: NSPoint { point }
            override var modifierFlags: NSEvent.ModifierFlags { modifiers }
            override var scrollingDeltaY: CGFloat { delta }
            override var scrollingDeltaX: CGFloat { 0 }
            override var hasPreciseScrollingDeltas: Bool { false }
            override var isDirectionInvertedFromDevice: Bool { false }
            override var momentumPhase: NSEvent.Phase { [] }
        }
        _ = NSApplication.shared
        let preferences = ["layout", "thumbnailSize"].map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer { for (key, value) in preferences { UserDefaults.standard.set(value, forKey: key) } }
        let store = AppStore(openInitialLibrary: false)
        store.assets = [Asset(name: "Scroll shortcut", ext: "png")]
        store.thumbnailSize = 190; store.layout = "grid"
        let host = NSHostingView(rootView: ContentView(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        func capture() -> ScrollWheelZoom.CaptureView? {
            var views: [NSView] = [host]
            while let view = views.popLast() {
                if let capture = view as? ScrollWheelZoom.CaptureView { return capture }
                views.append(contentsOf: view.subviews)
            }
            return nil
        }
        let event = ScrollEvent(); event.target = window
        for layout in ["grid", "waterfall"] {
            store.layout = layout
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let receiver = try #require(capture())
            event.modifiers = []
            #expect(receiver.handleScroll(event) === event)
            #expect(abs(store.thumbnailSize - 190) < 0.000001)
            event.modifiers = .option; event.point.x = 20
            #expect(receiver.handleScroll(event) === event)
            #expect(abs(store.thumbnailSize - 190) < 0.000001)
            event.point.x = 400; event.delta = 1
            #expect(receiver.handleScroll(event) == nil)
            #expect(abs(store.thumbnailSize - 209) < 0.000001)
            event.delta = -1
            #expect(receiver.handleScroll(event) == nil)
            #expect(abs(store.thumbnailSize - 190) < 0.000001)
        }
        store.showPreview = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(try #require(capture()).handleScroll(event) === event)
        #expect(abs(store.thumbnailSize - 190) < 0.000001)
        store.showPreview = false; store.layout = "list"
        try await Task.sleep(for: .milliseconds(100))
        #expect(capture() == nil)
        #expect(abs(store.thumbnailSize - 190) < 0.000001)
    }
    @MainActor @Test func inlinePreviewPreservesSelectionAndEndsOnNavigation() {
        let store = AppStore(openInitialLibrary: false)
        let first = Asset(name: "First", ext: "png"), second = Asset(name: "Second", ext: "png")
        store.assets = [first, second]
        store.preview(first)
        #expect(store.showPreview && store.selectedAsset?.id == first.id)
        store.nextAsset(1)
        #expect(store.showPreview && store.selectedAsset?.id == second.id)
        store.showPreview = false
        #expect(store.selectedAsset?.id == second.id)
        store.preview()
        store.selection.formIntersection([])
        #expect(!store.showPreview)
        store.preview(first)
        store.navigate(.uncategorized)
        store.refreshTask?.cancel()
        #expect(!store.showPreview && store.selection.isEmpty)
        store.preview()
        #expect(!store.showPreview)
    }
    @MainActor @Test func folderIconCatalogRendersAndSupportsCategorySearch() {
        #expect(Set(FolderIcons.all.map(\.symbol)).count == FolderIcons.all.count)
        for icon in FolderIcons.all {
            #expect(NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil) != nil, "Missing symbol: \(icon.symbol)")
        }
        #expect(FolderIcons.matching("摄影").flatMap(\.icons).contains { $0.symbol == "camera" })
        #expect(FolderIcons.matching("PHOTOGRAPHY").flatMap(\.icons).contains { $0.symbol == "camera" })
        #expect(FolderIcons.matching("设计 字体").flatMap(\.icons).map(\.symbol) == ["character.book.closed"])
        #expect(FolderIcons.matching("", category: "工作项目").map(\.title) == ["工作项目"])
        #expect(FolderIcons.matching("不存在的图标关键词").isEmpty)
    }
    @MainActor @Test func localOCRRecognizesFixtureText() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 220, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 900, height: 220)).fill()
        ("OPENEAGLE 2026" as NSString).draw(at: NSPoint(x: 40, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 70), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
        let text = try await MediaService.shared.recognizeText(at: file)
        #expect(text.uppercased().contains("OPENEAGLE") && text.contains("2026"))
    }
    @Test func metadataDraftPreservesConcurrentUneditedFields() {
        var asset = Asset(name: "Original", ext: "png")
        var draft = AssetMetadataDraft(asset)
        draft.edited.note = "My new note"
        asset.name = "Renamed by API"; asset.tags = ["Concurrent tag"]
        draft.apply(to: &asset)
        #expect(asset.name == "Renamed by API" && asset.tags == ["Concurrent tag"])
        #expect(asset.note == "My new note")
    }
    @MainActor @Test func nativePreviewViewsCanBeReplaced() async throws {
        _ = NSApplication.shared
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).txt")
        try Data("Quick Look lifecycle regression".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let host = NSHostingView(rootView: AnyView(QuickLookPreview(url: file)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.rootView = AnyView(Button("Underlying asset") {}.frame(maxWidth: .infinity, maxHeight: .infinity).overlay {
            QuickLookPreview(url: file).frame(maxWidth: .infinity, maxHeight: .infinity).padding(12).allowsHitTesting(false)
        })
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        var subviews = host.subviews
        var preview: QLPreviewView?
        while let view = subviews.popLast() {
            if let found = view as? QLPreviewView { preview = found; break }
            subviews.append(contentsOf: view.subviews)
        }
        let overlay = try #require(preview)
        for size in [CGSize(width: 400, height: 300), CGSize(width: 900, height: 520)] {
            window.setContentSize(size)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let frame = overlay.convert(overlay.bounds, to: host)
            #expect(frame == host.bounds.insetBy(dx: 12, dy: 12))
        }
        var ancestor: NSView? = host.hitTest(NSPoint(x: 200, y: 150))
        while let view = ancestor {
            #expect(!(view is QLPreviewView), "Hover preview must not intercept the card's pointer events")
            ancestor = view.superview
        }
        host.rootView = AnyView(NativePlayerView(player: AVPlayer(), audioOnly: false))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.rootView = AnyView(Text("Preview replaced"))
        host.layoutSubtreeIfNeeded()
        window.close()
        #expect(host.fittingSize.width >= 0)
    }
    @Test func thumbnailDimensionsAndClockwiseExport() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("openeagle-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("original.png"), thumbnail = base.appendingPathComponent("thumbnail.png"), rotated = base.appendingPathComponent("rotated.png")
        var pixels = [UInt8](repeating: 255, count: 80 * 40 * 4)
        for y in 0..<20 { for x in 0..<40 { let p = (y * 80 + x) * 4; pixels[p + 1] = 0; pixels[p + 2] = 0 } }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 80, height: 40, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 80 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let destination = CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let info = await MediaService.shared.analyze(source, kind: .image, thumbnail: thumbnail)
        #expect(info.width == 80 && info.height == 40)
        #expect(FileManager.default.fileExists(atPath: thumbnail.path))
        #expect(!info.colors.isEmpty)
        try await MediaService.shared.exportImage(source, to: rotated, format: "png", maxPixels: 0, rotate: true)
        let result = NSBitmapImageRep(data: try Data(contentsOf: rotated))!
        #expect(result.pixelsWide == 40 && result.pixelsHigh == 80)
        let topRight = result.colorAt(x: 35, y: 5)!
        let topLeft = result.colorAt(x: 5, y: 5)!
        #expect(topRight.redComponent > 0.95 && topRight.greenComponent < 0.05)
        #expect(topLeft.redComponent > 0.95 && topLeft.greenComponent > 0.95)
    }
}

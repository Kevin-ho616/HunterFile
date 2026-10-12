import SwiftUI
import AppKit

struct AssetBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct MarqueeSelection: NSViewRepresentable {
    var frames: [String: CGRect]
    var enabled: Bool
    @Binding var selection: Set<String>
    var onBegin: () -> Void
    var onEnd: () -> Void

    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.frames = frames; view.enabled = enabled
        view.readSelection = { selection }; view.select = { selection = $0 }
        view.onBegin = onBegin; view.onEnd = onEnd
    }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.stopMonitoring() }

    final class CaptureView: NSView {
        var frames: [String: CGRect] = [:]
        var enabled = true
        var readSelection: () -> Set<String> = { [] }
        var select: (Set<String>) -> Void = { _ in }
        var onBegin: () -> Void = {}
        var onEnd: () -> Void = {}
        private var monitor: Any?
        private var start: CGPoint?
        private var initial: Set<String> = []
        private var additive = false
        private(set) var marquee: CGRect?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown, .scrollWheel]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        func handle(_ event: NSEvent) -> NSEvent? {
            guard enabled, !isHiddenOrHasHiddenAncestor, event.window === window else {
                finish(); return event
            }
            let point = convert(event.locationInWindow, from: nil)
            switch event.type {
            case .leftMouseDown:
                guard visibleRect.contains(point), !frames.values.contains(where: { $0.contains(point) }) else { return event }
                start = point; initial = readSelection()
                additive = !event.modifierFlags.intersection([.command, .shift]).isEmpty
                onBegin()
                if !additive { select([]) }
                return nil
            case .leftMouseDragged:
                guard let start else { return event }
                let end = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
                guard marquee != nil || hypot(end.x - start.x, end.y - start.y) >= 4 else { return nil }
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
                marquee = rect
                let hits = Set(frames.filter { $0.key != "loadMore" && $0.value.intersects(rect) }.map(\.key))
                select(additive ? initial.union(hits) : hits)
                needsDisplay = true
                return nil
            case .leftMouseUp:
                guard start != nil else { return event }
                finish(); return nil
            case .keyDown where event.keyCode == 53:
                guard start != nil else { return event }
                select(initial); finish(); return nil
            case .scrollWheel:
                if start != nil { finish() }
                return event
            default: return event
            }
        }
        private func finish() {
            guard start != nil else { return }
            start = nil; marquee = nil; needsDisplay = true; onEnd()
        }
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            finish()
        }
        override func draw(_ dirtyRect: NSRect) {
            guard let marquee else { return }
            let path = NSBezierPath(rect: marquee.intersection(bounds).insetBy(dx: 0.5, dy: 0.5))
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke(); path.lineWidth = 1; path.stroke()
        }
    }
}

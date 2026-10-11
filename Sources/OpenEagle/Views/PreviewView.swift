import SwiftUI
import Quartz
import AVKit
import PDFKit
import CoreText
import OpenEagleCore

struct PreviewView: View {
    @Bindable var store: AppStore
    @FocusState private var previewFocused: Bool
    @State private var zoom = 1.0
    @State private var annotate = false
    @State private var annotationText = ""
    @State private var pendingRect: CGRect?
    @State private var dragStart: CGPoint?
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var background = 0
    private var asset: Asset? { store.selectedAsset }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { store.showPreview = false } label: { Label("返回素材", systemImage: "chevron.left") }.keyboardShortcut(.escape, modifiers: []).help("返回素材（Esc）")
                VStack(alignment: .leading, spacing: 3) {
                    Text(asset?.name ?? "预览").font(.headline).lineLimit(1)
                    Text([asset?.ext.uppercased() ?? "", asset?.dimensions ?? ""].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { openWindow() } label: { Image(systemName: "macwindow.on.rectangle") }.help("在独立窗口中打开")
                Button { store.openExternally() } label: { Image(systemName: "arrow.up.right.square") }.help("在默认应用中打开")
            }.buttonStyle(.borderless).padding(.horizontal, 17).padding(.vertical, 12)
            if asset?.kind == .image {
                HStack(spacing: 12) {
                    Button { annotate.toggle(); zoom = 1 } label: { Label("标注", systemImage: annotate ? "rectangle.dashed.badge.record" : "rectangle.and.pencil.and.ellipsis") }.tint(annotate ? .accentColor : .secondary)
                    Button { background = (background + 1) % 3 } label: { Image(systemName: "circle.lefthalf.filled") }.help("切换预览背景")
                    Spacer()
                    Slider(value: $zoom, in: ScrollWheelZoom.range).frame(width: 100).disabled(annotate).accessibilityLabel("预览缩放")
                    Button("\(Int(zoom * 100))%") { zoom = 1 }.monospacedDigit().frame(width: 55)
                }.buttonStyle(.borderless).padding(.horizontal, 17).padding(.bottom, 12)
            }
            Divider()
            if let asset, let repository = store.repository {
                GeometryReader { geometry in
                    ZStack {
                        (background == 0 ? Color(nsColor: .underPageBackgroundColor) : (background == 1 ? .white : Color(white: 0.09)))
                        if asset.kind == .image && asset.ext != "gif", let image {
                            let imageSize = fitted(image.size, in: CGSize(width: geometry.size.width - 48, height: geometry.size.height - 40))
                            ScrollView([.horizontal, .vertical]) {
                                ZStack(alignment: .topLeading) {
                                    Image(nsImage: image).resizable().interpolation(.high).frame(width: imageSize.width * zoom, height: imageSize.height * zoom)
                                    ForEach(asset.annotations) { annotation in
                                        let rect = CGRect(x: annotation.x * imageSize.width * zoom, y: annotation.y * imageSize.height * zoom, width: annotation.width * imageSize.width * zoom, height: annotation.height * imageSize.height * zoom)
                                        Rectangle().stroke(.orange, lineWidth: 2).background(.orange.opacity(0.09)).frame(width: max(10, rect.width), height: max(10, rect.height)).overlay(alignment: .topLeading) {
                                            Text(annotation.text).font(.system(size: 10)).lineLimit(2).padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4)).offset(y: -26)
                                        }.offset(x: rect.minX, y: rect.minY).help(annotation.text)
                                            .contextMenu { Button("删除标注", role: .destructive) { store.edit(ids: [asset.id]) { $0.annotations.removeAll { $0.id == annotation.id } } } }
                                    }
                                    if let rect = pendingRect {
                                        Rectangle().stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [5])).background(.orange.opacity(0.08)).frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                                    }
                                    if annotate {
                                        Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 2).onChanged { value in
                                            dragStart = value.startLocation
                                            let x = max(0, min(value.startLocation.x, value.location.x)), y = max(0, min(value.startLocation.y, value.location.y))
                                            pendingRect = CGRect(x: min(x, imageSize.width), y: min(y, imageSize.height), width: max(1, min(abs(value.location.x - value.startLocation.x), imageSize.width - x)), height: max(1, min(abs(value.location.y - value.startLocation.y), imageSize.height - y)))
                                        })
                                    }
                                }.frame(width: imageSize.width * zoom, height: imageSize.height * zoom)
                                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                            }
                            .background(ScrollWheelZoom(zoom: $zoom, enabled: !annotate))
                            .overlay(alignment: .bottom) {
                                if annotate, let rect = pendingRect {
                                    HStack {
                                        TextField("输入这处素材的备注…", text: $annotationText).textFieldStyle(.roundedBorder).frame(minWidth: 100, idealWidth: 270, maxWidth: 270)
                                        Button("保存标注") {
                                            let annotation = Annotation(x: rect.minX / imageSize.width, y: rect.minY / imageSize.height, width: rect.width / imageSize.width, height: rect.height / imageSize.height, text: annotationText.trimmed)
                                            store.edit(ids: [asset.id]) { $0.annotations.append(annotation) }
                                            pendingRect = nil; annotationText = ""; annotate = false
                                        }.buttonStyle(.borderedProminent).disabled(annotationText.trimmed.isEmpty)
                                        Button("取消") { pendingRect = nil; annotate = false }
                                    }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(16)
                                } else if annotate { Text("在图片上拖出矩形，添加位置标注").font(.caption).padding(10).background(.regularMaterial, in: Capsule()).padding(14) }
                            }
                        } else if asset.kind == .video || asset.kind == .audio {
                            NativePlayerView(player: player, audioOnly: asset.kind == .audio).padding(20)
                        } else if asset.kind == .font {
                            FontPreview(url: repository.fileURL(for: asset))
                        } else if asset.ext == "pdf" {
                            PDFPreview(url: repository.fileURL(for: asset), page: store.semanticHits[asset.id]?.page)
                        } else if asset.kind == .bookmark {
                            VStack(spacing: 22) {
                                Image(systemName: "globe").font(.system(size: 65, weight: .ultraLight)).foregroundStyle(.tint)
                                Text(asset.name).font(.title2)
                                Text(asset.sourceURL).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
                                if let url = URL(string: asset.sourceURL), ["http", "https"].contains(url.scheme ?? "") { Link("在浏览器中打开", destination: url).buttonStyle(.borderedProminent) }
                            }.padding(40)
                        } else { QuickLookPreview(url: repository.fileURL(for: asset)) }
                    }
                }
                .task(id: asset.id) {
                    zoom = 1; pendingRect = nil; annotate = false; image = nil; player?.pause(); player = nil
                    if asset.kind == .image && asset.ext != "gif" { image = await ThumbnailCache.shared.image(at: repository.fileURL(for: asset)) }
                    if asset.kind == .video || asset.kind == .audio {
                        player = AVPlayer(url: repository.fileURL(for: asset))
                        if let seconds = store.semanticHits[asset.id]?.seconds { await player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
                    }
                }
            }
            Divider()
            HStack(spacing: 22) {
                Button { store.nextAsset(-1) } label: { Image(systemName: "chevron.left") }.help("上一项（←）")
                Text(position).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Button { store.nextAsset(1) } label: { Image(systemName: "chevron.right") }.help("下一项（→）")
                Spacer()
                if let asset { Text(ByteCountFormatter.string(fromByteCount: asset.byteCount, countStyle: .file)).font(.caption).foregroundStyle(.tertiary) }
                Button("在 Finder 中显示") { store.revealSelection() }.font(.caption)
            }.buttonStyle(.borderless).padding(15)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
            .focusable(true, interactions: .edit).focusEffectDisabled().focused($previewFocused)
            .task { await Task.yield(); previewFocused = true }
            .onKeyPress(.leftArrow) { guard previewFocused else { return .ignored }; store.nextAsset(-1); return .handled }
            .onKeyPress(.rightArrow) { guard previewFocused else { return .ignored }; store.nextAsset(1); return .handled }
            .onDisappear { player?.pause(); player = nil }
    }
    private var position: String { "\((asset.flatMap { store.assets.firstIndex(of: $0) } ?? 0) + 1) / \(store.assets.count)" }
    private func fitted(_ size: CGSize, in available: CGSize) -> CGSize {
        let ratio = min(available.width / max(1, size.width), available.height / max(1, size.height))
        return CGSize(width: size.width * ratio, height: size.height * ratio)
    }
    private func openWindow() {
        guard let asset, let repository = store.repository else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = asset.name; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DetachedPreview(url: repository.fileURL(for: asset), window: window))
        window.center(); window.makeKeyAndOrderFront(nil)
        store.windows.removeAll { !$0.isVisible }; store.windows.append(window)
    }
}

struct ScrollWheelZoom: NSViewRepresentable {
    @Binding var zoom: Double
    var enabled: Bool
    static let range = 0.25...4.0
    var limits: ClosedRange<Double> = Self.range
    var requiredModifiers: NSEvent.ModifierFlags = []

    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.requiredModifiers = requiredModifiers
        view.onScroll = enabled ? { event in
            let delta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
            zoom = Self.adjustedZoom(zoom, delta: delta, precise: event.hasPreciseScrollingDeltas, limits: limits)
        } : nil
    }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.stopMonitoring() }
    static func adjustedZoom(_ zoom: Double, delta: Double, precise: Bool, limits: ClosedRange<Double> = Self.range) -> Double {
        let step = min(4, max(-4, delta / (precise ? 20 : 1)))
        return min(limits.upperBound, max(limits.lowerBound, zoom * pow(1.1, step)))
    }

    final class CaptureView: NSView {
        var onScroll: ((NSEvent) -> Void)?
        var requiredModifiers: NSEvent.ModifierFlags = []
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handleScroll(event)
            }
        }
        func handleScroll(_ event: NSEvent) -> NSEvent? {
            guard let onScroll, event.window === window,
                  event.modifierFlags.isSuperset(of: requiredModifiers),
                  !isHiddenOrHasHiddenAncestor,
                  bounds.contains(convert(event.locationInWindow, from: nil)),
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
            if event.momentumPhase.isEmpty { onScroll(event) }
            return nil
        }
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
    }
}

private struct DetachedPreview: View {
    let url: URL
    weak var window: NSWindow?
    @State private var pinned = false
    var body: some View {
        VStack {
            HStack { Spacer(); Toggle("置顶", isOn: $pinned).toggleStyle(.checkbox).onChange(of: pinned) { window?.level = pinned ? .floating : .normal } }.padding(10)
            QuickLookPreview(url: url)
        }
    }
}

struct QuickLookPreview: NSViewRepresentable {
    var url: URL?
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.shouldCloseWithWindow = false
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) { if (view.previewItem as? NSURL) != url as NSURL? { view.previewItem = url as NSURL? } }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

struct NativePlayerView: NSViewRepresentable {
    var player: AVPlayer?
    var audioOnly: Bool
    func makeNSView(context: Context) -> AVPlayerView { AVPlayerView() }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.controlsStyle = audioOnly ? .inline : .floating
        view.showsFullScreenToggleButton = !audioOnly
        if view.player !== player { view.player = player }
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player?.pause(); view.player = nil }
}

private struct PDFPreview: NSViewRepresentable {
    var url: URL
    var page: Int?
    class Coordinator { var page: Int? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; return view }
    func updateNSView(_ view: PDFView, context: Context) {
        let changed = view.document?.documentURL != url
        if changed { view.document = PDFDocument(url: url) }
        if changed || context.coordinator.page != page, let page, let target = view.document?.page(at: page - 1) { view.go(to: target) }
        context.coordinator.page = page
    }
}

private struct FontPreview: View {
    var url: URL
    @State private var font: NSFont?
    @State private var loaded = false
    @State private var text = "灵感，触手可及。\nThe quick brown fox jumps over the lazy dog.\nABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789 & @ # ! ?"
    @State private var size = 40.0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("字体预览").font(.headline); Spacer(); Slider(value: $size, in: 14...100).frame(width: 180); Text("\(Int(size)) pt").monospacedDigit() }
            if let font { TextEditor(text: $text).font(Font(font.withSize(size))).scrollContentBackground(.hidden) }
            else if loaded { QuickLookPreview(url: url) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.padding(35).task(id: url) {
            loaded = false; font = nil
            if let provider = CGDataProvider(url: url as CFURL), let cg = CGFont(provider) { font = CTFontCreateWithGraphicsFont(cg, size, nil, nil) as NSFont }
            loaded = true
        }
    }
}

// Controlled fixtures, not a real-library accuracy benchmark. Usage: swift script/make_ai_test_media.swift /absolute/output/path
import AppKit
import AVFoundation
import CoreVideo
import PDFKit

struct Topic {
    let title: String
    let emoji: String
    let text: String
    let queries: [String]
}
let topics = [
    Topic(title: "太空探索", emoji: "🚀", text: "运载火箭将卫星送入轨道。航天器离开地球后在太空飞行，宇航员在空间站开展实验。", queries: ["飞向宇宙的航天主题图片", "带火箭图案的宣传海报", "把卫星送到地球轨道的资料", "出现火箭的画面"]),
    Topic(title: "海洋生态", emoji: "🐠", text: "珊瑚礁为热带鱼提供栖息环境。潜水观察记录海底生物的活动，海水污染会影响珊瑚和鱼类的生存。", queries: ["海底生物主题的图片", "有热带鱼的设计参考", "保护珊瑚和鱼类的资料", "出现鱼的画面"]),
    Topic(title: "森林保护", emoji: "🌲", text: "森林由树木、灌木和地表植物组成。保护林地能够维持生物多样性。植树和减少砍伐有助于恢复林地。", queries: ["树木和自然保护主题的海报", "松树图案的素材", "植树恢复林地的资料", "出现树木的画面"]),
    Topic(title: "城市交通", emoji: "🚆", text: "铁路和地铁承担城市公共交通。乘客在车站换乘，轨道运输可以减少道路拥堵。时刻表用于安排列车运行。", queries: ["铁路出行主题的图片", "有列车图案的宣传图", "减少城市道路拥堵的轨道交通资料", "出现列车的画面"]),
    Topic(title: "摄影创作", emoji: "📷", text: "摄影通过相机记录光线。镜头焦距影响视角，光圈和快门控制曝光。摄影师使用三脚架稳定相机。", queries: ["拍照和影像创作主题的图片", "照相机图案的设计素材", "镜头焦距与曝光参数的资料", "出现相机的画面"]),
    Topic(title: "音乐演出", emoji: "🎸", text: "吉他手在舞台上演奏，乐队成员配合节奏。现场演出使用扩音设备，排练时需要校准乐器并检查音响。", queries: ["乐队演出主题的宣传图片", "带吉他图案的音乐海报", "舞台乐器和音响排练的资料", "出现吉他的画面"]),
    Topic(title: "咖啡冲煮", emoji: "☕", text: "咖啡豆经过烘焙和研磨后用于冲煮。水温、研磨粗细和萃取时间影响风味。咖啡馆提供手冲和浓缩咖啡。", queries: ["咖啡馆主题的图片", "咖啡杯图案的海报", "研磨粗细与萃取风味的资料", "出现咖啡杯的画面"]),
    Topic(title: "烘焙制作", emoji: "🥐", text: "面粉和黄油用于制作面包。可颂面团通过折叠形成层次，发酵后放入烤箱。温度和时间影响酥脆程度。", queries: ["面包店主题的图片", "可颂面包图案的海报", "黄油面团折叠和发酵的资料", "出现面包的画面"]),
    Topic(title: "宠物陪伴", emoji: "🐈", text: "猫是常见的家庭宠物。养猫需要准备食物、水和猫砂。猫会通过叫声、尾巴姿态和身体动作表达状态。", queries: ["家庭养猫主题的图片", "有猫咪图案的素材", "猫砂与宠物照料的资料", "出现猫的画面"]),
    Topic(title: "自行车运动", emoji: "🚲", text: "骑行使用自行车进行运动和通勤。出发前检查轮胎、链条和刹车。骑车人佩戴头盔，在允许骑行的道路上行进。", queries: ["骑行运动主题的图片", "自行车图案的宣传海报", "车胎链条与刹车检查的资料", "出现自行车的画面"]),
    Topic(title: "机器人制造", emoji: "🤖", text: "工业机器人在工厂执行装配和搬运。传感器检测位置，机械臂按照控制程序运动。自动化系统需要校准和维护。", queries: ["工厂自动化主题的图片", "带机器人图案的设计素材", "机械臂装配和传感器校准的资料", "出现机器人的画面"]),
    Topic(title: "图书阅读", emoji: "📚", text: "图书馆按主题管理书籍。读者通过目录寻找图书，阅读后记录笔记。书架编号和索引帮助定位资料。", queries: ["读书和图书馆主题的图片", "书本图案的宣传海报", "通过目录和书架编号找书的资料", "出现书本的画面"])
]
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let rect = CGRect(x: 0, y: 0, width: 640, height: 640)
// The system font's PDF character map substitutes some simplified Chinese glyphs with radicals.
let pdfFont = NSFont(name: "ArialUnicodeMS", size: 25)!
var frames: [CGImage] = [], assets: [[String: Any]] = [], queries: [[String: Any]] = []
for (index, topic) in topics.enumerated() {
    let id = String(format: "%02d", index + 1)
    let imageName = "image-\(id).png", documentName = "document-\(id).pdf"
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedHue: CGFloat(index) / CGFloat(topics.count), saturation: 0.3, brightness: 0.94, alpha: 1).setFill(); NSBezierPath(rect: rect).fill()
    (topic.emoji as NSString).draw(at: CGPoint(x: 180, y: 260), withAttributes: [.font: NSFont(name: "AppleColorEmoji", size: 230)!])
    (topic.title as NSString).draw(at: CGPoint(x: 95, y: 140), withAttributes: [.font: NSFont.systemFont(ofSize: 58, weight: .semibold), .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(imageName), options: .atomic)
    frames.append(bitmap.cgImage!)
    assets.append(["file": imageName, "topic": topic.title, "kind": "image"])
    var mediaBox = CGRect(x: 0, y: 0, width: 600, height: 800)
    let pdfURL = root.appendingPathComponent(documentName)
    let pdf = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil)!
    for content in ["项目执行清单\n\n资料收集、工作分配、版本记录、结果检查。\n请在第二页阅读具体内容。", "\(topic.title)\n\n\(topic.text)"] {
        pdf.beginPDFPage(nil); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
        (content as NSString).draw(in: CGRect(x: 50, y: 150, width: 500, height: 550), withAttributes: [.font: pdfFont, .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState(); pdf.endPDFPage()
    }
    pdf.closePDF()
    assert(PDFDocument(url: pdfURL)?.pageCount == 2)
    let pageText = PDFDocument(url: pdfURL)?.page(at: 1)?.string?.precomposedStringWithCompatibilityMapping
    assert(pageText?.contains(topic.title) == true)
    assets.append(["file": documentName, "topic": topic.title, "kind": "document"])
    for (queryIndex, query) in topic.queries.enumerated() {
        let kind = queryIndex < 2 ? "image" : (queryIndex == 2 ? "document" : "video")
        var item: [String: Any] = ["query": query, "kind": kind, "expected": kind == "image" ? imageName : (kind == "document" ? documentName : "video-scenes.mov")]
        if kind == "document" { item["page"] = 2 }
        if kind == "video" { item["secondsStart"] = index * 6; item["secondsEnd"] = (index + 1) * 6 }
        queries.append(item)
    }
}
let videoURL = root.appendingPathComponent("video-scenes.mov")
if FileManager.default.fileExists(atPath: videoURL.path) { try FileManager.default.removeItem(at: videoURL) }
let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 640])
let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 640, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
writer.add(input); assert(writer.startWriting()); writer.startSession(atSourceTime: .zero)
for frame in 0..<(topics.count * 6 * 5) {
    while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
    var pixelBuffer: CVPixelBuffer?
    assert(CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &pixelBuffer) == kCVReturnSuccess)
    let buffer = pixelBuffer!; CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 640, height: 640, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    context.draw(frames[frame / 30], in: rect); CVPixelBufferUnlockBaseAddress(buffer, [])
    assert(adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 5)))
}
input.markAsFinished(); await writer.finishWriting(); assert(writer.status == .completed)
let videoDuration = try await AVURLAsset(url: videoURL).load(.duration).seconds
assert(videoDuration > 71)
assets.append(["file": "video-scenes.mov", "kind": "video", "topic": "12 scenes, 6 seconds each"])
queries.append(["query": "资料收集和版本记录的执行清单", "kind": "document", "expected": "document-01.pdf", "page": 1, "anyDocument": true])
queries.append(["query": "有关航天和宇宙探索的内容", "kind": "all", "expected": "image-01.png", "alsoExpected": ["document-01.pdf", "video-scenes.mov"]])
assert(queries.count == 50)
try JSONSerialization.data(withJSONObject: ["fixtureVersion": 1, "controlled": true, "assets": assets, "queries": queries], options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
print("Controlled AI fixtures: 12 images, 12 two-page PDFs, a 72-second video, 50 Chinese queries. \(root.path)")

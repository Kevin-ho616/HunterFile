import SwiftUI
import AppKit
import OpenEagleCore

struct FolderIcon: Identifiable {
    let symbol: String
    let title: String
    let keywords: String
    var id: String { symbol }
    init(_ symbol: String, _ title: String, _ keywords: String) {
        self.symbol = symbol; self.title = title; self.keywords = keywords
    }
}

enum FolderIcons {
    struct Group: Identifiable {
        let title: String
        let icons: [FolderIcon]
        var id: String { title }
    }
    static let groups: [Group] = [
        Group(title: "常用", icons: [
            .init("folder", "默认文件夹", "folder default 分类"),
            .init("star", "星标", "star favorite 常用 重要"),
            .init("heart", "喜欢", "heart favorite 收藏"),
            .init("bookmark", "书签", "bookmark 保存"),
            .init("flag", "旗标", "flag 标记"),
            .init("pin", "置顶", "pin 固定"),
            .init("tray", "收集箱", "inbox 待整理"),
            .init("archivebox", "归档", "archive 完成 存档"),
            .init("checkmark.seal", "精选", "approved checked 审核 完成"),
            .init("sparkles", "灵感", "sparkles inspiration 创意"),
            .init("lightbulb", "想法", "idea 灵感"),
            .init("paperclip", "附件", "attachment 资料")
        ]),
        Group(title: "设计创作", icons: [
            .init("paintpalette", "配色", "color palette 色彩"),
            .init("paintbrush", "绘画", "painting art 艺术"),
            .init("pencil.and.outline", "插画", "illustration 手绘"),
            .init("square.on.circle", "平面设计", "graphic design 视觉"),
            .init("point.topleft.down.to.point.bottomright.curvepath", "矢量", "vector svg 曲线"),
            .init("crop", "构图", "composition 裁切"),
            .init("rectangle.3.group", "版式", "layout 排版 海报"),
            .init("character.book.closed", "字体", "font typography 字型"),
            .init("circle.hexagongrid", "纹理", "texture pattern 材质"),
            .init("cube", "三维", "3d 模型 渲染"),
            .init("scribble.variable", "草图", "sketch 线稿"),
            .init("wand.and.stars", "AI 创作", "ai 生成 人工智能 生图"),
            .init("ruler", "规范", "guideline 尺寸 设计系统"),
            .init("scissors", "拼贴", "collage 剪纸"),
            .init("square.stack.3d.up", "图层", "layers 合成"),
            .init("pencil.tip.crop.circle", "图标设计", "icon logo 标志")
        ]),
        Group(title: "工作项目", icons: [
            .init("briefcase", "项目", "work project 工作"),
            .init("person.2", "团队", "team 协作"),
            .init("person.crop.rectangle", "客户", "client customer 品牌"),
            .init("checklist", "任务", "todo task 清单"),
            .init("calendar", "日程", "calendar schedule 计划"),
            .init("doc.text", "文档", "document 文件 资料"),
            .init("chart.bar", "数据", "data analysis 分析 图表"),
            .init("megaphone", "营销", "marketing campaign 广告 运营"),
            .init("shippingbox", "电商", "ecommerce 商品 包装"),
            .init("bag", "产品", "product shopping 购物"),
            .init("desktopcomputer", "网页", "website web 网站"),
            .init("iphone", "界面", "ui ux app 应用 交互"),
            .init("chevron.left.forwardslash.chevron.right", "开发", "code programming 编程"),
            .init("gearshape", "工程", "engineering 工业 机械"),
            .init("cpu", "科技", "technology robot 机器人 智能"),
            .init("graduationcap", "学习", "education learning 课程 研究")
        ]),
        Group(title: "图片分类", icons: [
            .init("photo", "图片", "image picture 照片"),
            .init("photo.on.rectangle.angled", "参考图", "reference moodboard 情绪板"),
            .init("camera", "摄影", "photography camera 相机 照片"),
            .init("person.crop.square", "人像", "portrait people 人物 肖像"),
            .init("mountain.2", "风景", "landscape nature 山水 自然"),
            .init("building.2", "建筑", "architecture city 城市"),
            .init("chair.lounge", "室内", "interior furniture 家居 家具"),
            .init("leaf", "植物", "plant botanical 花草"),
            .init("pawprint", "动物", "animal pet 宠物"),
            .init("fork.knife", "美食", "food restaurant 餐饮"),
            .init("tshirt", "服装", "fashion clothing 时尚"),
            .init("face.smiling", "表情", "emoji meme 表情包"),
            .init("rectangle.on.rectangle", "截图", "screenshot screen 屏幕"),
            .init("seal", "标志", "logo brand 品牌 徽章"),
            .init("square.grid.3x3", "图案", "pattern 背景 壁纸"),
            .init("hand.draw", "手绘", "drawing illustration 插画")
        ]),
        Group(title: "内容媒体", icons: [
            .init("film", "视频", "video movie 电影"),
            .init("video", "短视频", "short video 拍摄"),
            .init("play.rectangle", "教程", "tutorial course 课程"),
            .init("mic", "播客", "podcast voice 配音"),
            .init("waveform", "音频", "audio sound 声音"),
            .init("music.note", "音乐", "music bgm 配乐"),
            .init("newspaper", "文章", "article writing 公众号 写作"),
            .init("book", "阅读", "book reading 书籍"),
            .init("bubble.left.and.bubble.right", "访谈", "interview 沟通 对话"),
            .init("theatermasks", "故事", "story 剧本 戏剧"),
            .init("captions.bubble", "字幕", "caption subtitle 文案"),
            .init("antenna.radiowaves.left.and.right", "直播", "live broadcast 广播")
        ]),
        Group(title: "生活旅行", icons: [
            .init("house", "居家", "home 家庭"),
            .init("airplane", "旅行", "travel trip 出行"),
            .init("map", "地点", "map location 地图"),
            .init("globe", "世界", "world 地理"),
            .init("sun.max", "日光", "sun light 光影"),
            .init("moon", "夜景", "night moon 夜晚"),
            .init("gift", "礼物", "gift event 节日 活动"),
            .init("figure.run", "运动", "sport fitness 健身")
        ])
    ]
    static let all = groups.flatMap(\.icons)
    static func title(for symbol: String?) -> String { all.first { $0.symbol == (symbol ?? "folder") }?.title ?? "自选图标" }
    static func matching(_ query: String, category: String = "") -> [Group] {
        let terms = query.searchFolded.split(whereSeparator: \.isWhitespace)
        return groups.filter { category.isEmpty || $0.title == category }.compactMap { group in
            let icons = group.icons.filter { icon in
                let text = "\(group.title) \(icon.title) \(icon.symbol) \(icon.keywords)".searchFolded
                return terms.allSatisfy { text.contains($0) }
            }
            return icons.isEmpty ? nil : Group(title: group.title, icons: icons)
        }
    }
}

struct FolderSymbol: View {
    let folder: LibraryFolder
    var size: CGFloat = 14
    private var symbol: String {
        guard let icon = folder.icon, NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil else { return "folder" }
        return icon
    }
    var body: some View {
        Image(systemName: symbol).font(.system(size: size)).foregroundStyle(Color(hex: folder.color))
            .frame(width: size + 4, height: size + 4)
            .overlay(alignment: .bottomTrailing) {
                if folder.password != nil {
                    Image(systemName: "lock.fill").font(.system(size: size * 0.55, weight: .semibold))
                        .padding(1).background(.background, in: Circle()).offset(x: 2, y: 2).help("有密码保护")
                }
            }
    }
}

struct FolderIconPicker: View {
    @Binding var icon: String?
    var color: Color
    @State private var query = ""
    @State private var category = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    private var groups: [FolderIcons.Group] { FolderIcons.matching(query, category: category) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("图标库").font(.headline)
                Text("\(FolderIcons.all.count) 个图标").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭图标库")
            }.padding(16)
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索：摄影、设计、项目…", text: $query).textFieldStyle(.plain).focused($searchFocused)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("清除图标搜索") }
                }.padding(8).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                Picker("图标分类", selection: $category) {
                    Text("全部分类").tag("")
                    ForEach(FolderIcons.groups) { Text($0.title).tag($0.title) }
                }.labelsHidden().frame(width: 122)
            }.padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            ScrollView {
                if groups.isEmpty {
                    ContentUnavailableView("没有匹配的图标", systemImage: "magnifyingglass", description: Text("试试“人像”“品牌”或“视频”等关键词。")).frame(minHeight: 260)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(group.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                                    ForEach(group.icons) { item in
                                        let selected = (icon ?? "folder") == item.symbol
                                        Button {
                                            icon = item.symbol == "folder" ? nil : item.symbol
                                            dismiss()
                                        } label: {
                                            VStack(spacing: 7) {
                                                Image(systemName: item.symbol).font(.system(size: 21)).frame(height: 26).foregroundStyle(color)
                                                Text(item.title).font(.system(size: 10)).foregroundStyle(.primary).lineLimit(1)
                                            }.frame(maxWidth: .infinity).frame(height: 66)
                                                .background(selected ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5) }
                                        }.buttonStyle(.plain).help(item.title).accessibilityLabel(item.title).accessibilityAddTraits(selected ? [.isSelected] : [])
                                    }
                                }
                            }
                        }
                    }.padding(16)
                }
            }.frame(height: 330)
            Divider()
            HStack {
                Image(systemName: icon ?? "folder").foregroundStyle(color)
                Text("当前：\(FolderIcons.title(for: icon))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") { icon = nil; dismiss() }.buttonStyle(.link)
            }.padding(14)
        }.frame(width: 490).onAppear { searchFocused = true }
    }
}

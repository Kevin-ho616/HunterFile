import SwiftUI
import HunterFilesCore

struct FilterBar: View {
    @Bindable var store: AppStore
    @State private var advanced = false
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Picker("类型", selection: $store.filter.kind) {
                    Text("全部类型").tag(nil as AssetKind?)
                    ForEach(AssetKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }.frame(width: 122)
                Picker("星级", selection: $store.filter.minRating) {
                    Text("不限评分").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0) 星及以上").tag($0) }
                }.frame(width: 130)
                Picker("形状", selection: $store.filter.shape) {
                    Text("全部比例").tag("")
                    Text("横向").tag("landscape"); Text("纵向").tag("portrait"); Text("正方形").tag("square"); Text("超宽图").tag("wide")
                }.frame(width: 116)
                Spacer(minLength: 0)
                Button { advanced.toggle() } label: { Label("更多条件", systemImage: "slider.horizontal.3") }.popover(isPresented: $advanced) { AdvancedFilters(filter: $store.filter).frame(width: 350).padding(20) }
                Button("重置") { store.filter = .init() }.buttonStyle(.link)
                Button { store.sheet = .smart(nil) } label: { Image(systemName: "folder.badge.plus") }.help("保存为智能文件夹")
            }.labelsHidden().controlSize(.small)
            HStack(spacing: 8) {
                Text("颜色").font(.caption).foregroundStyle(.secondary)
                ForEach(MediaService.palette, id: \.self) { hex in
                    Button { store.filter.color = store.filter.color == hex ? "" : hex } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 18, height: 18).overlay { Circle().stroke(store.filter.color == hex ? Color.primary : Color.clear, lineWidth: 2).padding(-3) }
                    }.buttonStyle(.plain).help(hex).accessibilityLabel("按颜色 \(hex) 筛选")
                }
                Spacer()
                if !store.filter.color.isEmpty { Button("清除颜色") { store.filter.color = "" }.buttonStyle(.link).font(.caption) }
            }
        }.padding(.horizontal, 22).padding(.bottom, 16)
    }
}

struct AdvancedFilters: View {
    @Binding var filter: AssetFilter
    var body: some View {
        Form {
            TextField("关键词", text: $filter.query)
            Picker("类型", selection: $filter.kind) {
                Text("不限").tag(nil as AssetKind?)
                ForEach(AssetKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            TextField("扩展名", text: $filter.ext, prompt: Text("png、pdf…"))
            TextField("包含标签", text: $filter.tag)
            Picker("最低评分", selection: $filter.minRating) { ForEach(0...5, id: \.self) { Text($0 == 0 ? "不限" : "\($0) 星").tag($0) } }
            Picker("形状", selection: $filter.shape) {
                Text("不限").tag(""); Text("横向").tag("landscape"); Text("纵向").tag("portrait"); Text("正方形").tag("square"); Text("超宽").tag("wide")
            }
            TextField("最小宽度 / px", value: $filter.minWidth, format: .number)
            TextField("最小高度 / px", value: $filter.minHeight, format: .number)
            TextField("最小字节数", value: $filter.minBytes, format: .number)
            TextField("最大字节数", value: $filter.maxBytes, format: .number)
            Picker("添加时间", selection: $filter.days) { Text("不限").tag(0); Text("最近 1 天").tag(1); Text("最近 7 天").tag(7); Text("最近 30 天").tag(30); Text("最近 90 天").tag(90) }
            Picker("颜色类别", selection: $filter.color) {
                Text("不限").tag("")
                ForEach(MediaService.palette, id: \.self) { hex in Text(hex).tag(hex) }
            }
            Text("数值为 0 表示不限。关键词按空格拆分，全部匹配。").font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder)
    }
}

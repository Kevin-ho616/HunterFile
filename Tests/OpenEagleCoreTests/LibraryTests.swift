import Foundation
import Testing
@testable import OpenEagleCore

struct LibraryTests {
    private func fixture() throws -> (URL, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("openeagle-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("灵感100%_晴天.txt")
        try Data("hello · 你好".utf8).write(to: file)
        return (base, file)
    }
    @Test func importSearchPersistenceAndBackup() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let url = base.appendingPathComponent("Test.openeagle")
        var library: LibraryRepository? = try LibraryRepository(url: url, create: true)
        var folder = LibraryFolder(name: "素材"); folder.icon = "camera"
        try await library!.saveFolder(folder)
        let imported = try await library!.importFile(file, folderIDs: [folder.id], tags: ["测试"])
        #expect(imported.duplicate == false)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try LibraryRepository.sha256(file) == LibraryRepository.sha256(library!.fileURL(for: imported.asset)))
        var asset = imported.asset; asset.rating = 4; asset.note = "可搜索的备注"; asset.favorite = true
        try await library!.save([asset])
        var filter = AssetFilter(); filter.query = "100%_ 晴天"
        #expect(try await library!.snapshot(filter: filter).total == 1)
        filter.query = "备注"
        #expect(try await library!.snapshot(filter: filter).total == 1)
        let backup = base.appendingPathComponent("Backup.openeagle")
        try await library!.backup(to: backup)
        library = nil
        library = try LibraryRepository(url: url)
        #expect(try await library!.asset(id: asset.id)?.rating == 4)
        #expect(try await library!.allFolders().first?.icon == "camera")
        let restored = try LibraryRepository(url: backup)
        #expect(try await restored.snapshot().total == 1)
        #expect(try await restored.allFolders().first?.icon == "camera")
        #expect(try await restored.snapshot(scope: .folder(folder.id)).assets.first?.tags == ["测试"])
    }
    @Test func foldersWithoutIconsRemainCompatibleAndCanReset() async throws {
        let legacy = Data(##"{"id":"9CDE3B98-4904-478C-A4BB-10289D359534","name":"旧文件夹","color":"#6E83E8","autoTags":[],"note":"保留描述","createdAt":0}"##.utf8)
        var folder = try JSONDecoder().decode(LibraryFolder.self, from: legacy)
        #expect(folder.icon == nil && folder.sortOrder == nil && folder.note == "保留描述")
        let (base, _) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Icons.openeagle"), create: true)
        folder.icon = "paintpalette"
        try await library.saveFolder(folder)
        #expect(try await library.allFolders().first?.icon == "paintpalette")
        folder.icon = nil
        try await library.saveFolder(folder)
        #expect(try await library.allFolders().first?.icon == nil)
        #expect(try await library.allFolders().first?.note == "保留描述")
    }
    @Test func deduplicationAndTrashAreReversible() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Test.openeagle"), create: true)
        let first = try await library.importFile(file)
        let second = try await library.importFile(file, tags: ["后来"])
        #expect(second.duplicate && second.asset.id == first.asset.id)
        #expect(try await library.snapshot().total == 1)
        try await library.setTrashed(ids: [first.asset.id], trashed: true)
        #expect(try await library.snapshot().total == 0)
        #expect(try await library.snapshot(scope: .trash).total == 1)
        try await library.setTrashed(ids: [first.asset.id], trashed: false)
        #expect(try await library.snapshot().assets.first?.tags == ["后来"])
        _ = try await library.importFile(file, tags: ["重复"], allowDuplicate: true)
        #expect(try await library.snapshot(scope: .duplicates).total == 2)
        #expect(try await library.mergeDuplicates() == 1)
        #expect(try await library.snapshot().assets.first?.tags == ["后来", "重复"])
        #expect(try await library.snapshot(scope: .trash).total == 1)
    }
    @Test func mergeDuplicatesKeepsExistingOriginal() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Test.openeagle"), create: true)
        let first = try await library.importFile(file).asset
        let second = try await library.importFile(file, allowDuplicate: true).asset
        try FileManager.default.removeItem(at: library.fileURL(for: first).deletingLastPathComponent())
        #expect(try await library.mergeDuplicates() == 1)
        #expect(try await library.snapshot().assets.map(\.id) == [second.id])
        #expect(try await library.snapshot(scope: .trash).assets.map(\.id) == [first.id])
        #expect(FileManager.default.fileExists(atPath: library.fileURL(for: second).path))
    }
    @Test func emptyTrashRemovesRecordsWithMissingAssetDirectories() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Test.openeagle"), create: true)
        let asset = try await library.importFile(file).asset
        try await library.setTrashed(ids: [asset.id], trashed: true)
        try FileManager.default.removeItem(at: library.fileURL(for: asset).deletingLastPathComponent())
        try await library.removeToSystemTrash(ids: [asset.id])
        #expect(try await library.snapshot(scope: .trash).total == 0)
    }
    @Test func hierarchicalFoldersSmartRulesAndTagMerge() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Test.openeagle"), create: true)
        let parent = LibraryFolder(name: "父文件夹")
        var child = LibraryFolder(name: "子文件夹", parentID: parent.id); child.autoTags = ["自动"]
        try await library.saveFolder(parent); try await library.saveFolder(child)
        let item = try await library.importFile(file, folderIDs: [child.id])
        #expect(item.asset.tags == ["自动"])
        #expect(try await library.snapshot(scope: .folder(parent.id), includeSubfolders: true).total == 1)
        var invalid = parent; invalid.parentID = child.id
        await #expect(throws: Error.self) { try await library.saveFolder(invalid) }
        var a = AssetFilter(); a.tag = "自动"
        var b = AssetFilter(); b.kind = .image
        let smart = SmartFolder(name: "任一条件", filters: [a, b], matchAll: false)
        try await library.saveSmartFolder(smart)
        #expect(try await library.snapshot(scope: .smart(smart.id)).total == 1)
        try await library.renameTag("自动", to: "合并")
        #expect(try await library.snapshot(scope: .tag("合并")).total == 1)
        try await library.deleteFolder(id: parent.id)
        #expect(try await library.snapshot(scope: .uncategorized).total == 1)
        #expect(FileManager.default.fileExists(atPath: library.fileURL(for: item.asset).path))
    }
    @Test func folderBrowsingCountsAndMovesRespectDescendantOption() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Folders.openeagle"), create: true)
        let root = LibraryFolder(name: "Root"), target = LibraryFolder(name: "Target")
        let parent = LibraryFolder(name: "Parent", parentID: root.id)
        let child = LibraryFolder(name: "Child", parentID: parent.id)
        var grandchild = LibraryFolder(name: "Grandchild", parentID: child.id)
        let folders = [root, parent, child, grandchild, target]
        for folder in folders { try await library.saveFolder(folder) }
        let shared = try await library.importFile(file, folderIDs: [parent.id, child.id], tags: ["查找"]).asset
        try Data("child original".utf8).write(to: file)
        let nested = try await library.importFile(file, folderIDs: [child.id, grandchild.id]).asset
        try Data("trashed original".utf8).write(to: file)
        let trash = try await library.importFile(file, folderIDs: [parent.id]).asset
        try await library.setTrashed(ids: [trash.id], trashed: true)
        #expect(try await library.snapshot(scope: .folder(root.id)).total == 0)
        #expect(try await library.snapshot(scope: .folder(parent.id)).assets.map(\.id) == [shared.id])
        #expect(try await library.snapshot(scope: .folder(root.id), includeSubfolders: true).total == 2)
        for recursive in [false, true] {
            for folder in folders {
                let snapshot = try await library.snapshot(scope: .folder(folder.id), limit: 1, includeSubfolders: recursive)
                let ids = try await library.matchingIDs(scope: .folder(folder.id), filter: .init(), includeSubfolders: recursive)
                #expect(snapshot.total == snapshot.folderCounts[folder.id, default: 0])
                #expect(snapshot.total == ids.count)
            }
        }
        var filter = AssetFilter(); filter.tag = "查找"
        let search = try await library.snapshot(scope: .folder(root.id), filter: filter, includeSubfolders: true)
        #expect(search.total == 1 && search.folderCounts[root.id] == 2)
        #expect(try await library.matchingIDs(scope: .folder(root.id), filter: filter, includeSubfolders: true) == [shared.id])

        let previous = try await library.moveAssets(ids: [shared.id, nested.id], fromFolder: parent.id, toFolder: target.id)
        #expect(previous.map(\.id) == [shared.id])
        #expect(try await library.snapshot(scope: .folder(parent.id)).total == 0)
        #expect(try await library.asset(id: shared.id)?.folderIDs == [child.id, target.id])
        #expect(try await library.asset(id: nested.id)?.folderIDs == nested.folderIDs)
        try await library.save(previous)
        let allPrevious = try await library.moveAssets(ids: [shared.id, nested.id], fromFolder: root.id, toFolder: target.id, includeSubfolders: true)
        #expect(allPrevious.count == 2)
        #expect(try await library.snapshot(scope: .folder(root.id), includeSubfolders: true).total == 0)
        try await library.save(allPrevious)
        grandchild.password = try PasswordDigest.create("test-password")
        try await library.saveFolder(grandchild); try await library.lockFolder(id: grandchild.id)
        let locked = try await library.snapshot(scope: .folder(root.id), includeSubfolders: true)
        #expect(locked.total == 1 && locked.folderCounts[root.id] == 1)
        #expect(locked.folderCounts[grandchild.id, default: 0] == 0)
    }
    @Test func assetMovesReplaceSourceMembershipAndUndoWithoutCopying() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let url = base.appendingPathComponent("Moves.openeagle")
        var library: LibraryRepository? = try LibraryRepository(url: url, create: true)
        let a = LibraryFolder(name: "A"), c = LibraryFolder(name: "C")
        var b = LibraryFolder(name: "B"); b.autoTags = ["目标"]
        var child = LibraryFolder(name: "A 的子级"); child.parentID = a.id
        for folder in [a, b, c, child] { try await library!.saveFolder(folder) }
        let first = try await library!.importFile(file, folderIDs: [a.id, c.id], tags: ["原标签"]).asset
        try Data("second original".utf8).write(to: file)
        let second = try await library!.importFile(file, folderIDs: [child.id, b.id]).asset
        let ids = [first.id, second.id]
        let before = try await library!.assets(ids: ids)
        #expect(try await library!.moveAssets(ids: ids, fromFolder: a.id, toFolder: a.id).isEmpty)
        await #expect(throws: Error.self) { try await library!.moveAssets(ids: ids, fromFolder: a.id, toFolder: "missing") }
        var locked = LibraryFolder(name: "锁定"); locked.password = try PasswordDigest.create("test-password")
        try await library!.saveFolder(locked); try await library!.lockFolder(id: locked.id)
        await #expect(throws: Error.self) { try await library!.moveAssets(ids: ids, fromFolder: a.id, toFolder: locked.id) }
        #expect(try await library!.assets(ids: ids) == before)

        let previous = try await library!.moveAssets(ids: ids, fromFolder: a.id, toFolder: b.id, includeSubfolders: true)
        #expect(previous == before)
        let moved = try await library!.assets(ids: ids)
        #expect(Set(moved[0].folderIDs) == Set([b.id, c.id]))
        #expect(moved[1].folderIDs == [b.id])
        #expect(Set(moved[0].tags) == Set(["原标签", "目标"]))
        #expect(try await library!.snapshot(scope: .folder(a.id)).total == 0)
        #expect(try await library!.snapshot(scope: .folder(b.id)).total == 2)
        #expect(try await library!.snapshot(scope: .folder(c.id)).total == 1)
        #expect(try await library!.snapshot().total == 2)
        for asset in moved { #expect(try LibraryRepository.sha256(library!.fileURL(for: asset)) == asset.hash) }
        #expect(try await library!.moveAssets(ids: ids, fromFolder: a.id, toFolder: b.id).isEmpty)

        try await library!.save(previous)
        for (restored, original) in zip(try await library!.assets(ids: ids), before) {
            #expect(restored.folderIDs == original.folderIDs && restored.tags == original.tags)
        }
        try await library!.save(moved)
        library = nil
        library = try LibraryRepository(url: url)
        #expect(try await library!.snapshot(scope: .folder(a.id)).total == 0)
        #expect(try await library!.snapshot(scope: .folder(b.id)).total == 2)
        #expect(try await library!.snapshot().total == 2)
    }
    @Test func folderMovesPersistOrderHierarchyAndAssetMembership() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let url = base.appendingPathComponent("Order.openeagle")
        var library: LibraryRepository? = try LibraryRepository(url: url, create: true)
        let a = LibraryFolder(name: "A"), b = LibraryFolder(name: "B")
        var c = LibraryFolder(name: "C"); c.password = try PasswordDigest.create("test-password")
        let child = LibraryFolder(name: "Child", parentID: b.id)
        for folder in [c, b, a, child] { try await library!.saveFolder(folder) }
        let asset = try await library!.importFile(file, folderIDs: [child.id]).asset
        try await library!.moveFolder(id: c.id, toParent: nil, before: a.id)
        #expect(try await library!.allFolders().filter { $0.parentID == nil }.map(\.id) == [c.id, a.id, b.id])
        try await library!.moveFolder(id: a.id, toParent: nil)
        #expect(try await library!.allFolders().filter { $0.parentID == nil }.map(\.id) == [c.id, b.id, a.id])
        try await library!.moveFolder(id: b.id, toParent: c.id)
        #expect(try await library!.snapshot(scope: .folder(c.id), includeSubfolders: true).assets.map(\.id) == [asset.id])
        let beforeInvalid = try await library!.allFolders()
        await #expect(throws: Error.self) { try await library!.moveFolder(id: c.id, toParent: c.id) }
        await #expect(throws: Error.self) { try await library!.moveFolder(id: c.id, toParent: child.id) }
        await #expect(throws: Error.self) { try await library!.moveFolder(id: a.id, toParent: "missing") }
        await #expect(throws: Error.self) { try await library!.moveFolder(id: a.id, toParent: nil, before: child.id) }
        #expect(try await library!.allFolders() == beforeInvalid)
        try await library!.moveFolder(id: b.id, toParent: nil, before: c.id)
        var renamed = try #require(try await library!.allFolders().first { $0.id == b.id })
        renamed.name = "Z renamed"; try await library!.saveFolder(renamed)
        let newFolder = LibraryFolder(name: "AA new"); try await library!.saveFolder(newFolder)
        #expect(try await library!.allFolders().filter { $0.parentID == nil }.map(\.id) == [b.id, c.id, a.id, newFolder.id])
        try await library!.lockFolder(id: c.id)
        await #expect(throws: Error.self) { try await library!.moveFolder(id: c.id, toParent: b.id) }
        await #expect(throws: Error.self) { try await library!.moveFolder(id: a.id, toParent: c.id) }
        // Reordering an unlocked sibling must not unlock a protected folder.
        try await library!.moveFolder(id: a.id, toParent: nil, before: b.id)
        #expect(try await library!.lockedAncestor(of: c.id)?.id == c.id)
        let expected = try await library!.allFolders()
        let backup = base.appendingPathComponent("Backup.openeagle")
        try await library!.backup(to: backup)
        library = nil
        library = try LibraryRepository(url: url)
        #expect(try await library!.allFolders() == expected)
        #expect(try await library!.allFolders().first { $0.id == child.id }?.parentID == b.id)
        #expect(try await library!.asset(id: asset.id)?.folderIDs == [child.id])
        #expect(try LibraryRepository.sha256(library!.fileURL(for: asset)) == asset.hash)
        let restored = try LibraryRepository(url: backup)
        #expect(try await restored.allFolders() == expected)
    }
    @Test func trustBoundariesAndNonOverwritingExport() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Test.openeagle")
        let library = try LibraryRepository(url: root, create: true)
        #expect(throws: Error.self) { try LibraryRepository(url: root) }
        #expect(throws: Error.self) { try library.checkedURL("../secret") }
        let result = try await library.importFile(file)
        var asset = result.asset; asset.relativePath = "../../secret"
        await #expect(throws: Error.self) { try await library.save([asset]) }
        let export = base.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        let first = try await library.export(ids: [result.asset.id], to: export, includeMetadata: true)
        let second = try await library.export(ids: [result.asset.id], to: export, includeMetadata: true)
        #expect(first.first != second.first)
        #expect(try FileManager.default.contentsOfDirectory(atPath: export.path).count == 4)
        await #expect(throws: Error.self) { try await library.backup(to: root.appendingPathComponent("nested")) }
    }
    @Test func eagleMigrationValidatesOriginalPaths() throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Eagle.library")
        let entry = root.appendingPathComponent("images/ABC.info")
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: entry.appendingPathComponent("Asset.txt"))
        try JSONSerialization.data(withJSONObject: ["folders": [["id": "F1", "name": "Eagle 文件夹", "children": []]]]).write(to: root.appendingPathComponent("metadata.json"))
        try JSONSerialization.data(withJSONObject: ["name": "Asset", "ext": "txt", "tags": ["迁移"], "folders": ["F1"], "star": 5]).write(to: entry.appendingPathComponent("metadata.json"))
        let plan = try EagleMigrationPlan.read(root)
        #expect(plan.entries.count == 1 && plan.folders.count == 1)
        #expect(plan.entries[0].folders == [plan.folders[0].id])
        #expect(plan.entries[0].rating == 5)
        try JSONSerialization.data(withJSONObject: ["name": "../../../secret", "ext": "txt"]).write(to: entry.appendingPathComponent("metadata.json"))
        let bad = try EagleMigrationPlan.read(root)
        #expect(bad.entries.isEmpty && bad.warnings.count == 1)
    }
    @Test func folderProtectionCoversSearchAPIAndHierarchy() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Test.openeagle"), create: true)
        let parent = LibraryFolder(name: "父文件夹")
        var secret = LibraryFolder(name: "私密", parentID: parent.id)
        secret.password = try PasswordDigest.create("test-password-123")
        try await library.saveFolder(parent); try await library.saveFolder(secret)
        let child = LibraryFolder(name: "嵌套", parentID: secret.id)
        try await library.saveFolder(child)
        let item = try await library.importFile(file, folderIDs: [child.id], tags: ["隐藏标签"])
        #expect(try await library.snapshot().total == 1)
        try await library.lockFolder(id: secret.id)
        #expect(try await library.snapshot().total == 0)
        #expect(try await library.snapshot().tags.isEmpty)
        #expect(try await library.asset(id: item.asset.id) == nil)
        #expect(try await library.matchingIDs(scope: .all, filter: .init()).isEmpty)
        #expect(try await library.lockedAncestor(of: child.id)?.id == secret.id)
        await #expect(throws: Error.self) { try await library.unlockFolder(id: secret.id, password: "wrong") }
        await #expect(throws: Error.self) { try await library.deleteFolder(id: parent.id) }
        var bypass = secret; bypass.password = nil
        await #expect(throws: Error.self) { try await library.saveFolder(bypass) }
        try await library.unlockFolder(id: secret.id, password: "test-password-123")
        #expect(try await library.snapshot().total == 1)
        #expect(try await library.asset(id: item.asset.id)?.tags == ["隐藏标签"])
    }
    @Test func failedBatchEditRollsBackAllItems() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Test.openeagle"), create: true)
        let first = try await library.importFile(file).asset
        let second = try await library.importFile(file, allowDuplicate: true).asset
        var a = first, b = second
        a.note = "不能部分提交"; b.rating = 99
        await #expect(throws: Error.self) { try await library.save([a, b]) }
        #expect(try await library.asset(id: first.id)?.note == "")
        b = second; b.relativePath = first.relativePath
        await #expect(throws: Error.self) { try await library.save([b]) }
    }
    @Test func interruptedImportRecoveryIsIdempotent() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Test.openeagle"), create: true)
        var asset = Asset(name: "中断后恢复", ext: "txt")
        asset.relativePath = "assets/\(asset.id)/original.txt"
        let directory = library.root.appendingPathComponent("assets/\(asset.id)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent("original.txt"))
        try JSONEncoder().encode(asset).write(to: directory.appendingPathComponent(".pending-import.json"))
        #expect(try await library.recoverInterruptedImports() == 1)
        #expect(try await library.recoverInterruptedImports() == 0)
        #expect(try await library.snapshot().total == 1)
    }
    @Test func assetPackRoundTripPreservesMetadataAndOriginals() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let source = try LibraryRepository(url: base.appendingPathComponent("Source.openeagle"), create: true)
        var parent = LibraryFolder(name: "项目"); parent.icon = "briefcase"; parent.sortOrder = 2
        var child = LibraryFolder(name: "海报", parentID: parent.id); child.icon = "paintpalette"; child.sortOrder = 3
        try await source.saveFolder(parent); try await source.saveFolder(child)
        var asset = try await source.importFile(file, folderIDs: [child.id], tags: ["迁移标签"]).asset
        asset.note = "保留备注"; asset.rating = 5; asset.annotations = [Annotation(x: 0.1, y: 0.1, width: 0.2, height: 0.2, text: "测试标注")]
        try await source.save([asset])
        let pack = base.appendingPathComponent("Export.openeaglepack")
        try await source.exportPack(ids: [asset.id], to: pack)
        let destination = try LibraryRepository(url: base.appendingPathComponent("Destination.openeagle"), create: true)
        let result = try await destination.importPack(pack)
        #expect(result.count == 1)
        #expect(result[0].asset.tags == asset.tags && result[0].asset.note == asset.note)
        #expect(result[0].asset.annotations == asset.annotations && result[0].asset.rating == 5)
        #expect(try await destination.allFolders().count == 2)
        let importedFolders = try await destination.allFolders()
        #expect(importedFolders.first { $0.name == "项目" }?.icon == "briefcase")
        #expect(importedFolders.first { $0.name == "海报" }?.icon == "paintpalette")
        #expect(importedFolders.first { $0.name == "项目" }?.sortOrder == 2)
        #expect(importedFolders.first { $0.name == "海报" }?.sortOrder == 3)
        #expect(try LibraryRepository.sha256(destination.fileURL(for: result[0].asset)) == asset.hash)
    }
    @Test func concurrentEditsDoNotLoseMetadata() async throws {
        let (base, file) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Test.openeagle"), create: true)
        let asset = try await library.importFile(file).asset
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 { group.addTask { _ = try await library.modify(ids: [asset.id]) { $0.tags.append("tag-\(index)") } } }
            try await group.waitForAll()
        }
        #expect(try await library.asset(id: asset.id)?.tags.count == 20)
    }
    @Test func largeIndexPaginationAndSearch() async throws {
        let (base, _) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let library = try LibraryRepository(url: base.appendingPathComponent("Index.openeagle"), create: true)
        try await library.seedIndexForTest(count: 25_000)
        let start = ContinuousClock.now
        let first = try await library.snapshot(limit: 500)
        #expect(first.total == 25_000 && first.assets.count == 500)
        var filter = AssetFilter(); filter.query = "检索标本"; filter.tag = "分类-7"; filter.minRating = 2
        let filtered = try await library.snapshot(filter: filter, limit: 1_000)
        #expect(filtered.total == 1_000 && filtered.assets.count == 1_000)
        let loaded = try await library.assets(ids: first.assets.map(\.id))
        #expect(loaded.map(\.id) == first.assets.map(\.id))
        print("25,000-row index: initial page, combined search and 500-item lookup in \(start.duration(to: .now))")
    }
}

private extension LibraryRepository {
    // Synthetic metadata only: this measures the index, not thumbnail rendering or file import.
    func seedIndexForTest(count: Int) throws {
        try db.transaction {
            for index in 0..<count {
                var asset = Asset(name: "检索标本 \(index)", ext: "png")
                asset.relativePath = "assets/\(asset.id)/original.png"
                asset.tags = ["分类-\(index % 25)"]; asset.rating = index % 5
                try upsert(asset)
            }
        }
    }
}

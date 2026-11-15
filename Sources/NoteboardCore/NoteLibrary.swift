import Foundation

/// 저장 폴더 하나를 다룬다. 노트 하나 = 파일 하나(`제목.md` / `제목.txt`).
/// 날짜는 파일의 생성·수정 시각을 그대로 쓴다.
public struct NoteLibrary: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder.standardizedFileURL
    }

    private var fm: FileManager { .default }

    public func ensureFolder() throws {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public static func isNoteFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }
        return NoteFormat(fileExtension: url.pathExtension) != nil
    }

    /// 폴더에 있는 이름들(숨김 파일 포함). 이름 겹침을 피할 때 쓴다.
    public func existingNames() -> Set<String> {
        Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    /// 노트 파일 목록. 최근 수정이 위로.
    public func list() -> [NoteSummary] {
        let urls = (try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls.filter(Self.isNoteFile)
            .compactMap(summary(for:))
            .sorted { $0.modified > $1.modified }
    }

    public func summary(for url: URL) -> NoteSummary? {
        guard let format = NoteFormat(fileExtension: url.pathExtension) else { return nil }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey])
        guard values?.isRegularFile ?? false else { return nil }
        let modified = values?.contentModificationDate ?? Date.distantPast
        let created = values?.creationDate ?? modified
        let body = (try? read(url)) ?? ""
        let stem = url.deletingPathExtension().lastPathComponent
        return NoteSummary(url: url.standardizedFileURL, title: NoteNaming.title(fromStem: stem), format: format,
                           created: created, modified: modified, body: body)
    }

    public func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s }
        // UTF-8 이 아니면(다른 편집기에서 만든 파일) 한국어 옛 인코딩을 한 번 더 시도한다.
        // 0x0422 = kCFStringEncodingDOSKorean (CP949, EUC-KR 의 확장)
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0422)))
        if let s = String(data: data, encoding: cp949) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    public func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func fileStem(title: String, created: Date) -> String {
        let clean = NoteNaming.sanitizedTitle(title)
        return clean.isEmpty ? NoteNaming.untitledStem(for: created) : clean
    }

    /// 새 노트 파일을 만든다. 돌려준 주소가 이 노트의 파일이 된다.
    @discardableResult
    public func create(text: String, title: String, format: NoteFormat, created: Date = Date()) throws -> URL {
        try ensureFolder()
        let name = NoteNaming.uniqueFileName(stem: fileStem(title: title, created: created),
                                             ext: format.fileExtension, existing: existingNames())
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url, options: [.withoutOverwriting])
        return url.standardizedFileURL
    }

    /// 내용을 저장한다. 통째로 바꿔 쓰는 방식이라 생성 시각이 지워지므로 원래 값을 되돌려 놓는다.
    public func write(_ text: String, to url: URL) throws {
        let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
        try Data(text.utf8).write(to: url, options: [.atomic])
        if let created {
            try? fm.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        }
    }

    /// 제목이나 포맷이 바뀌면 파일 이름을 바꾼다. 바뀐 주소를 돌려준다(같으면 그대로).
    public func rename(_ url: URL, title: String, format: NoteFormat) throws -> URL {
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let stem = fileStem(title: title, created: created)
        let wanted = "\(stem).\(format.fileExtension)"
        if wanted == url.lastPathComponent { return url }
        var names = existingNames()
        names.remove(url.lastPathComponent)
        // 대소문자만 바뀌는 경우도 같은 파일로 본다.
        let name = NoteNaming.uniqueFileName(stem: stem, ext: format.fileExtension, existing: names)
        let target = folder.appendingPathComponent(name)
        if name.lowercased() == url.lastPathComponent.lowercased() {
            // 대소문자만 다른 이름은 한 번에 못 바꾸니 임시 이름을 거친다.
            let temp = folder.appendingPathComponent(".rename-\(UUID().uuidString)")
            try fm.moveItem(at: url, to: temp)
            try fm.moveItem(at: temp, to: target)
        } else {
            try fm.moveItem(at: url, to: target)
        }
        return target.standardizedFileURL
    }

    /// 휴지통으로 보낸다(복구 가능).
    public func trash(_ url: URL) throws {
        try fm.trashItem(at: url, resultingItemURL: nil)
    }

    /// 아무것도 안 쓴 노트를 지운다. 비어 있을 때만 지운다.
    public func deleteIfBlank(_ url: URL) throws {
        guard let text = try? read(url), NoteText.isBlank(text) else { return }
        try fm.removeItem(at: url)
    }

    /// 노트 파일을 모두 새 폴더로 옮긴다. 옛 주소 → 새 주소 대응표를 돌려준다.
    public func moveAll(to newFolder: URL) throws -> [URL: URL] {
        let target = NoteLibrary(folder: newFolder)
        try target.ensureFolder()
        if target.folder == folder { return [:] }
        var mapping: [URL: URL] = [:]
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names.sorted() {
            let url = folder.appendingPathComponent(name)
            guard Self.isNoteFile(url) else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            let destName = NoteNaming.uniqueFileName(stem: stem, ext: url.pathExtension, existing: target.existingNames())
            let dest = target.folder.appendingPathComponent(destName)
            try fm.moveItem(at: url, to: dest)
            mapping[url.standardizedFileURL] = dest.standardizedFileURL
        }
        return mapping
    }
}

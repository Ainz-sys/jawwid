import Foundation

/// Where recitation files are kept on the device, and the downloads that fill it.
enum AudioFiles {
    /// Kept out of iCloud backups: the files can always be downloaded again.
    static let root: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var u = dir
        try? u.setResourceValues(values)
        return dir
    }()

    static func folder(_ r: Reciter) -> URL {
        root.appendingPathComponent(r.rawValue, isDirectory: true)
    }

    static func ensureFolder(_ r: Reciter) {
        try? FileManager.default.createDirectory(at: folder(r), withIntermediateDirectories: true)
    }

    static func ayahName(_ s: Int, _ a: Int) -> String { String(format: "%03d%03d.mp3", s, a) }

    static func surahName(_ s: Int) -> String { String(format: "%03d.mp3", s) }

    static func ayahFile(_ r: Reciter, _ s: Int, _ a: Int) -> URL {
        folder(r).appendingPathComponent(ayahName(s, a))
    }

    static func surahFile(_ r: Reciter, _ s: Int) -> URL {
        folder(r).appendingPathComponent(surahName(s))
    }

    /// Whether a surah is fully present, given the file names in its reciter's folder.
    static func isComplete(_ r: Reciter, _ s: Int, names: Set<String>) -> Bool {
        if !r.isAyahByAyah { return names.contains(surahName(s)) }
        let info = Quran.shared.surah(s)
        if info.hasBasmalaHeader && !names.contains(ayahName(1, 1)) { return false }
        return (1...info.ayahCount).allSatisfy { names.contains(ayahName(s, $0)) }
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Local file when downloaded, otherwise the online address.
    static func ayahURL(_ r: Reciter, _ s: Int, _ a: Int) -> URL? {
        let local = ayahFile(r, s, a)
        return exists(local) ? local : r.remoteURL(surah: s, ayah: a)
    }

    static func surahURL(_ r: Reciter, _ s: Int) -> URL? {
        let local = surahFile(r, s)
        return exists(local) ? local : r.remoteSurahURL(surah: s)
    }

    static func size(of r: Reciter) -> Int64 {
        let dir = folder(r)
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

@MainActor
final class Downloads: ObservableObject {
    static let shared = Downloads()

    struct Key: Hashable {
        let reciter: Reciter
        let surah: Int
    }

    /// Running downloads: fraction done (0…1).
    @Published private(set) var progress: [Key: Double] = [:]
    /// Surahs fully on the device.
    @Published private(set) var done: Set<Key> = []
    @Published private(set) var lastError: String?

    private var tasks: [Key: Task<Void, Never>] = [:]

    private init() {
        if Demo.active {
            done = [Key(reciter: .murattal, surah: 1), Key(reciter: .murattal, surah: 78)]
            progress = [Key(reciter: .murattal, surah: 2): 0.4]
            return
        }
        refresh()
    }

    func refresh() {
        var set = Set<Key>()
        for r in Reciter.allCases {
            let dir = AudioFiles.folder(r)
            let names = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            guard !names.isEmpty else { continue }
            for s in 1...114 where AudioFiles.isComplete(r, s, names: names) {
                set.insert(Key(reciter: r, surah: s))
            }
        }
        done = set
    }

    func isDone(_ r: Reciter, _ s: Int) -> Bool { done.contains(Key(reciter: r, surah: s)) }

    func fraction(_ r: Reciter, _ s: Int) -> Double? { progress[Key(reciter: r, surah: s)] }

    func start(_ r: Reciter, _ s: Int) {
        let key = Key(reciter: r, surah: s)
        guard tasks[key] == nil, !done.contains(key) else { return }
        lastError = nil
        progress[key] = 0
        tasks[key] = Task { [weak self] in
            await self?.run(key)
        }
    }

    func cancel(_ r: Reciter, _ s: Int) {
        let key = Key(reciter: r, surah: s)
        tasks[key]?.cancel()
        tasks[key] = nil
        progress[key] = nil
    }

    func delete(_ r: Reciter, _ s: Int) {
        cancel(r, s)
        let info = Quran.shared.surah(s)
        if r.isAyahByAyah {
            for a in 1...info.ayahCount { try? FileManager.default.removeItem(at: AudioFiles.ayahFile(r, s, a)) }
        } else {
            try? FileManager.default.removeItem(at: AudioFiles.surahFile(r, s))
        }
        done.remove(Key(reciter: r, surah: s))
        refresh()
    }

    func deleteAll(_ r: Reciter) {
        for key in tasks.keys where key.reciter == r { cancel(key.reciter, key.surah) }
        try? FileManager.default.removeItem(at: AudioFiles.folder(r))
        refresh()
    }

    private func run(_ key: Key) async {
        let r = key.reciter, s = key.surah
        var jobs: [(remote: URL, local: URL)] = []
        if r.isAyahByAyah {
            let info = Quran.shared.surah(s)
            var ayat = Array(1...info.ayahCount).map { (s, $0) }
            if info.hasBasmalaHeader { ayat.append((1, 1)) }
            for (su, a) in ayat {
                if let remote = r.remoteURL(surah: su, ayah: a) { jobs.append((remote, AudioFiles.ayahFile(r, su, a))) }
            }
        } else if let remote = r.remoteSurahURL(surah: s) {
            jobs.append((remote, AudioFiles.surahFile(r, s)))
        }
        AudioFiles.ensureFolder(r)
        let total = Double(max(jobs.count, 1))
        var finished = 0.0
        for job in jobs {
            if Task.isCancelled { return }
            if !AudioFiles.exists(job.local) {
                do {
                    let (tmp, response) = try await URLSession.shared.download(from: job.remote)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        try? FileManager.default.removeItem(at: tmp)
                        fail(key, "تعذّر تنزيل بعض الملفات. حاول مرة أخرى لاحقاً.")
                        return
                    }
                    try? FileManager.default.removeItem(at: job.local)
                    try FileManager.default.moveItem(at: tmp, to: job.local)
                } catch {
                    if Task.isCancelled { return }
                    fail(key, "تعذّر التنزيل. تحقّق من الاتصال بالإنترنت.")
                    return
                }
            }
            finished += 1
            progress[key] = finished / total
        }
        progress[key] = nil
        tasks[key] = nil
        done.insert(key)
    }

    private func fail(_ key: Key, _ message: String) {
        progress[key] = nil
        tasks[key] = nil
        lastError = message
    }
}

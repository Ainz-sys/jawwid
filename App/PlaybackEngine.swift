import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum PlayerPhase: Equatable {
    case idle        // nothing chosen yet
    case loading     // waiting for the audio
    case reciting    // the sheikh recites
    case gap         // the learner's turn to repeat
    case waiting     // manual mode: waiting for "next"
    case listening   // whole-surah teacher recording
    case finished
    case failed(String)
}

/// One entry of the playback plan: a recitation of an ayah, or the pause after it.
struct PlaybackStep: Equatable {
    enum Kind { case recite, gap, surah }
    let kind: Kind
    let surah: Int
    /// 0 = the basmala before the surah.
    let ayah: Int
    let repetition: Int
    let repetitions: Int
    /// Finishing this step completes the ayah (all repetitions heard and repeated).
    var endsAyah: Bool
}

/// Time inside the current item, kept apart so that only the progress bar redraws ten times a second.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
}

/// Plays the recitation ayah by ayah with the learner's pauses, repetitions and speed.
/// Each pause is a stretch of silent audio in the same queue, so playback goes on with the screen locked.
@MainActor
final class PlaybackEngine: ObservableObject {
    static let shared = PlaybackEngine()

    @Published private(set) var surah: Int?
    @Published private(set) var ayah: Int = 1
    @Published private(set) var repetition: Int = 1
    @Published private(set) var repetitions: Int = 1
    @Published private(set) var phase: PlayerPhase = .idle
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var wordRange: Range<Int>?
    @Published private(set) var reciter: Reciter = .murattal
    @Published private(set) var rangeStart: Int = 1
    @Published private(set) var rangeEnd: Int = 1

    let clock = PlaybackClock()

    var isActive: Bool { surah != nil && phase != .idle }

    /// Range chosen in the settings before playback started, per surah.
    private(set) var preparedRange: (surah: Int, start: Int, end: Int)?

    private let player = AVQueuePlayer()
    private var stepFor: [ObjectIdentifier: PlaybackStep] = [:]
    private var itemObservers: [ObjectIdentifier: AnyCancellable] = [:]
    private var gapAfter: [ObjectIdentifier: AVPlayerItem] = [:]
    private var lastReciteItem: AVPlayerItem?
    private var pending: [PlaybackStep] = []
    private var nextAyah: Int?
    private var barrier: Int?
    private var timings: [[Int]]?
    private var segments: [TimedSegment] = []
    private var currentStep: PlaybackStep?
    private var timeObserver: Any?
    private var bag = Set<AnyCancellable>()
    private var token = 0
    /// The learner asked for playback (and has not paused it); a call or Siri pausing the player does not change it.
    private var wantsToPlay = false
    private var resumeAfterInterruption = false
    private lazy var silence: AVURLAsset? = PlaybackEngine.makeSilence().map { AVURLAsset(url: $0) }

    private var settings: AppSettings { AppStore.shared.settings }

    private init() {
        player.actionAtItemEnd = .advance
        if Demo.active { return }
        observePlayer()
        observeSession()
        setupRemoteCommands()
    }

    // MARK: - Starting and stopping

    /// Starts (or restarts) a surah at an ayah. The range limits where playback stops.
    func start(surah s: Int, at a: Int, rangeStart: Int? = nil, rangeEnd: Int? = nil, autoplay: Bool = true) {
        guard !Demo.active else { return }
        let info = Quran.shared.surah(s)
        var lo = rangeStart ?? a
        var hi = rangeEnd ?? info.ayahCount
        if rangeStart == nil, rangeEnd == nil, let p = preparedRange, p.surah == s, a >= p.start, a <= p.end {
            lo = p.start
            hi = p.end
        }
        lo = min(max(lo, 1), info.ayahCount)
        hi = min(max(hi, lo), info.ayahCount)
        let first = min(max(a, lo), hi)

        clearQueue()
        token += 1
        wantsToPlay = autoplay
        let current = token
        let r = settings.reciter
        if r != reciter { timings = nil }
        surah = s
        reciter = r
        self.rangeStart = lo
        self.rangeEnd = hi
        ayah = first
        repetition = 1
        repetitions = r.isAyahByAyah ? max(1, settings.repeatCount) : 1
        wordRange = nil
        clock.elapsed = 0
        clock.duration = 0
        phase = .loading
        preparedRange = (s, lo, hi)
        activateSession()
        player.defaultRate = Float(settings.speed)
        AppStore.shared.setPosition(surah: s, ayah: first)

        if r.isAyahByAyah {
            nextAyah = (first == 1 && info.hasBasmalaHeader && settings.playBasmala) ? 0 : first
            Task {
                let t = await self.loadTimings(r)
                if self.reciter == r { self.timings = t }
                guard current == self.token else { return }
                self.refill()
                if autoplay { self.player.play() } else { self.player.pause() }
                self.updateNowPlaying()
            }
        } else {
            nextAyah = nil
            guard let url = AudioFiles.surahURL(r, s) else {
                phase = .failed("تعذّر العثور على التلاوة.")
                return
            }
            let item = AVPlayerItem(url: url)
            item.audioTimePitchAlgorithm = .spectral
            register(item, PlaybackStep(kind: .surah, surah: s, ayah: 0, repetition: 1, repetitions: 1, endsAyah: false))
            player.insert(item, after: nil)
            if autoplay { player.play() }
            updateNowPlaying()
        }
    }

    /// Stops playback and forgets the session.
    func stop() {
        clearQueue()
        token += 1
        wantsToPlay = false
        surah = nil
        phase = .idle
        isPlaying = false
        isBuffering = false
        wordRange = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Remembers a range for a surah; restarts within it if that surah is playing.
    func setRange(surah s: Int, start a: Int, end b: Int) {
        let info = Quran.shared.surah(s)
        let lo = min(max(a, 1), info.ayahCount)
        let hi = min(max(b, lo), info.ayahCount)
        preparedRange = (s, lo, hi)
        guard surah == s, isActive else { return }
        if lo != rangeStart || hi != rangeEnd {
            let resumeAt = (ayah >= lo && ayah <= hi) ? max(ayah, lo) : lo
            start(surah: s, at: resumeAt, rangeStart: lo, rangeEnd: hi, autoplay: isPlaying || phase == .loading)
        }
    }

    // MARK: - Transport

    func togglePlay() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        wantsToPlay = false
        player.pause()
        syncPlaying()
        updateNowPlaying()
    }

    func resume() {
        guard let s = surah else { return }
        switch phase {
        case .waiting:
            next()
        case .finished:
            start(surah: s, at: rangeStart, rangeStart: rangeStart, rangeEnd: rangeEnd)
        case .failed:
            start(surah: s, at: max(ayah, rangeStart), rangeStart: rangeStart, rangeEnd: rangeEnd)
        case .idle:
            start(surah: s, at: ayah)
        default:
            wantsToPlay = true
            activateSession()
            player.play()
            syncPlaying()
            updateNowPlaying()
        }
    }

    func next() {
        guard let s = surah else { return }
        if !reciter.isAyahByAyah {
            if s < 114 { start(surah: s + 1, at: 1) }
            return
        }
        if phase == .waiting, let b = barrier {
            barrier = nil
            if b < rangeEnd { restart(at: b + 1) } else { finish() }
            return
        }
        let target = ayah == 0 ? rangeStart : ayah + 1
        if target > rangeEnd {
            finish()
        } else {
            restart(at: target)
        }
    }

    func previous() {
        guard let s = surah else { return }
        if !reciter.isAyahByAyah {
            start(surah: s, at: 1)
            return
        }
        restart(at: max(rangeStart, ayah - 1))
    }

    /// Plays from a given ayah of the current surah (or starts that surah).
    func play(surah s: Int, from a: Int) {
        let same = surah == s && isActive && reciter == settings.reciter
        if same && !reciter.isAyahByAyah {
            // The teacher recording has no ayah times to jump to; a tap only starts it again once it has ended.
            switch phase {
            case .finished, .failed: start(surah: s, at: 1)
            default: break
            }
            return
        }
        if same, a >= rangeStart, a <= rangeEnd {
            restart(at: a)
        } else if same {
            start(surah: s, at: a, rangeStart: a, rangeEnd: Quran.shared.surah(s).ayahCount)
        } else {
            start(surah: s, at: a)
        }
    }

    func setSpeed(_ v: Double) {
        AppStore.shared.settings.speed = v
        player.defaultRate = Float(v)
        if player.rate > 0 { player.rate = Float(v) }
        updateNowPlaying()
    }

    /// Applies new repeat/pause/advance settings without cutting the current recitation.
    func settingsChanged() {
        guard let s = surah, isActive else { return }
        if settings.reciter != reciter {
            start(surah: s, at: max(ayah, rangeStart), rangeStart: rangeStart, rangeEnd: rangeEnd, autoplay: isPlaying)
            return
        }
        player.defaultRate = Float(settings.speed)
        // Waiting for "next" while the learner switches to automatic: go on by itself.
        if phase == .waiting {
            if settings.autoAdvance { next() }
            return
        }
        guard reciter.isAyahByAyah, let current = currentStep, let item = player.currentItem else { return }
        // Drop everything queued after the current item and plan the rest of this ayah again.
        for queued in player.items().dropFirst() {
            forget(queued)
            player.remove(queued)
        }
        pending = []
        barrier = nil
        let total = max(1, settings.repeatCount)
        let withGap = settings.pauseMode != .none
        // A repetition beyond the new count counts as the last one.
        let rep = min(current.repetition, total)
        let shown = max(current.repetition, total)
        var remainder: [PlaybackStep] = []
        if current.kind == .recite && withGap {
            remainder.append(PlaybackStep(kind: .gap, surah: current.surah, ayah: current.ayah, repetition: current.repetition,
                                          repetitions: shown, endsAyah: rep == total))
        }
        if rep < total {
            for r in (rep + 1)...total {
                remainder.append(PlaybackStep(kind: .recite, surah: current.surah, ayah: current.ayah, repetition: r,
                                              repetitions: shown, endsAyah: !withGap && r == total))
                if withGap {
                    remainder.append(PlaybackStep(kind: .gap, surah: current.surah, ayah: current.ayah, repetition: r,
                                                  repetitions: shown, endsAyah: r == total))
                }
            }
        }
        var updated = current
        updated.endsAyah = rep == total && (current.kind == .gap || !withGap)
        stepFor[ObjectIdentifier(item)] = updated
        currentStep = updated
        repetitions = shown
        pending = remainder
        lastReciteItem = current.kind == .recite ? item : nil
        advancePlanning(after: current.ayah)
        refill()
        updateNowPlaying()
    }

    // MARK: - Planning

    private func plan(surah s: Int, ayah a: Int) -> [PlaybackStep] {
        let reps = max(1, settings.repeatCount)
        let withGap = settings.pauseMode != .none
        var steps: [PlaybackStep] = []
        for r in 1...reps {
            steps.append(PlaybackStep(kind: .recite, surah: s, ayah: a, repetition: r, repetitions: reps,
                                      endsAyah: !withGap && r == reps))
            if withGap {
                steps.append(PlaybackStep(kind: .gap, surah: s, ayah: a, repetition: r, repetitions: reps,
                                          endsAyah: r == reps))
            }
        }
        return steps
    }

    private func advancePlanning(after a: Int) {
        if a == 0 {
            nextAyah = rangeStart
        } else if a >= rangeEnd {
            nextAyah = nil
        } else if !settings.autoAdvance {
            nextAyah = nil
            barrier = a
        } else {
            nextAyah = a + 1
        }
    }

    /// Keeps a few items queued ahead, so the next ayah or pause is ready without any gap.
    private func refill() {
        guard let s = surah, reciter.isAyahByAyah else { return }
        while player.items().count < 4 {
            if pending.isEmpty {
                guard let a = nextAyah else { break }
                pending = plan(surah: s, ayah: a)
                advancePlanning(after: a)
            }
            guard !pending.isEmpty else { break }
            enqueue(pending.removeFirst())
        }
    }

    private func enqueue(_ step: PlaybackStep) {
        let item: AVPlayerItem
        switch step.kind {
        case .recite:
            let source = step.ayah == 0 ? AyahRef(surah: 1, ayah: 1) : AyahRef(surah: step.surah, ayah: step.ayah)
            guard let url = AudioFiles.ayahURL(reciter, source.surah, source.ayah) else { return }
            item = AVPlayerItem(url: url)
            item.audioTimePitchAlgorithm = .spectral
        case .gap:
            guard let asset = silence else { return }
            item = AVPlayerItem(asset: asset)
            item.forwardPlaybackEndTime = CMTime(seconds: gapLength(ayah: step.ayah, base: nil), preferredTimescale: 600)
            if let before = lastReciteItem { gapAfter[ObjectIdentifier(before)] = item }
        case .surah:
            return
        }
        register(item, step)
        player.insert(item, after: nil)
        lastReciteItem = step.kind == .recite ? item : nil
    }

    private func restart(at a: Int) {
        guard let s = surah else { return }
        // Only ayah-by-ayah recordings can start at an ayah; the teacher recording starts over.
        guard reciter.isAyahByAyah else {
            start(surah: s, at: a)
            return
        }
        clearQueue()
        token += 1
        ayah = a
        wordRange = nil
        phase = .loading
        nextAyah = a
        AppStore.shared.setPosition(surah: s, ayah: a)
        wantsToPlay = true
        activateSession()
        refill()
        player.play()
        syncPlaying()
    }

    private func finish() {
        clearQueue()
        token += 1
        wantsToPlay = false
        phase = .finished
        wordRange = nil
        syncPlaying()
        updateNowPlaying()
    }

    private func clearQueue() {
        player.pause()
        player.removeAllItems()
        stepFor.removeAll()
        itemObservers.removeAll()
        gapAfter.removeAll()
        lastReciteItem = nil
        pending = []
        nextAyah = nil
        barrier = nil
        currentStep = nil
        segments = []
    }

    private func forget(_ item: AVPlayerItem) {
        let id = ObjectIdentifier(item)
        stepFor[id] = nil
        itemObservers[id] = nil
        gapAfter[id] = nil
    }

    // MARK: - Lengths

    private func loadTimings(_ r: Reciter) async -> [[Int]]? {
        guard let resource = r.timingResource else { return nil }
        return await TimingStore.shared.timings(for: resource)
    }

    private func timingIndex(ayah a: Int) -> Int? {
        guard let s = surah else { return nil }
        return a == 0 ? 0 : Quran.shared.globalIndex(s, a)
    }

    /// Length of the sheikh's recitation of the ayah, from the word timings.
    private func recitedLength(ayah a: Int) -> Double? {
        guard let t = timings, let g = timingIndex(ayah: a), g < t.count, let len = Timings.recitedLength(t[g]) else { return nil }
        return len + 0.3
    }

    /// Pause length in media seconds (the silence plays at the chosen speed too).
    private func gapLength(ayah a: Int, base: Double?) -> Double {
        let rate = max(settings.speed, 0.5)
        let ayahLength = base ?? recitedLength(ayah: a) ?? 5
        let real: Double
        switch settings.pauseMode {
        case .ayahLength: real = ayahLength / rate
        case .oneAndHalf: real = ayahLength * 1.5 / rate
        case .fixed: real = Double(settings.fixedPause)
        case .none: real = 0
        }
        return min(max(real * rate, 1), 175)
    }

    // MARK: - Observing the player

    private func register(_ item: AVPlayerItem, _ step: PlaybackStep) {
        let id = ObjectIdentifier(item)
        stepFor[id] = step
        itemObservers[id] = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self, let item else { return }
                self.itemStatusChanged(item, status)
            }
    }

    private func observePlayer() {
        player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.currentItemChanged() }
            .store(in: &bag)
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncPlaying() }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.itemEnded(note.object as? AVPlayerItem) }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.itemFailed(note.object as? AVPlayerItem) }
            .store(in: &bag)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func currentItemChanged() {
        guard surah != nil else { return }
        if let item = player.currentItem {
            guard let step = stepFor[ObjectIdentifier(item)] else { return }
            apply(step, item)
            refill()
        } else {
            queueEmptied()
        }
    }

    private func apply(_ step: PlaybackStep, _ item: AVPlayerItem) {
        currentStep = step
        if ayah != step.ayah { ayah = step.ayah }
        repetition = step.repetition
        repetitions = step.repetitions
        wordRange = nil
        switch step.kind {
        case .recite:
            phase = .reciting
            if let g = timingIndex(ayah: step.ayah), let t = timings, g < t.count {
                segments = Timings.segments(t[g])
            } else {
                segments = []
            }
            if step.repetition == 1, step.ayah >= 1, let s = surah {
                AppStore.shared.setPosition(surah: s, ayah: step.ayah)
            }
        case .gap:
            phase = .gap
            segments = []
        case .surah:
            phase = .listening
            segments = []
        }
        clock.elapsed = 0
        if step.kind == .gap {
            clock.duration = CMTimeGetSeconds(item.forwardPlaybackEndTime) / max(settings.speed, 0.5)
        } else {
            let d = CMTimeGetSeconds(item.duration)
            clock.duration = d.isFinite && d > 0 ? d : (recitedLength(ayah: step.ayah) ?? 0)
        }
        updateNowPlaying()
    }

    private func tick() {
        guard let item = player.currentItem, let step = currentStep else { return }
        let t = CMTimeGetSeconds(item.currentTime())
        guard t.isFinite else { return }
        switch step.kind {
        case .gap:
            let rate = max(settings.speed, 0.5)
            clock.elapsed = t / rate
            clock.duration = CMTimeGetSeconds(item.forwardPlaybackEndTime) / rate
        case .recite, .surah:
            clock.elapsed = t
            let d = CMTimeGetSeconds(item.duration)
            if d.isFinite, d > 0, abs(d - clock.duration) > 0.05 { clock.duration = d }
        }
        if step.kind == .recite {
            let w = Timings.words(at: t, in: segments)
            if w != wordRange { wordRange = w }
        }
    }

    private func itemStatusChanged(_ item: AVPlayerItem, _ status: AVPlayerItem.Status) {
        guard let step = stepFor[ObjectIdentifier(item)] else { return }
        if status == .failed {
            itemFailed(item)
            return
        }
        // Without word timings, size the following pause from the real length of the recording.
        if status == .readyToPlay, step.kind == .recite, recitedLength(ayah: step.ayah) == nil,
           let gap = gapAfter[ObjectIdentifier(item)] {
            let d = CMTimeGetSeconds(item.duration)
            if d.isFinite, d > 0 {
                gap.forwardPlaybackEndTime = CMTime(seconds: gapLength(ayah: step.ayah, base: d), preferredTimescale: 600)
            }
        }
    }

    private func itemEnded(_ item: AVPlayerItem?) {
        guard let item, let step = stepFor[ObjectIdentifier(item)] else { return }
        if step.endsAyah, step.ayah >= 1 {
            AppStore.shared.markCompleted(surah: step.surah, ayah: step.ayah)
        }
        if step.kind == .surah {
            phase = .finished
        }
    }

    private func itemFailed(_ item: AVPlayerItem?) {
        guard let item, stepFor[ObjectIdentifier(item)] != nil else { return }
        clearQueue()
        token += 1
        wantsToPlay = false
        wordRange = nil
        phase = .failed("تعذّر تشغيل التلاوة. تحقّق من الاتصال بالإنترنت، أو نزّل السورة لتعمل دون اتصال.")
        syncPlaying()
        updateNowPlaying()
    }

    private func queueEmptied() {
        switch phase {
        case .idle, .loading, .failed, .finished, .waiting:
            return
        default:
            break
        }
        if pending.isEmpty && nextAyah == nil {
            if let b = barrier {
                phase = .waiting
                ayah = b
            } else {
                phase = .finished
            }
            wantsToPlay = false
            wordRange = nil
            syncPlaying()
            updateNowPlaying()
        } else {
            refill()
            player.play()
        }
    }

    private func syncPlaying() {
        let playing = player.timeControlStatus != .paused && player.currentItem != nil
        if playing != isPlaying { isPlaying = playing }
        let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if buffering != isBuffering { isBuffering = buffering }
    }

    // MARK: - Audio session, lock screen

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func observeSession() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleInterruption(note) }
            .store(in: &bag)
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // By now the system may already have paused the player, so go by what the learner asked for.
            resumeAfterInterruption = wantsToPlay
            syncPlaying()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: (info[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0)
            if options.contains(.shouldResume) && resumeAfterInterruption {
                resume()
            } else if resumeAfterInterruption {
                wantsToPlay = false
            }
            resumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        _ = center.playCommand.addTarget { _ in
            Task { @MainActor in PlaybackEngine.shared.resume() }
            return .success
        }
        _ = center.pauseCommand.addTarget { _ in
            Task { @MainActor in PlaybackEngine.shared.pause() }
            return .success
        }
        _ = center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in PlaybackEngine.shared.togglePlay() }
            return .success
        }
        _ = center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in PlaybackEngine.shared.next() }
            return .success
        }
        _ = center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in PlaybackEngine.shared.previous() }
            return .success
        }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        guard let s = surah, phase != .idle else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let surahTitle = Quran.shared.surah(s).title
        let title: String
        switch phase {
        case .gap: title = "دورك: كرّر الآية \(Arabic.n(ayah))"
        case .waiting: title = "اضغط «التالي» للمتابعة"
        case .listening, .finished, .failed: title = surahTitle
        default: title = ayah == 0 ? "البسملة" : "الآية \(Arabic.n(ayah))"
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: Reciter.reciterName,
            MPMediaItemPropertyAlbumTitle: surahTitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? settings.speed : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: settings.speed,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.elapsed,
        ]
        if clock.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = clock.duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Silence for the pauses

    /// Three minutes of silence, made once and cut to length for each pause.
    private static func makeSilence() -> URL? {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("silence-180s.caf")
        // 180 s of 16-bit samples at 8 kHz; a shorter file was cut off while being written.
        let fullSize = 180 * 8000 * 2
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size >= fullSize {
            return url
        }
        try? FileManager.default.removeItem(at: url)
        let rate = 8000.0
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true) else { return nil }
        let frames = AVAudioFrameCount(rate * 10)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.int16ChannelData else { return nil }
        buffer.frameLength = frames
        channel[0].initialize(repeating: 0, count: Int(frames))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            for _ in 0..<18 { try file.write(from: buffer) }
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    // MARK: - Screenshots

    /// Freezes the player in one state for simulator screenshots (no audio).
    func showDemo(surah s: Int, ayah a: Int, words: Range<Int>?, phase p: PlayerPhase, repetition r: Int, repetitions n: Int,
                  elapsed: Double, duration: Double, playing: Bool) {
        surah = s
        ayah = a
        wordRange = words
        phase = p
        repetition = r
        repetitions = n
        rangeStart = a
        rangeEnd = Quran.shared.surah(s).ayahCount
        isPlaying = playing
        reciter = settings.reciter
        clock.elapsed = elapsed
        clock.duration = duration
    }
}

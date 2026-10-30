import SwiftUI
import AVKit
import Supabase
import HomePlateScoringCore

private struct GameRecordingRow: Decodable, Identifiable, Sendable {
  let id: UUID; let started_at: Date; let status: String; let assembled_path: String?
}
private struct GameVideoSegmentRow: Decodable, Identifiable, Sendable {
  let id: UUID; let start_ms: Double; let end_ms: Double; let playback_path: String?
  let storage_path: String; let bytes: Int64
}
private struct GameVideoClipRow: Decodable, Identifiable, Sendable {
  let id: UUID; let label: String; let inning: Int; let half: String
  let play_id: UUID
  let start_ms: Double; let end_ms: Double; let status: String
  let needs_review: Bool; let withdrawn: Bool; let playback_path: String?
  let player_name: String?
  let thumbnail_path: String?
  let revision: Int
  let manual_start_ms: Double?
  let manual_end_ms: Double?
}

struct GameVideoView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.openURL) private var openURL
  let gameID: UUID
  var focusedPlayID: UUID? = nil
  @State private var recordings: [GameRecordingRow] = []
  @State private var segments: [GameVideoSegmentRow] = []
  @State private var clips: [GameVideoClipRow] = []
  @State private var selected: UUID?
  @State private var showPlays = true
  @State private var canManage = false
  @State private var permitted = false
  @State private var message: String?
  @State private var player: AVPlayer?
  @State private var showRecorder = false
  @State private var filter = ""
  @State private var editing: GameVideoClipRow?
  @State private var trimStart = ""
  @State private var trimEnd = ""
  @State private var playingSegment: UUID?
  @State private var openedFocusedPlay = false
  @State private var confirmDeletion = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Game Video").font(.title.bold())
        Text("Private team recording and official-play clips").foregroundStyle(.secondary)
        if let message { Text(message).font(.callout) }
        if permitted {
          #if os(iOS)
          if canManage { Button("Record this game", systemImage: "video.badge.plus") { showRecorder = true }.buttonStyle(.borderedProminent) }
          #endif
          if recordings.isEmpty { Text("No recording yet.") }
          Picker("Recording", selection: $selected) {
            ForEach(recordings) { r in Text("\(r.started_at.formatted()) · \(r.status)").tag(Optional(r.id)) }
          }
          Picker("View", selection: $showPlays) { Text("Full Recording").tag(false); Text("Plays").tag(true) }.pickerStyle(.segmented)
          if let player { VideoPlayer(player: player).frame(minHeight: 220).clipShape(RoundedRectangle(cornerRadius: 12)) }
          if showPlays {
            TextField("Search player, result or inning", text: $filter).textFieldStyle(.roundedBorder)
            ForEach(clips.filter { !$0.withdrawn && (filter.isEmpty || "\($0.player_name ?? "") \($0.label) \($0.inning)".localizedCaseInsensitiveContains(filter)) }) { clip in
              VStack(alignment: .leading, spacing: 6) {
                Button { Task { await play(clip.playback_path) } } label: {
                  VStack(alignment: .leading) {
                    GameVideoThumbnail(path: clip.thumbnail_path)
                    Label(clip.label.capitalized, systemImage: "play.rectangle.fill").font(.headline)
                  }
                }.disabled(clip.playback_path == nil)
                Text("\(clip.player_name ?? "Player") · \(clip.half.capitalized) \(clip.inning) · \(time(clip.manual_start_ms ?? clip.start_ms))–\(time(clip.manual_end_ms ?? clip.end_ms))").font(.caption)
                Text(clip.status.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary)
                if clip.needs_review { Text("Timing needs review").font(.caption).foregroundStyle(.orange) }
                Button("View in full recording") {
                  showPlays = false
                  if let segment = segments.first(where: { $0.start_ms <= clip.start_ms && $0.end_ms > clip.start_ms }) {
                    Task { await play(segment.playback_path, offset: (clip.start_ms - segment.start_ms) / 1000, segmentID: segment.id) }
                  }
                }.font(.caption)
                if canManage {
                  Button("Adjust clip") {
                    editing = clip
                    trimStart = String((clip.manual_start_ms ?? clip.start_ms) / 1000)
                    trimEnd = String((clip.manual_end_ms ?? clip.end_ms) / 1000)
                  }.font(.caption)
                }
              }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
          } else {
            Text("Original footage is preserved. Gaps in recording remain visible.").font(.caption)
            Text(String(format: "Cloud originals: %.2f GB", Double(segments.reduce(Int64(0)) { $0 + $1.bytes }) / 1_000_000_000)).font(.caption)
            if let assembled = recordings.first(where: { $0.id == selected })?.assembled_path {
              Button("Watch full recording") { Task { await play(assembled) } }
              Button("Download full recording") { Task {
                guard let service = appState.supabase else { return }
                let org = appState.activeOrgId
                do {
                  let url = try await service.client.storage.from("game-video").createSignedURL(path: assembled, expiresIn: 600, download: "HomePlate-Game.mp4")
                  if org == appState.activeOrgId { openURL(url) }
                } catch { message = "Could not prepare the download. Try again." }
              } }
            }
            ForEach(segments) { segment in
              Button("\(time(segment.start_ms))–\(time(segment.end_ms)) · \(segment.playback_path == nil ? "Awaiting footage" : "Watch")") {
                Task { await play(segment.playback_path, segmentID: segment.id) }
              }.disabled(segment.playback_path == nil)
              Button("Download original \(time(segment.start_ms))–\(time(segment.end_ms))") { Task { await download(segment.storage_path, name: "HomePlate-Segment.mov") } }.font(.caption)
            }
            if canManage, let current = recordings.first(where: { $0.id == selected }), current.status != "recording" {
              Button("Delete cloud recording and clips", role: .destructive) { confirmDeletion = true }
            }
          }
          Button("Refresh") { Task { await load() } }
        }
      }.padding()
    }
    .navigationTitle("Game Video")
    .task(id: "\(appState.activeOrgId?.uuidString ?? ""):\(gameID):\(selected?.uuidString ?? "")") {
      await load()
      while !Task.isCancelled { try? await Task.sleep(for: .seconds(15)); if !Task.isCancelled { await load() } }
    }
    .onDisappear { player?.pause(); player = nil }
    .onChange(of: selected) { _, _ in player?.pause(); player = nil; playingSegment = nil }
    .onChange(of: appState.activeOrgId) { _, _ in player?.pause(); player = nil; permitted = false; recordings = []; clips = []; segments = []; selected = nil; editing = nil }
    .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notification in
      guard let item = notification.object as? AVPlayerItem, item === player?.currentItem,
        let id = playingSegment, let index = segments.firstIndex(where: { $0.id == id }), index + 1 < segments.count else { return }
      let next = segments[index + 1]
      guard next.start_ms - segments[index].end_ms <= 100 else { message = "Recording gap before \(time(next.start_ms)). Select the next segment to continue."; return }
      Task { await play(next.playback_path, segmentID: next.id) }
    }
    .sheet(item: $editing) { clip in
      VStack(spacing: 16) {
        Text("Adjust clip boundaries").font(.headline)
        Text("Seconds from recording start. Original footage stays unchanged.")
        TextField("Start seconds", text: $trimStart).textFieldStyle(.roundedBorder)
        TextField("End seconds", text: $trimEnd).textFieldStyle(.roundedBorder)
        if let message { Text(message).font(.caption) }
        Button("Save trim") { Task { await saveTrim(clip) } }.buttonStyle(.borderedProminent)
        Button("Cancel") { editing = nil }
      }.padding()
    }
    .alert("Permanently delete this recording?", isPresented: $confirmDeletion) {
      Button("Delete cloud recording", role: .destructive) { Task {
        guard let selected, let service = appState.supabase else { return }
        struct Params: Encodable { let p_id: UUID; let p_confirmation: UUID }
        do {
          try await service.client.rpc("sd_request_game_video_deletion", params: Params(p_id: selected, p_confirmation: selected)).execute()
          player?.pause(); player = nil; self.selected = nil; await load()
          message = "Cloud deletion requested. The recording is hidden from viewers."
        } catch { message = "Deletion could not be requested. Try again." }
      } }
      Button("Cancel", role: .cancel) {}
    } message: { Text("This removes the cloud originals and clips and cannot be undone. Local files on the camera device are not deleted.") }
    #if os(iOS)
    .fullScreenCover(isPresented: $showRecorder) {
      if let service = appState.supabase, let accountID = appState.myProfile?.id { GameCameraScreen(gameID: gameID, accountID: accountID, service: service) }
    }
    #endif
  }
  private func time(_ ms: Double) -> String { String(format: "%d:%02d", Int(ms / 60000), Int(ms / 1000) % 60) }
  @MainActor private func load() async {
    guard let service = appState.supabase else { return }
    let org = appState.activeOrgId
    do {
      struct Params: Encodable { let p_game: UUID }
      let allowed: Bool = try await service.client.rpc("sd_can_view_game_video", params: Params(p_game: gameID)).execute().value
      guard org == appState.activeOrgId, !Task.isCancelled else { return }
      permitted = allowed
      guard allowed else { recordings = []; clips = []; segments = []; player = nil; message = "Game recording is not enabled for this team, or you do not have access."; return }
      canManage = try await service.client.rpc("sd_can_manage_game_video", params: Params(p_game: gameID)).execute().value
      let fetched: [GameRecordingRow] = try await service.client.from("sd_game_recordings").select().eq("game_id", value: gameID).order("started_at").execute().value
      guard org == appState.activeOrgId, !Task.isCancelled else { return }
      recordings = fetched
      if selected == nil {
        if let focusedPlayID, !fetched.isEmpty {
          struct Match: Decodable { let recording_id: UUID }
          let matches: [Match] = (try? await service.client.from("sd_game_video_clips").select("recording_id").eq("play_id", value: focusedPlayID)
            .eq("status", value: "ready").in("recording_id", values: fetched.map(\.id)).limit(1).execute().value) ?? []
          if !Task.isCancelled { selected = matches.first?.recording_id ?? fetched.last?.id }
        } else { selected = fetched.last?.id }
      }
      if let selected {
        let fetchedClips: [GameVideoClipRow] = try await allRows(service, table: "sd_game_video_clips", recording: selected)
        let fetchedSegments: [GameVideoSegmentRow] = try await allRows(service, table: "sd_game_video_segments", recording: selected)
        guard org == appState.activeOrgId, !Task.isCancelled else { return }
        clips = fetchedClips; segments = fetchedSegments
        if !openedFocusedPlay, let target = fetchedClips.first(where: { $0.play_id == focusedPlayID }), let path = target.playback_path {
          openedFocusedPlay = true; await play(path)
        }
      }
      message = nil
    } catch { message = "Game video is not available yet. Your scoring is unaffected." }
  }
  private func allRows<Row: Decodable & Sendable>(_ service: SupabaseService, table: String, recording: UUID) async throws -> [Row] {
    var result: [Row] = []
    var offset = 0
    while true {
      try Task.checkCancellation()
      let rows: [Row] = try await service.client.from(table).select().eq("recording_id", value: recording).order("start_ms").order("id").range(from: offset, to: offset + 999).execute().value
      result += rows
      if rows.count < 1000 { return result }
      offset += 1000
    }
  }
  @MainActor private func play(_ path: String?, offset: Double = 0, segmentID: UUID? = nil) async {
    guard let path, let service = appState.supabase else { return }
    let org = appState.activeOrgId
    let recording = selected
    do {
      let url = try await service.client.storage.from("game-video").createSignedURL(path: path, expiresIn: 3600)
      guard org == appState.activeOrgId, recording == selected else { return }
      player?.pause(); player = AVPlayer(url: url); playingSegment = segmentID
      await player?.seek(to: CMTime(seconds: offset, preferredTimescale: 600)); player?.play()
    } catch { message = "Could not open this video. Refresh and try again." }
  }
  @MainActor private func download(_ path: String, name: String) async {
    guard let service = appState.supabase else { return }
    let org = appState.activeOrgId
    do {
      let url = try await service.client.storage.from("game-video").createSignedURL(path: path, expiresIn: 600, download: name)
      if org == appState.activeOrgId { openURL(url) }
    } catch { message = "Original footage is not available for download yet." }
  }
  @MainActor private func saveTrim(_ clip: GameVideoClipRow) async {
    guard let a = Double(trimStart), let b = Double(trimEnd), a.isFinite, b.isFinite, a >= 0, b > a, let service = appState.supabase else {
      message = "Enter valid start and end seconds."; return
    }
    struct Params: Encodable { let p_id: UUID; let p_revision: Int; let p_start: Double; let p_end: Double }
    do {
      try await service.client.rpc("sd_edit_game_video_clip", params: Params(p_id: clip.id, p_revision: clip.revision, p_start: a * 1000, p_end: b * 1000)).execute()
      editing = nil; message = "Trim saved; the clip will be reprocessed."; await load()
    } catch { message = "Trim could not be saved. Refresh if another staff member edited it." }
  }
}

private struct GameVideoThumbnail: View {
  @EnvironmentObject private var appState: AppState
  let path: String?
  @State private var url: URL?
  var body: some View {
    AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "video").frame(height: 100) }
      .frame(maxWidth: .infinity, maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 10))
      .task(id: "\(appState.activeOrgId?.uuidString ?? ""):\(path ?? "")") {
        url = nil
        guard let path, let service = appState.supabase else { return }
        let signed = try? await service.client.storage.from("game-video").createSignedURL(path: path, expiresIn: 1800)
        if !Task.isCancelled { url = signed }
      }
  }
}

#if os(iOS)
import UIKit
import Combine

private struct LocalGameSegment: Codable, Identifiable, Sendable {
  var id: UUID; var ordinal: Int; var startMS: Double; var endMS: Double; var file: String; var bytes: Int64
  var uploadURL: URL?; var uploaded = false
}
private struct LocalGameRecording: Codable, Sendable {
  var id: UUID; var gameID: UUID; var accountID: UUID; var deviceID: UUID
  var startedAt: Date; var uncertaintyMS: Double?; var endedAt: Date?; var registered = false
  var interrupted = false; var segments: [LocalGameSegment] = []
  var closedRemotely: Bool? = nil
  var mediaOffsetMS: Double? = nil
  var alignmentSynced: Bool? = nil
}
private struct PendingGameFragment: Codable, Sendable {
  let recordingID: UUID
  let file: String
  let startMS: Double
}

/// All capture state is confined to queue. Files are closed before delivery.
private final class GameSegmentCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
  // The writer is handed to its completion callback only after inputs are
  // finished; no capture-queue mutations occur after that handoff.
  private final class FinishingWriter: @unchecked Sendable {
    let value: AVAssetWriter
    init(_ value: AVAssetWriter) { self.value = value }
  }
  let session = AVCaptureSession()
  let queue = DispatchQueue(label: "homeplate.game-camera")
  var onSegment: (@Sendable (URL, Double, Double) -> Void)?
  var onError: (@Sendable (String) -> Void)?
  var onStopped: (@Sendable () -> Void)?
  var onFirstFrame: (@Sendable (Double) -> Void)?
  private let closing = DispatchGroup()
  private var writer: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var audioInput: AVAssetWriterInput?
  private var folder: URL?
  private var recording = false
  private var origin: Double = 0
  private var segmentStart: CMTime = .zero
  private var lastVideoEnd: CMTime = .zero
  private var file: URL?
  private var hasStarted = false
  private var recordingID: UUID?

  func start(folder: URL, origin: Double, recordingID: UUID) {
    queue.async {
      do {
        self.folder = folder; self.origin = origin; self.recordingID = recordingID; self.hasStarted = false
        self.session.beginConfiguration()
        for input in self.session.inputs { self.session.removeInput(input) }
        for output in self.session.outputs { self.session.removeOutput(output) }
        self.session.sessionPreset = .hd1920x1080
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CocoaError(.featureUnsupported) }
        let cameraInput = try AVCaptureDeviceInput(device: camera)
        guard self.session.canAddInput(cameraInput) else { throw CocoaError(.featureUnsupported) }
        self.session.addInput(cameraInput)
        if let microphone = AVCaptureDevice.default(for: .audio) {
          let micInput = try AVCaptureDeviceInput(device: microphone)
          if self.session.canAddInput(micInput) { self.session.addInput(micInput) }
        }
        let video = AVCaptureVideoDataOutput(); video.alwaysDiscardsLateVideoFrames = false
        video.setSampleBufferDelegate(self, queue: self.queue)
        let audio = AVCaptureAudioDataOutput(); audio.setSampleBufferDelegate(self, queue: self.queue)
        guard self.session.canAddOutput(video), self.session.canAddOutput(audio) else { throw CocoaError(.featureUnsupported) }
        self.session.addOutput(video); self.session.addOutput(audio)
        self.session.commitConfiguration()
        self.recording = true; self.session.startRunning()
      } catch { self.onError?("Camera could not start. Check camera/microphone access.") }
    }
  }
  func stop() { queue.async {
    self.recording = false; self.finish(); self.session.stopRunning()
    self.closing.notify(queue: self.queue) { self.onStopped?() }
  } }
  func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard recording, CMSampleBufferDataIsReady(sample) else { return }
    let isVideo = output is AVCaptureVideoDataOutput
    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
    do {
      if isVideo && (writer == nil || CMTimeGetSeconds(pts - segmentStart) >= 30) {
        if writer != nil { lastVideoEnd = pts }
        finish()
        guard let folder else { return }
        let free = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard free > 250_000_000 else { recording = false; session.stopRunning(); onError?("Recording stopped: storage is nearly full. Closed segments are preserved."); return }
        let url = folder.appendingPathComponent(UUID().uuidString + ".mov")
        let next = try AVAssetWriter(outputURL: url, fileType: .mov)
        next.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
        guard let recordingID else { throw CocoaError(.fileWriteUnknown) }
        let pending = PendingGameFragment(recordingID: recordingID, file: url.lastPathComponent, startMS: max(0, pts.seconds - origin) * 1000)
        try JSONEncoder().encode(pending).write(to: folder.appendingPathComponent("pending-\(url.deletingPathExtension().lastPathComponent).json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        guard let description = CMSampleBufferGetFormatDescription(sample) else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
          AVVideoWidthKey: Int(dimensions.width), AVVideoHeightKey: Int(dimensions.height),
          AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000]])
        v.expectsMediaDataInRealTime = true
        let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000])
        a.expectsMediaDataInRealTime = true
        next.add(v); next.add(a)
        guard next.startWriting() else { throw next.error ?? CocoaError(.fileWriteUnknown) }
        next.startSession(atSourceTime: pts)
        writer = next; videoInput = v; audioInput = a; file = url; segmentStart = pts; lastVideoEnd = pts
        if !hasStarted { hasStarted = true; onFirstFrame?(max(0, pts.seconds - origin) * 1000) }
      }
      guard writer != nil, pts >= segmentStart else { return }
      let input = isVideo ? videoInput : audioInput
      guard input?.isReadyForMoreMediaData == true else { onError?("Camera is overloaded; footage may contain a gap. Stop and check device temperature."); return }
      guard input?.append(sample) == true else { throw writer?.error ?? CocoaError(.fileWriteUnknown) }
      if isVideo {
        let duration = CMSampleBufferGetDuration(sample)
        lastVideoEnd = pts + (duration.isValid && duration.seconds > 0 ? duration : CMTime(value: 1, timescale: 30))
      }
    } catch { recording = false; finish(); session.stopRunning(); onError?("Recording interrupted. Completed segments are preserved.") }
  }
  private func finish() {
    guard let writer, let file else { return }
    let start = max(0, segmentStart.seconds - origin) * 1000
    let end = max(start, (lastVideoEnd.seconds - origin) * 1000)
    videoInput?.markAsFinished(); audioInput?.markAsFinished()
    let callback = onSegment; let failure = onError
    closing.enter()
    let group = closing
    let finished = FinishingWriter(writer)
    writer.finishWriting {
      if finished.value.status == .completed { callback?(file, start, end) } else { failure?("A segment could not be finalized. Earlier segments remain saved.") }
      group.leave()
    }
    self.writer = nil; self.file = nil; videoInput = nil; audioInput = nil
  }
}

@MainActor private final class GameCameraModel: ObservableObject {
  private static var activeModels: [String: GameCameraModel] = [:]
  static func shared(gameID: UUID, accountID: UUID) -> GameCameraModel {
    let key = "\(accountID):\(gameID)"
    if let existing = activeModels[key] { return existing }
    let model = GameCameraModel(); model.cacheKey = key; activeModels[key] = model; return model
  }
  @Published var status = "Ready to record. Keep this screen open."
  @Published var recording = false
  @Published var pending = 0
  @Published var availableGB = 0.0
  @Published var recoveryWarning: String?
  let camera = GameSegmentCamera()
  private var manifest: LocalGameRecording?
  private var directory: URL?
  private var service: SupabaseService?
  private var syncing = false
  private var finishing = false
  private var startedMonotonic: Double?
  private var cacheKey = ""
  private var uploadTask: Task<Void, Never>?
  private var prepared = false
  var elapsedSeconds: Int {
    if recording, let startedMonotonic { return max(0, Int(ProcessInfo.processInfo.systemUptime - startedMonotonic - (manifest?.mediaOffsetMS ?? 0) / 1000)) }
    return Int((manifest?.segments.map(\.endMS).max() ?? 0) / 1000)
  }

  func prepare(gameID: UUID, service: SupabaseService) async {
    self.service = service
    if prepared { startUploadLoop(); return }
    do {
      let account = try await service.client.auth.session.user.id
      let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("GameRecordings/\(account)/\(gameID)", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      directory = folder
      availableGB = Double(try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000
      let file = folder.appendingPathComponent("manifest.json")
      if FileManager.default.fileExists(atPath: file.path) {
        manifest = try JSONDecoder().decode(LocalGameRecording.self, from: Data(contentsOf: file))
        if manifest?.endedAt == nil { manifest?.interrupted = true; manifest?.endedAt = Date(); try save() }
        await recoverFragments()
        status = "Recovered recording. Pending segments will resume uploading; raw files remain on this device."
      }
      camera.onSegment = { [weak self] url, start, end in DispatchQueue.main.async { self?.closedSegment(url, start: start, end: end) } }
      camera.onFirstFrame = { [weak self] offset in DispatchQueue.main.async {
        guard let self, var local = self.manifest, local.mediaOffsetMS == nil else { return }
        local.mediaOffsetMS = offset
        local.startedAt = local.startedAt.addingTimeInterval(offset / 1000)
        self.manifest = local
        do { try self.save() } catch { self.status = "Could not save camera timing. Recording stopped."; self.stop(interrupted: true) }
      } }
      camera.onError = { [weak self] text in DispatchQueue.main.async { self?.status = text; self?.stop(interrupted: true) } }
      camera.onStopped = { [weak self] in DispatchQueue.main.async { self?.finishing = false; Task { await self?.sync() } } }
      prepared = true; startUploadLoop()
      await sync()
    } catch { status = "Could not open protected local recording storage." }
  }
  func start(gameID: UUID) async {
    guard let service, let directory, !recording else { return }
    // Preserve an existing manifest until it has been uploaded and closed remotely.
    if let old = manifest {
      guard !finishing, old.closedRemotely == true, old.segments.allSatisfy(\.uploaded) else {
        status = "Finish uploading this recording before starting another session."; return
      }
      do {
        try JSONEncoder().encode(old).write(to: directory.appendingPathComponent("\(old.id).json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        manifest = nil
      } catch { status = "Could not preserve previous recording manifest."; return }
    }
    guard await AVCaptureDevice.requestAccess(for: .video), await AVCaptureDevice.requestAccess(for: .audio) else { status = "Camera and microphone permission are required."; return }
    do {
      let anchor = try await service.gameVideoClockAnchor()
      let origin = CMClockGetTime(CMClockGetHostTimeClock()).seconds
      startedMonotonic = ProcessInfo.processInfo.systemUptime
      let stamp = try anchor.timestamp(at: ProcessInfo.processInfo.systemUptime)
      let account = try await service.client.auth.session.user.id
      let local = LocalGameRecording(id: UUID(), gameID: gameID, accountID: account, deviceID: SDGameDeviceIdentity.current,
        startedAt: stamp.enteredAt, uncertaintyMS: stamp.uncertaintyMilliseconds)
      manifest = local; try save()
      struct Params: Encodable { let p_id: UUID; let p_game: UUID; let p_device: UUID; let p_started: Date; let p_uncertainty: Double? }
      try await service.client.rpc("sd_start_game_recording", params: Params(p_id: local.id, p_game: gameID, p_device: local.deviceID,
        p_started: local.startedAt, p_uncertainty: local.uncertaintyMS)).execute()
      manifest?.registered = true; try save()
      recording = true; UIApplication.shared.isIdleTimerDisabled = true
      startUploadLoop()
      status = "Recording locally · uploads run independently"
      camera.start(folder: directory, origin: origin, recordingID: local.id)
    } catch {
      if manifest != nil { manifest?.endedAt = Date(); manifest?.interrupted = true; try? save() }
      status = "Could not start. Connect to recover preparation and confirm another camera is not already recording this game."
    }
  }
  func stop(interrupted: Bool = false) {
    guard recording else { return }
    recording = false; finishing = true; camera.stop(); UIApplication.shared.isIdleTimerDisabled = false
    manifest?.endedAt = Date(); manifest?.interrupted = interrupted
    do { try save() } catch { status = "Recording stopped; manifest save failed. Keep this app open." }
    if !interrupted { status = "Stopped. Raw footage is retained; pending uploads will continue." }
  }
  private func closedSegment(_ url: URL, start: Double, end: Double) {
    do {
      guard var local = manifest, end > start else { return }
      if local.mediaOffsetMS == nil {
        local.mediaOffsetMS = start
        local.startedAt = local.startedAt.addingTimeInterval(start / 1000)
      }
      let offset = local.mediaOffsetMS ?? 0
      let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
      local.segments.append(.init(id: UUID(), ordinal: local.segments.count, startMS: start - offset, endMS: end - offset, file: url.lastPathComponent, bytes: bytes))
      manifest = local; try save()
      Task { await sync() }
    } catch { status = "Could not journal closed segment. Recording stopped; raw file retained."; stop(interrupted: true) }
  }
  private func recoverFragments() async {
    guard let directory, var local = manifest else { return }
    do {
      let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      var fragments: [PendingGameFragment] = []
      for file in files where file.lastPathComponent.hasPrefix("pending-") && file.pathExtension == "json" {
        if let pending = try? JSONDecoder().decode(PendingGameFragment.self, from: Data(contentsOf: file)),
          pending.recordingID == local.id, URL(fileURLWithPath: pending.file).lastPathComponent == pending.file,
          !local.segments.contains(where: { $0.file == pending.file }) { fragments.append(pending) }
      }
      for pending in fragments.sorted(by: { $0.startMS < $1.startMS }) {
        let source = directory.appendingPathComponent(pending.file)
        guard let duration = try? await AVURLAsset(url: source).load(.duration), duration.seconds.isFinite, duration.seconds > 0 else {
          recoveryWarning = "An unfinished fragment could not be recovered. Earlier segments and original files are retained."; continue
        }
        if local.mediaOffsetMS == nil { local.mediaOffsetMS = pending.startMS; local.startedAt = local.startedAt.addingTimeInterval(pending.startMS / 1000) }
        let start = pending.startMS - (local.mediaOffsetMS ?? 0)
        let bytes = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard start >= 0, bytes > 0 else { continue }
        local.segments.append(.init(id: UUID(), ordinal: local.segments.count, startMS: start, endMS: start + duration.seconds * 1000, file: pending.file, bytes: bytes))
      }
      manifest = local; try save()
    } catch { recoveryWarning = "Some interrupted footage needs recovery. All original files have been retained." }
  }
  private func save() throws {
    guard let directory, let manifest else { return }
    try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
    availableGB = Double(try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000
    pending = manifest.segments.filter { !$0.uploaded }.count
  }
  private func startUploadLoop() {
    if !cacheKey.isEmpty { Self.activeModels[cacheKey] = self }
    guard uploadTask == nil else { return }
    // Retain the coordinator while queued work exists, not just while the
    // camera screen is visible. iOS suspension still pauses foreground work.
    uploadTask = Task { [self] in
      while !Task.isCancelled {
        await sync()
        if !recording && !finishing && (manifest == nil || (manifest?.closedRemotely == true && pending == 0)) { break }
        if let service, let account = try? await service.client.auth.session.user.id,
          let expected = manifest?.accountID, account != expected { break }
        try? await Task.sleep(for: .seconds(10))
      }
      uploadTask = nil
      if !recording && !finishing && pending == 0 { Self.activeModels.removeValue(forKey: cacheKey) }
    }
  }
  func sync() async {
    guard !syncing, let service, let directory, let local = manifest else { return }
    syncing = true; defer { syncing = false }
    do {
      guard try await service.client.auth.session.user.id == local.accountID else { return }
      if !local.registered {
        struct Start: Encodable { let p_id: UUID; let p_game: UUID; let p_device: UUID; let p_started: Date; let p_uncertainty: Double? }
        try await service.client.rpc("sd_start_game_recording", params: Start(p_id: local.id, p_game: local.gameID, p_device: local.deviceID, p_started: local.startedAt, p_uncertainty: local.uncertaintyMS)).execute()
        manifest?.registered = true; try save()
      }
      if local.mediaOffsetMS != nil, local.alignmentSynced != true {
        struct Align: Encodable { let p_id: UUID; let p_started: Date }
        try await service.client.rpc("sd_align_game_recording", params: Align(p_id: local.id, p_started: local.startedAt)).execute()
        manifest?.alignmentSynced = true; try save()
      }
      for segment in local.segments where !segment.uploaded {
        struct Params: Encodable { let p_id: UUID; let p_recording: UUID; let p_ordinal: Int; let p_start: Double; let p_end: Double; let p_bytes: Int64 }
        struct Row: Decodable { let storage_path: String }
        let row: Row = try await service.client.rpc("sd_register_game_video_segment", params: Params(p_id: segment.id, p_recording: local.id,
          p_ordinal: segment.ordinal, p_start: segment.startMS, p_end: segment.endMS, p_bytes: segment.bytes)).execute().value
        if let existing = try? await service.client.storage.from("game-video").info(path: row.storage_path) {
          guard existing.size == Int(segment.bytes) else { throw CocoaError(.fileReadCorruptFile) }
        } else {
          let token = try await service.client.auth.session.accessToken
          try await upload(segment: segment, file: directory.appendingPathComponent(segment.file), path: row.storage_path, token: token)
        }
        if let index = manifest?.segments.firstIndex(where: { $0.id == segment.id }) { manifest?.segments[index].uploaded = true; try save() }
      }
      if let ended = manifest?.endedAt, !finishing {
        struct Stop: Encodable { let p_id: UUID; let p_ended: Date; let p_interrupted: Bool }
        try await service.client.rpc("sd_stop_game_recording", params: Stop(p_id: local.id, p_ended: ended, p_interrupted: manifest?.interrupted ?? true)).execute()
        manifest?.closedRemotely = true; try save()
      }
    } catch { if !recording { status = "Saved on this device. Uploads will retry when connected and authorized." } }
  }
  private func upload(segment: LocalGameSegment, file: URL, path: String, token: String) async throws {
    let endpoint = URL(string: "https://kbulbvngysflfhaqpvtv.storage.supabase.co/storage/v1/upload/resumable")!
    func request(_ url: URL, method: String) -> URLRequest {
      var r = URLRequest(url: url); r.httpMethod = method; r.timeoutInterval = 45
      r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); r.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
      return r
    }
    var location = segment.uploadURL
    if location == nil {
      var create = request(endpoint, method: "POST")
      create.setValue(String(segment.bytes), forHTTPHeaderField: "Upload-Length")
      create.setValue(["bucketName": "game-video", "objectName": path, "contentType": "video/quicktime"].map { "\($0.key) \(Data($0.value.utf8).base64EncodedString())" }.joined(separator: ","), forHTTPHeaderField: "Upload-Metadata")
      let (_, response) = try await URLSession.shared.data(for: create)
      guard let response = response as? HTTPURLResponse, response.statusCode == 201,
        let header = response.value(forHTTPHeaderField: "Location"), let resolved = URL(string: header, relativeTo: endpoint)?.absoluteURL,
        resolved.host == endpoint.host, resolved.scheme == "https" else { throw URLError(.badServerResponse) }
      location = resolved
      if let index = manifest?.segments.firstIndex(where: { $0.id == segment.id }) { manifest?.segments[index].uploadURL = location; try save() }
    }
    guard let location, location.host == endpoint.host, location.scheme == "https" else { throw URLError(.badURL) }
    let (_, head) = try await URLSession.shared.data(for: request(location, method: "HEAD"))
    if let response = head as? HTTPURLResponse, [404, 410].contains(response.statusCode) {
      if let index = manifest?.segments.firstIndex(where: { $0.id == segment.id }) { manifest?.segments[index].uploadURL = nil; try save() }
      throw URLError(.resourceUnavailable)
    }
    guard let head = head as? HTTPURLResponse, head.statusCode == 200 || head.statusCode == 204,
      let value = head.value(forHTTPHeaderField: "Upload-Offset"), var offset = Int64(value), offset >= 0, offset <= segment.bytes else { throw URLError(.badServerResponse) }
    let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
    while offset < segment.bytes {
      try handle.seek(toOffset: UInt64(offset))
      guard let chunk = try handle.read(upToCount: 6 * 1024 * 1024), !chunk.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
      var patch = request(location, method: "PATCH"); patch.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
      patch.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
      let (_, response) = try await URLSession.shared.upload(for: patch, from: chunk)
      guard let response = response as? HTTPURLResponse, response.statusCode == 204,
        let next = response.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int64.init), next == offset + Int64(chunk.count) else { throw URLError(.badServerResponse) }
      offset = next
    }
  }
}

private struct GameCameraPreview: UIViewRepresentable {
  let camera: GameSegmentCamera
  final class Preview: UIView { override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self } }
  func makeUIView(context: Context) -> Preview {
    let view = Preview(); let layer = view.layer as! AVCaptureVideoPreviewLayer
    layer.session = camera.session; layer.videoGravity = .resizeAspect
    return view
  }
  func updateUIView(_ uiView: Preview, context: Context) {}
}
private struct GameCameraScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  let gameID: UUID; let service: SupabaseService
  @StateObject private var model: GameCameraModel
  init(gameID: UUID, accountID: UUID, service: SupabaseService) {
    self.gameID = gameID; self.service = service
    _model = StateObject(wrappedValue: GameCameraModel.shared(gameID: gameID, accountID: accountID))
  }
  var body: some View {
    VStack(spacing: 16) {
      Text("Game Camera").font(.title.bold())
      GameCameraPreview(camera: model.camera).background(.black)
      Text(model.status).font(.callout)
      if let warning = model.recoveryWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        Text(String(format: "%02d:%02d:%02d", model.elapsedSeconds / 3600, (model.elapsedSeconds / 60) % 60, model.elapsedSeconds % 60)).font(.title.monospacedDigit())
      }
      Text(String(format: "%.1f GB free · 1080p uses approximately 5.4 GB/hour", model.availableGB)).font(.caption)
      Text("\(model.pending) segments waiting to upload").font(.caption)
      if model.recording { Button("Stop recording", role: .destructive) { model.stop() } }
      else { Button("Start recording") { Task { await model.start(gameID: gameID) } } }
      Button("Close") { model.stop(interrupted: model.recording); dismiss() }
    }.padding()
    .task { await model.prepare(gameID: gameID, service: service) }
    .onChange(of: scenePhase) { _, phase in if phase != .active { model.stop(interrupted: true) } }
    .onDisappear { model.stop(interrupted: true) }
    .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: model.camera.session)) { _ in model.stop(interrupted: true) }
    .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: model.camera.session)) { _ in model.stop(interrupted: true) }
  }
}
#endif

import SwiftUI
import AVKit
import UniformTypeIdentifiers
import Supabase
import PhotosUI

enum PersonalVideoAccessResult: Equatable {
  case allowed, denied, unavailable

  @MainActor static func resolve(_ check: () async throws -> Bool) async -> Self {
    do { return try await check() ? .allowed : .denied }
    catch { return .unavailable }
  }
}

private struct PersonalVideoUploadView: View {
  @EnvironmentObject private var appState: AppState
  let playerId: UUID
  let onUploaded: () -> Void
  @State private var allowed = false
  @State private var permissionLoading = false
  @State private var permissionError = false
  @Environment(\.scenePhase) private var scenePhase
  @State private var picker = false
  @State private var photo: PhotosPickerItem?
  @State private var busy = false
  @State private var date = Date()
  @State private var category = "other"
  @State private var message: String?
  private struct Pending {
    let id = UUID()
    let org: UUID; let actor: UUID; let player: UUID
    let data: Data; let title: String; let original: String; let date: String; let category: String
  }
  private struct Record: Codable {
    let id: UUID; let org_id: UUID; let player_id: UUID; let created_by: UUID
    let title: String; let original_filename: String; let recorded_date: String; let category: String; let storage_path: String
  }
  @State private var pending: Pending?
  @State private var prepared: Pending?
  @State private var filename = ""
  private var context: String { "\(appState.activeOrgId?.uuidString ?? ""):\(appState.myProfile?.id.uuidString ?? ""):\(playerId)" }
  var body: some View {
    VStack(spacing: 0) {
      if permissionLoading { ProgressView("Checking upload access…") }
      if permissionError {
        Text("Upload access could not be checked. Your permissions have not changed.").font(.caption)
        Button("Retry upload access") { Task { await checkPermission() } }
      }
      if allowed {
        DisclosureGroup("Upload a video") {
          VStack(alignment: .leading, spacing: 16) {
          DatePicker("Video date", selection: $date, displayedComponents: .date).disabled(busy || pending != nil || prepared != nil)
          Picker("Category", selection: $category) {
            ForEach(["workout", "testing", "hitting", "pitching", "other"], id: \.self) { Text($0.capitalized).tag($0) }
          }.disabled(busy || pending != nil || prepared != nil)
          if let pending { Text(pending.title).font(.caption) }
          if busy { ProgressView("Preparing or uploading video…") }
          else if pending != nil { DHDButton("Retry upload", systemImage: "arrow.clockwise", expands: true) { Task { await upload() } } }
          else if prepared != nil {
            Divider().overlay(HP.Color.input)
            HStack(spacing: 12) {
              Image(systemName: "video.badge.checkmark")
                .font(.title2).foregroundStyle(HP.Color.accent)
              VStack(alignment: .leading, spacing: 4) {
                Text("Make it easy to find").font(.headline)
                Text("Give this video a clear name for your library.")
                  .font(.subheadline).foregroundStyle(.secondary)
              }
            }
            HPFormField(label: "Video name", text: $filename,
                        placeholder: "e.g. Bullpen • Fastball mechanics",
                        helper: "The .mp4 extension is added automatically.")
            DHDButton("Confirm name and upload", systemImage: "arrow.up.circle.fill", expands: true) {
              Task { await confirmPreparedVideo() }
            }
          }
          else {
            PhotosPicker(selection: $photo, matching: .videos) { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
            Button("Choose from Files", systemImage: "folder") { picker = true }
          }
          if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
          }.padding(.top, 16).frame(maxWidth: .infinity, alignment: .leading)
        }.padding().background(HP.Color.surface).clipShape(RoundedRectangle(cornerRadius: 12))
      }
    }
    .task(id: context) {
      allowed = false; pending = nil; prepared = nil; message = nil
      await checkPermission()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active && permissionError { Task { await checkPermission() } }
    }
    .fileImporter(isPresented: $picker, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
      if case .success(let urls) = result, let url = urls.first { Task { await prepare(url) } }
      else if case .failure = result { message = "The video could not be selected. Try again." }
    }
    .onChange(of: photo) { _, item in
      guard let item else { return }
      Task {
        guard !busy else { return }
        let captured = context
        busy = true
        do {
          guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
          guard data.count <= 262_144_000 else { throw CocoaError(.fileReadTooLarge) }
          let ext = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) })?.preferredFilenameExtension ?? "mov"
          let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          defer { try? FileManager.default.removeItem(at: directory) }
          let url = directory.appendingPathComponent("Video.\(ext)")
          try data.write(to: url, options: .atomic)
          busy = false
          if context == captured { await prepare(url) }
        } catch {
          if context == captured { message = "This video could not be loaded. Choose a downloaded video of 250 MB or less." }
        }
        busy = false; photo = nil
      }
    }
  }
  private func checkPermission() async {
    guard !permissionLoading else { return }
    let captured = context
    permissionLoading = true; permissionError = false
    defer { permissionLoading = false }
    guard let service = appState.supabase, let org = appState.activeOrgId else { permissionError = true; return }
    let result = await PersonalVideoAccessResult.resolve {
      try await service.client.rpc("sd_can_upload_player_library_video", params: ["p_org_id": org.uuidString, "p_player_id": playerId.uuidString]).execute().value
    }
    if context == captured {
      switch result {
      case .allowed: allowed = true
      case .denied: allowed = false
      case .unavailable: permissionError = true
      }
    }
  }
  private func prepare(_ url: URL) async {
    guard !busy, let org = appState.activeOrgId, let actor = appState.myProfile?.id else { return }
    let captured = context; let selectedDate = date; let selectedCategory = category
    busy = true; defer { busy = false }
    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
    do {
      if (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 262_144_000 { message = "Choose a video of 250 MB or less."; return }
      let data = try await CompatibleVideoTranscoder.mp4Data(from: Data(contentsOf: url), sourceExtension: url.pathExtension)
      guard context == captured else { return }
      guard data.count <= 262_144_000 else { message = "The prepared video exceeds 250 MB."; return }
      let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
      filename = url.deletingPathExtension().lastPathComponent
      prepared = Pending(org: org, actor: actor, player: playerId, data: data, title: filename, original: url.lastPathComponent, date: formatter.string(from: selectedDate), category: selectedCategory)
      message = nil
    } catch { message = "This video could not be prepared: \(error.localizedDescription)" }
  }
  private func confirmPreparedVideo() async {
    guard !busy, let p = prepared, p.org == appState.activeOrgId, p.actor == appState.myProfile?.id, p.player == playerId else { return }
    do {
      let name = try HPUploadNaming.filename(original: "Video.mp4", stem: filename)
      guard name.count <= 160 else { message = "Use a name of at most 156 characters, plus .mp4."; return }
      pending = Pending(org: p.org, actor: p.actor, player: p.player, data: p.data, title: name, original: p.original, date: p.date, category: p.category)
      prepared = nil
      message = nil
      await upload()
    } catch { message = error.localizedDescription }
  }
  private func upload() async {
    guard !busy, let p = pending, p.org == appState.activeOrgId, p.actor == appState.myProfile?.id, p.player == playerId, let service = appState.supabase else { return }
    busy = true; defer { busy = false }
    let captured = context
    let path = "\(p.org)/\(p.player)/\(p.id).mp4".lowercased()
    let record = Record(id: p.id, org_id: p.org, player_id: p.player, created_by: p.actor, title: p.title, original_filename: p.original, recorded_date: p.date, category: p.category, storage_path: path)
    do {
      do { _ = try await service.client.storage.from("player-library-videos").upload(path, data: p.data, options: FileOptions(contentType: "video/mp4", upsert: false, metadata: ["displayName": .string(p.title), "originalFilename": .string(p.original)])) }
      catch let error as StorageError where error.statusCode == "409" { }
      do { try await service.client.from("sd_player_library_videos").insert(record).execute() }
      catch {
        let existing: Record = try await service.client.from("sd_player_library_videos").select().eq("id", value: p.id.uuidString).single().execute().value
        guard existing.org_id == p.org, existing.player_id == p.player, existing.created_by == p.actor, existing.storage_path == path, existing.title == p.title, existing.original_filename == p.original, existing.recorded_date == p.date, existing.category == p.category else { throw error }
      }
      guard captured == context else { return }
      pending = nil; message = "Video added."; onUploaded()
    } catch { if captured == context { message = "Upload interrupted. Retry to finish this same video; its player, date, and category are preserved." } }
  }
}

private struct PersonalVideoThumbnail: View {
  @EnvironmentObject private var appState: AppState
  let bucket: String
  let path: String
  @State private var frame: CGImage?
  var body: some View {
    ZStack {
      Rectangle().fill(.secondary.opacity(0.12))
      if let frame { Image(decorative: frame, scale: 1).resizable().scaledToFill() }
      Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white).shadow(radius: 3)
    }.aspectRatio(16/9, contentMode: .fit).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
    .task(id: "\(appState.activeOrgId?.uuidString ?? ""):\(appState.myProfile?.id.uuidString ?? ""):\(path)") {
      frame = nil
      guard let service = appState.supabase else { return }
      do {
        let url = try await service.client.storage.from(bucket).createSignedURL(path: path, expiresIn: 600)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 640, height: 360)
        let result = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600))
        if !Task.isCancelled { frame = result.image }
      } catch { /* The play button remains available if a preview cannot be generated. */ }
    }
  }
}

struct NativeSharedVideoLibraryView: View {
  @EnvironmentObject private var appState: AppState
  var playerId: UUID? = nil
  private struct Item: Decodable, Identifiable {
    let id: String; let player_id: UUID; let title: String; let recorded_date: String
    let source: String; let bucket: String; let storage_path: String; let context: String?
    let player_name: String?; let duration_seconds: Double?
    let origin_id: UUID?
    let category: String?
  }
  private struct LibraryPlayer: Decodable, Identifiable { let player_id: UUID; let player_name: String; var id: UUID { player_id } }
  @State private var libraryPlayers: [LibraryPlayer] = []
  @State private var selectedPlayer: UUID?
  @State private var filterDates = false
  @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
  @State private var endDate = Date()
  @State private var listLayout = false
  private struct Playback: Identifiable {
    let id = UUID()
    let item: Item
    let player: AVPlayer
  }
  @State private var playback: Playback?
  @State private var rows: [Item] = []
  @State private var source = "all"
  @State private var search = ""
  @State private var loading = false
  @State private var hasMore = true
  @State private var errorText: String?
  @State private var playbackRequest = UUID()
  private var scope: String { "\(appState.activeOrgId?.uuidString ?? ""):\(appState.myProfile?.id.uuidString ?? ""):\(playerId?.uuidString ?? ""):\(source):\(search):\(selectedPlayer?.uuidString ?? ""):\(filterDates):\(startDate):\(endDate)" }
  private func dateKey(_ date: Date) -> String { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let playerId { PersonalVideoUploadView(playerId: playerId) { Task { await load(reset: true) } }.id("\(appState.activeOrgId?.uuidString ?? ""):\(appState.myProfile?.id.uuidString ?? ""):\(playerId)") }
        TextField("Search video titles", text: $search).textFieldStyle(.roundedBorder)
        Picker("Source", selection: $source) {
          Text("All categories").tag("all")
          ForEach(["workout", "testing", "hitting", "pitching", "other"], id: \.self) { Text($0.capitalized).tag($0) }
        }.pickerStyle(.menu)
        if playerId == nil {
          Picker("Player", selection: $selectedPlayer) {
            Text("All players").tag(UUID?.none)
            ForEach(libraryPlayers) { Text($0.player_name).tag(Optional($0.player_id)) }
          }
        }
        Toggle("Filter by date", isOn: $filterDates)
        if filterDates {
          DatePicker("From", selection: $startDate, displayedComponents: .date)
          DatePicker("Through", selection: $endDate, in: startDate..., displayedComponents: .date)
        }
        Toggle("List layout", isOn: $listLayout)
        Text("Authorized program, testing and session videos. Private chat attachments are excluded.").font(.caption).foregroundStyle(.secondary)
        if let errorText {
          Text(errorText).foregroundStyle(.red)
          Button("Retry loading videos") { Task { await load(reset: rows.isEmpty) } }
        }
        LazyVGrid(columns: listLayout ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 250))], spacing: 16) {
          ForEach(rows) { row in
            Button { Task { await play(row) } } label: {
              (listLayout ? AnyLayout(HStackLayout(alignment: .center, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))) {
                PersonalVideoThumbnail(bucket: row.bucket, path: row.storage_path)
                  .frame(maxWidth: listLayout ? 110 : .infinity)
                VStack(alignment: .leading, spacing: 6) {
                Text(row.title).font(.headline).multilineTextAlignment(.leading)
                Text(row.player_name ?? "Player").font(.subheadline)
                Text("\(row.recorded_date) · \((row.category ?? row.source).capitalized)").font(.caption)
                Text(row.context ?? "").font(.caption).foregroundStyle(.secondary)
                if let duration = row.duration_seconds { Text("\(Int(duration)) seconds").font(.caption) }
                }
              }.padding(12).background(HP.Color.surface).clipShape(RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
          }
        }
        if loading { ProgressView("Loading videos…") }
        else if rows.isEmpty && errorText == nil { ContentUnavailableView("No videos yet", systemImage: "video", description: Text("Upload a personal video, or find footage added through workouts, testing, and sessions. If you selected filters, try clearing them.")) }
        if hasMore && !loading && errorText == nil { Button("Load more videos") { Task { await load(reset: false) } } }
      }.padding()
    }
    .navigationTitle("Video Library")
    .task(id: scope) { playback?.player.pause(); playback = nil; libraryPlayers = []; await load(reset: true) }
    .sheet(item: $playback) { selection in
      NavigationStack { VStack {
        VideoPlayer(player: selection.player)
          .onAppear { selection.player.play() }
          .onDisappear { selection.player.pause() }
        if selection.item.origin_id != nil { NavigationLink("Open original day") { PlayerDevelopmentDayView(playerId: selection.item.player_id, playerName: selection.item.player_name ?? "Player", date: selection.item.recorded_date) }.padding() }
      }.navigationTitle(selection.item.title).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { playback = nil } } } }
    }
  }
  private func load(reset: Bool) async {
    guard let service = appState.supabase, let org = appState.activeOrgId else { return }
    let capturedScope = scope
    if reset { rows = []; hasMore = true }
    loading = true; defer { if capturedScope == scope { loading = false } }
    do {
      var query = service.client.from("sd_video_library").select().eq("org_id", value: org.uuidString)
      if let playerId { query = query.eq("player_id", value: playerId.uuidString) }
      else if let selectedPlayer { query = query.eq("player_id", value: selectedPlayer.uuidString) }
      if filterDates { query = query.gte("recorded_date", value: dateKey(startDate)).lte("recorded_date", value: dateKey(endDate)) }
      if source != "all" { query = query.eq("category", value: source) }
      if !search.isEmpty { query = query.ilike("title", pattern: "%\(search.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%") }
      let page: [Item] = try await query.order("recorded_date", ascending: false).order("created_at", ascending: false).order("id").range(from: rows.count, to: rows.count + 23).execute().value
      guard capturedScope == scope else { return }
      rows += page; hasMore = page.count == 24; errorText = nil
      if playerId == nil && reset {
        var fetched: [LibraryPlayer] = []; var offset = 0
        while true {
          let people: [LibraryPlayer] = try await service.client.from("sd_video_library_players").select("player_id,player_name").eq("org_id", value: org.uuidString).order("player_id").range(from: offset, to: offset+999).execute().value
          fetched += people; if people.count < 1000 { break }; offset += 1000
        }
        if capturedScope == scope { libraryPlayers = fetched.sorted { $0.player_name < $1.player_name } }
      }
    } catch { if capturedScope == scope { errorText = SDApplicationErrorClassifier.alertMessage(for: error) } }
  }
  private func play(_ item: Item) async {
    guard let service = appState.supabase else { return }; let capturedScope = scope
    let request = UUID(); playbackRequest = request
    do {
      let url = try await service.client.storage.from(item.bucket).createSignedURL(path: item.storage_path, expiresIn: 600)
      guard capturedScope == scope && request == playbackRequest else { return }
      playback?.player.pause()
      playback = Playback(item: item, player: AVPlayer(url: url))
    } catch { errorText = "Video unavailable. Refresh access and try again." }
  }
}

private struct ProgramFolderRecord: Decodable, Identifiable {
  let id: UUID
  let name: String
  let parent_id: UUID?
  let archived_at: String?
}

private struct LibraryTemplateRecord: Decodable, Identifiable {
  let template: SDProgramTemplate
  let folder_id: UUID?
  let archived_at: String?
  var id: UUID { template.id }
  enum CodingKeys: String, CodingKey { case folder_id, archived_at }
  init(from decoder: Decoder) throws {
    template = try SDProgramTemplate(from: decoder)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    folder_id = try values.decodeIfPresent(UUID.self, forKey: .folder_id)
    archived_at = try values.decodeIfPresent(String.self, forKey: .archived_at)
  }
}

private struct NativeProgramLibraryView: View {
  @EnvironmentObject private var appState: AppState
  let onCreate: () -> Void
  var refreshTrigger = false
  @State private var folders: [ProgramFolderRecord] = []
  @State private var templates: [LibraryTemplateRecord] = []
  @State private var folder: UUID?
  @State private var search = ""
  @State private var kind = "all"
  @State private var archived = false
  @State private var errorText: String?
  @State private var loading = false
  @State private var saving = false
  @State private var action: String?
  @State private var target: UUID?
  @State private var name = ""
  @State private var destination: UUID?

  private var visibleFolders: [ProgramFolderRecord] {
    folders.filter { ($0.archived_at != nil) == archived && (search.isEmpty ? archived || $0.parent_id == folder : $0.name.localizedCaseInsensitiveContains(search)) }
  }
  private var visibleTemplates: [LibraryTemplateRecord] {
    templates.filter { ($0.archived_at != nil) == archived && (kind == "all" || $0.template.program_kind == kind) && (search.isEmpty ? archived || $0.folder_id == folder : $0.template.name.localizedCaseInsensitiveContains(search)) }
  }
  private var breadcrumbs: [ProgramFolderRecord] {
    var result: [ProgramFolderRecord] = []; var current = folder; var seen = Set<UUID>()
    while let id = current, seen.insert(id).inserted, let row = folders.first(where: { $0.id == id }) {
      result.insert(row, at: 0); current = row.parent_id
    }
    return result
  }
  var body: some View {
    List {
      Section {
        TextField("Search all programs and folders", text: $search)
        HStack(spacing: HP.Space.sm) {
          Menu {
            Button("All program types") { kind = "all" }
            ForEach(["strength", "hitting", "pitching", "general"], id: \.self) { value in
              Button {
                kind = value
              } label: {
                Label(value.capitalized, systemImage: kind == value ? "checkmark" : "circle")
              }
            }
          } label: {
            Label(kind == "all" ? "All types" : kind.capitalized, systemImage: "line.3.horizontal.decrease.circle")
              .font(HP.Font.callout)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Toggle("Archived", isOn: $archived)
            .font(HP.Font.callout)
            .controlSize(.small)
        }
        ScrollView(.horizontal) {
          HStack {
            Button("Library / Unfiled") { folder = nil; search = "" }
              .dropDestination(for: String.self) { items, _ in receiveDrop(items, destination: nil) }
            ForEach(breadcrumbs) { row in Button(row.name) { folder = row.id; search = "" } }
          }
        }
      }
      if loading { ProgressView("Loading library…") }
      if let errorText { Text(errorText).foregroundStyle(.red) }
      Section("Folders") {
        ForEach(visibleFolders) { row in
          VStack(alignment: .leading) {
            Button { folder = row.id; search = ""; archived = false } label: { Label(row.name, systemImage: "folder") }
            controls(id: row.id, name: row.name, suffix: "folder", isArchived: row.archived_at != nil)
          }
          .draggable("folder:\(row.id.uuidString)")
          .dropDestination(for: String.self) { items, _ in row.archived_at == nil && receiveDrop(items, destination: row.id) }
        }
      }
      Section("Programs") {
        ForEach(visibleTemplates) { row in
          VStack(alignment: .leading, spacing: 8) {
            if row.archived_at == nil {
              NavigationLink {
                ProgramTemplateEditorView(template: row.template, onDuplicated: { _ in Task { await reload() } }, onDeleted: { Task { await reload() } })
              } label: { Label(row.template.name, systemImage: "doc.text") }
            } else { Text(row.template.name) }
            Text("\(row.template.weeks) weeks · \(row.template.program_kind ?? "general")").font(.caption)
            controls(id: row.id, name: row.template.name, suffix: "template", isArchived: row.archived_at != nil)
          }
          .draggable("template:\(row.id.uuidString)")
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Program Library")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Menu {
          Button("New program", action: onCreate)
          Button("New folder") { begin("create_folder") }
        } label: {
          Label("Create", systemImage: "plus")
        }
        NavigationLink {
          NativeSharedVideoLibraryView()
        } label: {
          Label("Video Library", systemImage: "video")
        }
      }
    }
    .refreshable { await reload() }
    .task(id: "\(appState.activeOrgId?.uuidString ?? ""):\(refreshTrigger)") { folder = nil; folders = []; templates = []; await reload() }
    .sheet(isPresented: Binding(get: { action != nil }, set: { if !$0 && !saving { action = nil } })) {
      NavigationStack {
        Form {
          Text(action?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Library")
          if action == "create_folder" || action?.hasPrefix("rename") == true { TextField("Name", text: $name) }
          if action?.hasPrefix("move") == true || action == "duplicate_template" || action == "restore_template" {
            Picker("Move to folder", selection: $destination) {
              Text("Unfiled / root").tag(UUID?.none)
              ForEach(folders.filter { $0.archived_at == nil && $0.id != target }) { Text($0.name).tag(Optional($0.id)) }
            }
          }
          Text("Archiving a folder archives its contents. Existing assignments and submissions remain available. Restore is explicit for each archived item.").font(.caption)
          if let errorText { Text(errorText).foregroundStyle(.red) }
          Button(saving ? "Saving…" : "Confirm") { Task { await perform() } }.disabled(saving)
          Button("Cancel", role: .cancel) { action = nil }.disabled(saving)
        }.navigationTitle("Program Library")
      }
    }
  }
  private func controls(id: UUID, name: String, suffix: String, isArchived: Bool) -> some View {
    Menu("Organize") {
      if !isArchived {
        Button("Rename") { begin("rename_\(suffix)", id, name) }
        Button("Move to folder") { begin("move_\(suffix)", id, name) }
        if suffix == "template" { Button("Duplicate") { begin("duplicate_template", id, name) } }
      }
      Button(isArchived ? "Restore" : "Archive") { begin("\(isArchived ? "restore" : "archive")_\(suffix)", id, name) }
    }
  }
  private func receiveDrop(_ items: [String], destination: UUID?) -> Bool {
    guard !saving, items.count == 1 else { return false }
    let parts = items[0].split(separator: ":")
    guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return false }
    let suffix = String(parts[0])
    guard (suffix == "folder" && folders.contains { $0.id == id && $0.archived_at == nil }) || (suffix == "template" && templates.contains { $0.id == id && $0.archived_at == nil }) else { return false }
    Task {
      guard let service = appState.supabase, let org = appState.activeOrgId else { return }
      struct Move: Encodable { let target_org: UUID; let action: String; let target_id: UUID; let destination_id: UUID? }
      saving = true; defer { saving = false }
      do { _ = try await service.client.rpc("sd_program_library_action", params: Move(target_org: org, action: "move_\(suffix)", target_id: id, destination_id: destination)).execute(); await reload() }
      catch { errorText = SDApplicationErrorClassifier.alertMessage(for: error) }
    }
    return true
  }
  private func begin(_ value: String, _ id: UUID? = nil, _ title: String = "") {
    action = value; target = id; name = title; destination = folder; errorText = nil
  }
  private func reload() async {
    guard let service = appState.supabase, let org = appState.activeOrgId else { return }
    loading = true; defer { loading = false }
    do {
      var fetchedFolders: [ProgramFolderRecord] = []; var fetchedTemplates: [LibraryTemplateRecord] = []
      var offset = 0
      while true {
        let page: [ProgramFolderRecord] = try await service.client.from("sd_program_folders").select().eq("org_id", value: org.uuidString).order("id").range(from: offset, to: offset + 999).execute().value
        fetchedFolders += page; if page.count < 1000 { break }; offset += 1000
      }
      offset = 0
      while true {
        let page: [LibraryTemplateRecord] = try await service.client.from("sd_program_templates").select().eq("org_id", value: org.uuidString).order("id").range(from: offset, to: offset + 999).execute().value
        fetchedTemplates += page; if page.count < 1000 { break }; offset += 1000
      }
      guard org == appState.activeOrgId else { return }
      folders = fetchedFolders; templates = fetchedTemplates; errorText = nil
    } catch { errorText = "Library unavailable: \(SDApplicationErrorClassifier.alertMessage(for: error) ?? "Please try again.")" }
  }
  private func perform() async {
    guard let service = appState.supabase, let org = appState.activeOrgId, let action else { return }
    struct Params: Encodable { let target_org: UUID; let action: String; let target_id: UUID?; let destination_id: UUID?; let new_name: String }
    saving = true; defer { saving = false }
    do {
      _ = try await service.client.rpc("sd_program_library_action", params: Params(target_org: org, action: action, target_id: target, destination_id: destination, new_name: name)).execute()
      self.action = nil; await reload()
    } catch { errorText = SDApplicationErrorClassifier.alertMessage(for: error) }
  }
}

struct CoachProgramsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.isPresented) private var isPresented
  @EnvironmentObject private var appState: AppState

  @State private var templates: [SDProgramTemplate] = []
  @State private var libraryEnabled = false
  @State private var isLoading = false
  @State private var errorText: String?

  @State private var showCreate = false
  @State private var query = ""
  @State private var selectedKind: SDProgramKind = .strength
  @State private var selectedWorkspace: Workspace

#if os(macOS)
  @State private var selectedTemplateId: UUID?
#endif

  init(initialWorkspace: Workspace = .workspace) {
    _selectedWorkspace = State(initialValue: initialWorkspace)
  }

  var body: some View {
#if os(macOS)
    VStack(spacing: 0) {
      workspacePicker
      workspaceContent
    }
    .navigationTitle(workspaceTitle)
    .task(id: appState.activeOrgId) { await reload() }
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          Task { await reload() }
        } label: { Image(systemName: "arrow.clockwise") }
          .accessibilityLabel("Refresh programs")
      }
    }
    .sheet(isPresented: $showCreate) {
      CreateProgramTemplateSheet(kind: selectedKind) { created in
        templates.insert(created, at: 0)
        selectedTemplateId = created.id
      }
      .environmentObject(appState)
      .frame(minWidth: 520, minHeight: 540)
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
#else
    NavigationStack {
      VStack(spacing: 0) {
        workspacePicker
        workspaceContent
      }
      .navigationTitle(workspaceTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if isPresented {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        }
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button {
              selectedWorkspace = .templates
            } label: {
              Label("Program Builder", systemImage: "list.clipboard")
            }
            Button {
              selectedWorkspace = .testingSetup
            } label: {
              Label("Testing Setup", systemImage: "slider.horizontal.3")
            }
          } label: {
            Label("Manage", systemImage: "ellipsis.circle")
          }
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
      .sheet(isPresented: $showCreate) {
        CreateProgramTemplateSheet(kind: selectedKind) { created in
          templates.insert(created, at: 0)
        }
        .environmentObject(appState)
      }
      .task(id: appState.activeOrgId) {
        await reload()
      }
    }
#endif
  }

  enum Workspace: String, CaseIterable, Hashable {
    case workspace = "Player Hub"
    case templates = "Library"
    case testingSetup = "Testing Setup"
  }

  private var workspaceTitle: String {
    switch selectedWorkspace {
    case .workspace: "Programs"
    case .templates: "Program Library"
    case .testingSetup: "Testing Setup"
    }
  }

  private var workspacePicker: some View {
    Picker("Programs workspace", selection: $selectedWorkspace) {
      ForEach(Workspace.allCases, id: \.self) { workspace in
        Text(workspace.rawValue).tag(workspace)
      }
    }
    .pickerStyle(.segmented)
    .controlSize(.small)
    .padding(.horizontal, HP.Space.md)
    .padding(.vertical, 4)
    .background(HP.Color.bg)
  }

  @ViewBuilder
  private var workspaceContent: some View {
    switch selectedWorkspace {
    case .workspace:
      UnifiedPlayerDevelopmentWorkspaceView(onOpenTemplateBuilder: {
        selectedWorkspace = .templates
      })
    case .templates:
      if libraryEnabled {
        NativeProgramLibraryView(onCreate: { showCreate = true }, refreshTrigger: showCreate)
      } else {
        templateListLayout
      }
    case .testingSetup:
      TestingSetupWorkspaceView()
    }
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var templateListLayout: some View {
    HPListScreenLayout {
      HPWorkspaceHeader(
        "Programs",
        orgLabel: activeOrganizationName,
        context: "\(presentedTemplates.count) \(selectedKind.title.lowercased()) template\(presentedTemplates.count == 1 ? "" : "s")"
      ) {
        HPButton(
          title: "New program",
          systemImage: "plus",
          variant: .primary,
          size: .sm,
          action: { showCreate = true }
        )
      }
    } controls: {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          VStack(alignment: .leading, spacing: 6) {
            Text("PROGRAM TYPE")
              .font(HP.Font.eyebrow)
              .tracking(HP.Font.eyebrowTracking)
              .foregroundStyle(HP.Color.textMuted)
            HPSegmentedControl(
              options: SDProgramKind.allCases.map { (value: $0, label: $0.title) },
              selection: $selectedKind
            )
          }
          #if os(macOS)
          HPSearchBar(text: $query, placeholder: "Search templates")
          #endif
        }
      }
    } results: { context in
      templateResults(context)
    }
  }

  private var presentedTemplates: [SDProgramTemplate] {
    #if os(macOS)
    filteredTemplates
    #else
    visibleTemplates
    #endif
  }

  private func templateResults(_ context: HPScreenLayoutContext) -> some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("\(selectedKind.title) program templates") {
          HPStatusBadge(text: "\(presentedTemplates.count)", kind: .neutral)
        }

        if isLoading {
          HPLoadingState(text: "Loading…")
        } else if presentedTemplates.isEmpty {
          HPEmptyState(
            title: "No \(selectedKind.title) program templates yet.",
            message: "Create a \(selectedKind.title.lowercased()) template to get started.",
            systemImage: selectedKind.systemImage
          )
        } else {
          if context.tableLayout == .columns {
            templateColumnHeader
          }

          ForEach(presentedTemplates) { template in
            templateAction(template, stacked: context.tableLayout != .columns)

            if template.id != presentedTemplates.last?.id {
              Divider().overlay(HP.Color.border.opacity(0.5))
            }
          }
        }
      }
    }
  }

  private var templateColumnHeader: some View {
    HStack(spacing: HP.Space.sm) {
      Text("NAME")
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("WEEKS")
        .frame(width: 72, alignment: .leading)
      Text("DAYS")
        .frame(width: 180, alignment: .leading)
      Color.clear.frame(width: 20, height: 1).accessibilityHidden(true)
    }
    .font(HP.Font.eyebrow)
    .tracking(HP.Font.eyebrowTracking)
    .foregroundStyle(HP.Color.textMuted)
    .padding(.vertical, 6)
  }

  @ViewBuilder
  private func templateAction(_ template: SDProgramTemplate, stacked: Bool) -> some View {
    #if os(macOS)
    Button {
      selectedTemplateId = template.id
    } label: {
      templateRow(template, stacked: stacked, selected: selectedTemplateId == template.id)
    }
    .buttonStyle(.plain)
    #else
    NavigationLink {
      ProgramTemplateEditorView(
        template: template,
        onDuplicated: { templates.insert($0, at: 0) },
        onDeleted: { templates.removeAll { $0.id == template.id } }
      )
      .id(template.id)
    } label: {
      templateRow(template, stacked: stacked, selected: false)
    }
    .buttonStyle(.plain)
    #endif
  }

  @ViewBuilder
  private func templateRow(_ template: SDProgramTemplate, stacked: Bool, selected: Bool) -> some View {
    if stacked {
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        Text(template.name)
          .font(HP.Font.headline)
          .foregroundStyle(HP.Color.text)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(template.weeks) weeks • \(weekdayLabel(template.lift_weekdays))")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, selected ? HP.Space.xs : 0)
      .background(selected ? HP.Color.accent.opacity(0.12) : .clear)
      .contentShape(Rectangle())
    } else {
      HStack(spacing: HP.Space.sm) {
        Text(template.name)
          .font(HP.Font.callout.weight(.semibold))
          .foregroundStyle(HP.Color.text)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("\(template.weeks)")
          .font(HP.Font.number(.callout))
          .foregroundStyle(HP.Color.text)
          .frame(width: 72, alignment: .leading)
        Text(weekdayLabel(template.lift_weekdays))
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(2)
          .frame(width: 180, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(HP.Color.textMuted)
          .frame(width: 20)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, selected ? HP.Space.xs : 0)
      .background(selected ? HP.Color.accent.opacity(0.12) : .clear)
      .contentShape(Rectangle())
    }
  }

  private var visibleTemplates: [SDProgramTemplate] {
    templates.filter { $0.kind == selectedKind }
  }

#if os(macOS)
  private var filteredTemplates: [SDProgramTemplate] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return templates.filter {
      $0.kind == selectedKind && (q.isEmpty || $0.name.lowercased().contains(q))
    }
  }

  private var selectedTemplate: SDProgramTemplate? {
    guard let selectedTemplateId else { return nil }
    return templates.first(where: { $0.id == selectedTemplateId })
  }

  @ViewBuilder
  private var templateDetail: some View {
    if let t = selectedTemplate {
      ProgramTemplateEditorView(
        template: t,
        onDuplicated: { duplicated in
          templates.insert(duplicated, at: 0)
          selectedTemplateId = duplicated.id
        },
        onDeleted: {
          templates.removeAll { $0.id == t.id }
          selectedTemplateId = filteredTemplates.first?.id
        }
      )
        .id(t.id)
        .environmentObject(appState)
    } else {
      HPStateScreenLayout { _ in
        HPCard {
          HPEmptyState(
            title: "Select a template",
            message: "Choose a program template to edit, or create a new one.",
            systemImage: "rectangle.stack"
          )
        }
      }
    }
  }
#endif

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    let org = appState.activeOrgId
    libraryEnabled = false
    isLoading = true
    defer { isLoading = false }
    do {
      if let org { libraryEnabled = (try? await supabase.libraryRolloutEnabled(organizationId: org)) == true }
      let fetched = try await supabase.listMyCoachTemplates(orgId: org)
      guard org == appState.activeOrgId else { return }
      templates = fetched
#if os(macOS)
      if selectedTemplateId == nil {
        selectedTemplateId = templates.first?.id
      }
#endif
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }

  private func weekdayLabel(_ days: [Int]) -> String {
    let map: [Int: String] = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
    return days.compactMap { map[$0] }.joined(separator: ", ")
  }
}

private struct CreateProgramTemplateSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  let kind: SDProgramKind
  let onCreated: (SDProgramTemplate) -> Void

  @State private var name = ""
  @State private var weeks = 2
  @State private var liftDays: Set<Int> = [1, 3, 5] // MWF
  @State private var isSaving = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "New \(kind.title) program",
          orgLabel: activeOrganizationName,
          context: "\(weeks) weeks • \(liftDays.count) training day\(liftDays.count == 1 ? "" : "s")"
        )
      } sections: { _ in
        templateSection
        trainingDaysSection
      } primaryAction: { context in
        HPButton(
          title: "Create",
          systemImage: "plus",
          variant: .primary,
          size: .lg,
          isLoading: isSaving,
          fullWidth: context.isAccessibilitySize,
          action: { Task { await create() } }
        )
        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || liftDays.isEmpty)
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle("Create program")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
      .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorText ?? "")
      }
    }
  }

  private var activeOrganizationName: String {
    if let organizationId = appState.activeOrgId,
       let organization = appState.availableOrganizations.first(where: { $0.id == organizationId }) {
      return organization.displayName
    }
    return appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var templateSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Template")
        HPFormField(
          label: "\(kind.title) program name",
          text: $name,
          placeholder: "\(kind.title) program name"
        )
        VStack(alignment: .leading, spacing: 6) {
          Text("WEEKS")
            .font(HP.Font.eyebrow)
            .tracking(HP.Font.eyebrowTracking)
            .foregroundStyle(HP.Color.textMuted)
          Picker("Weeks", selection: $weeks) {
            Text("2 weeks").tag(2)
            Text("4 weeks").tag(4)
          }
          .pickerStyle(.segmented)
          .tint(HP.Color.accent)
        }
      }
    }
  }

  private var trainingDaysSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(kind == .strength ? "Lift days (weekdays)" : "Training days (weekdays)")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: HP.Space.sm) {
          ForEach(1...7, id: \.self) { index in
            Button {
              if liftDays.contains(index) { liftDays.remove(index) } else { liftDays.insert(index) }
            } label: {
              Text(weekday(index)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(HPButtonStyle(variant: liftDays.contains(index) ? .primary : .secondary, size: .sm, fullWidth: true))
            .accessibilityValue(liftDays.contains(index) ? "Selected" : "Not selected")
          }
        }
      }
    }
  }

  private func weekday(_ i: Int) -> String {
    ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][i]
  }

  private func create() async {
    guard let supabase = appState.supabase else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let created = try await supabase.createProgramTemplate(
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        kind: kind,
        weeks: weeks,
        liftWeekdays: liftDays.sorted(),
        orgId: appState.activeOrgId
      )
      onCreated(created)
      dismiss()
    } catch {
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }
}

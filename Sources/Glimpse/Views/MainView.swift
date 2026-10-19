import SwiftUI

enum SidebarItem: Hashable {
    case timeline
    case category(Category)
}

struct MainView: View {
    @EnvironmentObject var store: CaptureStore
    @EnvironmentObject var settings: AppSettings
    @State private var selection: SidebarItem? = .timeline
    @State private var selectedCaptureID: UUID?
    @State private var searchText = ""

    private var filtered: [Capture] {
        store.captures.filter { $0.matches(search: searchText) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Timeline", systemImage: "clock")
                        .tag(SidebarItem.timeline)
                        .badge(store.captures.count)
                }
                Section("Categories") {
                    ForEach(Category.allCases) { cat in
                        Label {
                            Text(cat.title)
                        } icon: {
                            Image(systemName: cat.symbol).foregroundStyle(cat.color)
                        }
                        .tag(SidebarItem.category(cat))
                        .badge(store.captures(in: cat).count)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } content: {
            Group {
                switch selection ?? .timeline {
                case .timeline:
                    TimelineList(captures: filtered, selection: $selectedCaptureID)
                        .navigationTitle("Timeline")
                case .category(let cat):
                    CategoryList(category: cat, captures: filtered.filter { $0.category == cat }, selection: $selectedCaptureID)
                        .navigationTitle(cat.title)
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search captures")
            .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 560)
        } detail: {
            if let id = selectedCaptureID, let capture = store.capture(id: id) {
                CaptureDetailView(capture: capture)
                    .id(capture.id)
            } else {
                ContentUnavailableView {
                    Label("Nothing selected", systemImage: "rectangle.dashed")
                } description: {
                    Text("⌥⇧S captures a screen region · ⌥⇧N starts a quick note")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    CaptureFlow.startScreenshot()
                } label: {
                    Label("Screenshot", systemImage: "camera.viewfinder")
                }
                .help("Capture a screen region (⌥⇧S)")
                Button {
                    CaptureFlow.startNote()
                } label: {
                    Label("Note", systemImage: "square.and.pencil")
                }
                .help("Quick note (⌥⇧N)")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if settings.apiKey == nil && settings.enrichmentEnabled {
                MissingKeyBanner()
            }
        }
        .onChange(of: selection) { _, _ in
            selectedCaptureID = nil
        }
    }
}

struct MissingKeyBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "key")
            Text("Add your Anthropic API key in Settings so Claude can title, summarize, and categorize captures.")
                .font(.callout)
            Spacer()
            SettingsLink {
                Text("Open Settings")
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

struct TimelineList: View {
    let captures: [Capture]
    @Binding var selection: UUID?

    var body: some View {
        let groups = CaptureStore.groupByDay(captures)
        List(selection: $selection) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { capture in
                        CaptureRow(capture: capture).tag(capture.id)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(DayFormat.label(for: group.day))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(DayFormat.detail(for: group.day))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(group.items.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if captures.isEmpty {
                ContentUnavailableView {
                    Label("No captures yet", systemImage: "camera.viewfinder")
                } description: {
                    Text("Press ⌥⇧S anywhere to grab part of your screen, or ⌥⇧N to jot a note.")
                }
            }
        }
    }
}

struct CategoryList: View {
    let category: Category
    let captures: [Capture]
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(captures) { capture in
                    CaptureRow(capture: capture, showDate: true).tag(capture.id)
                }
            } header: {
                HStack {
                    Image(systemName: category.symbol).foregroundStyle(category.color)
                    Text(category.guidance.prefix(1).uppercased() + category.guidance.dropFirst())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
        .overlay {
            if captures.isEmpty {
                ContentUnavailableView {
                    Label("Nothing in \(category.title)", systemImage: category.symbol)
                } description: {
                    Text("Press ⌘\(category.hotkeyNumber) while capturing to file something here.")
                }
            }
        }
    }
}

struct CaptureRow: View {
    let capture: Capture
    var showDate: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumbnail(capture: capture)
            VStack(alignment: .leading, spacing: 3) {
                Text(capture.displayTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let sub = capture.subtitle {
                    Text(sub)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if showDate {
                        Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text(capture.createdAt, style: .time)
                    }
                    if let app = capture.sourceApp {
                        Text("·")
                        Text(app).lineLimit(1)
                    }
                    Spacer()
                    if let cat = capture.category {
                        CategoryBadge(category: cat, dimmed: capture.categorySource == .ai)
                    }
                    AIStatusIndicator(status: capture.aiStatus)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

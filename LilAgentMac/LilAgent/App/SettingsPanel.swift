import SwiftUI
import AppKit
import Observation


@Observable
final class SettingsModel {
    var values: PetSettings
    var claudeConnected = false
    var codexConnected = false
    var agentStatus = ""
    var typingNote: String?
    var asleep = false
    var shortcutErrors: [String] = []
    var update = UpdateStatus.idle

    @ObservationIgnored var change: ((inout PetSettings) -> Void) -> Void = { _ in }
    @ObservationIgnored var preview: (String) -> Void = { _ in }
    @ObservationIgnored var command: (String) -> Void = { _ in }
    @ObservationIgnored var resetPosition: () -> Void = {}
    @ObservationIgnored var toggleClaudeHooks: () -> Void = {}
    @ObservationIgnored var toggleCodexHooks: () -> Void = {}
    @ObservationIgnored var openInputMonitoring: () -> Void = {}
    @ObservationIgnored var revealApp: () -> Void = {}
    @ObservationIgnored var close: () -> Void = {}
    @ObservationIgnored var checkUpdates: () -> Void = {}
    @ObservationIgnored var openUpdate: () -> Void = {}

    init(values: PetSettings) { self.values = values }

    func binding<T>(_ path: WritableKeyPath<PetSettings, T>) -> Binding<T> {
        Binding(get: { self.values[keyPath: path] }, set: { value in self.change { $0[keyPath: path] = value } })
    }

    func allowed(_ state: String) -> Binding<Bool> {
        Binding(get: { self.values.allows(state) }, set: { on in
            self.change { s in
                s.disabled.removeAll { $0 == state }
                if !on { s.disabled.append(state) }
            }
        })
    }
}

final class SettingsWindow: NSWindow {
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "\(Brand.name) Settings"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        toolbar = NSToolbar(identifier: "LilAgentSettings")
        toolbarStyle = .unifiedCompact
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.fullScreenNone, .moveToActiveSpace]
        contentMinSize = SettingsView.minimumSize
        isReleasedWhenClosed = false
        level = .normal
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", character = "Character", moods = "Moods", agents = "Agents", keybinds = "Keybinds"

    var id: Self { self }
    var icon: IconName {
        switch self {
        case .general: .asset("tab-general")
        case .character: .asset("tab-appearance")
        case .moods: .symbol("face.smiling.inverse")
        case .agents: .symbol("sparkles")
        case .keybinds: .asset("tab-keybinds")
        }
    }
}

enum IconName {
    case asset(String)
    case symbol(String)
}

struct SettingsView: View {
    static let defaultSize = CGSize(width: 448, height: 540)
    static let minimumSize = CGSize(width: 448, height: 380)

    @Bindable var model: SettingsModel
    @State private var tab: SettingsTab
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(model: SettingsModel, tab: SettingsTab = .general) {
        self.model = model
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Brand.name) Settings").font(SettingsStyle.font(12.5))
                .frame(height: 42)
                .accessibilityAddTraits(.isHeader)
            tabBar.padding(.top, 8)
            card.padding(.top, 12.5).padding(.horizontal, 42.5).padding(.bottom, 43.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { glass }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background { Button("Close", action: model.close).keyboardShortcut(.cancelAction).hidden() }
    }

    @ViewBuilder private var glass: some View {
        if reduceTransparency {
            SettingsStyle.window
        } else if #available(macOS 26.0, *) {
            ZStack {
                Rectangle().fill(.ultraThickMaterial)
                Color.black.opacity(0.35)
                Color.clear.glassEffect(.regular.tint(.black.opacity(0.2)), in: Rectangle())
            }
        } else {
            ZStack {
                Rectangle().fill(.ultraThickMaterial)
                Color.black.opacity(0.45)
            }
        }
    }


    private var tabBar: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(SettingsTab.allCases) { item in
                if item != .general { Spacer(minLength: 8) }
                tabButton(item)
            }
        }
        .padding(.horizontal, 44)
    }

    private func tabButton(_ item: SettingsTab) -> some View {
        let selected = tab == item
        return Button { tab = item } label: {
            VStack(spacing: 3.5) {
                TabIcon(name: item.icon, selected: selected).frame(width: 40, height: 40)
                Text(item.rawValue).font(SettingsStyle.font(9.5)).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var card: some View {
        Group {
            switch tab {
            case .general: general
            case .character: character
            case .moods: moods
            case .agents: agents
            case .keybinds: keybinds
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsStyle.card, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }


    private func page<Content: View>(leading: CGFloat = 31, trailing: CGFloat = 31, bottom: CGFloat,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        let rows = SpreadStack(bottom: bottom) { content() }
            .padding(.leading, leading)
            .padding(.trailing, trailing)
        return ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }.scrollIndicators(.automatic)
        }
    }

    private func list<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 31)
                .padding(.top, 26)
                .padding(.bottom, 26)
        }
        .scrollIndicators(.automatic)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(SettingsStyle.font(9.5)).accessibilityAddTraits(.isHeader)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(SettingsStyle.label).foregroundStyle(SettingsStyle.secondary).lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func row<Control: View>(_ icon: IconName, _ text: String, spacing: CGFloat = 5.5,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 0) {
            Icon(icon)
            label(text).padding(.leading, spacing)
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: 20)
    }

    private func note(_ text: String, error: Bool = false) -> some View {
        Text(text).font(SettingsStyle.label)
            .foregroundStyle(error ? SettingsStyle.errorText : SettingsStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding).toggleStyle(SwitchStyle())
    }

    private func activity(_ item: Activity, canDisable: Bool = true) -> some View {
        row(item.icon, item.title, spacing: 7) {
            HStack(spacing: 10) {
                Button("Preview") { model.preview(item.state) }
                    .buttonStyle(OutlineButtonStyle(width: 52.5))
                    .accessibilityLabel("Preview \(item.title)")
                if canDisable {
                    toggle(item.title, model.allowed(item.state))
                } else {
                    Color.clear.frame(width: 38.5, height: 19)
                }
            }
        }
    }


    private var general: some View {
        page(leading: 38, trailing: 43, bottom: 17.5) {
            header("Updates").gap(47)
            row(.asset("general-version"), versionText) { updateButton }
            .gap(20)
            header("Behavior").gap(20)
            row(.asset("general-reset-position"), "Reset Position") {
                Button("Reset", action: model.resetPosition).buttonStyle(OutlineButtonStyle(width: 52.5))
                    .accessibilityLabel("Reset the mascot's position")
            }
            .gap(16)
            row(.asset("general-keep-on-top"), "Keep on top of all windows", spacing: 4.5) {
                toggle("Keep on top of all windows", model.binding(\.keepOnTop))
            }
            .gap(21)
            row(.symbol("text.alignleft"), "Show mascot text") {
                toggle("Show mascot text", model.binding(\.showStatusText))
            }
            .gap(16)
            header("Startup").gap(23.5)
            row(.asset(model.values.openAtLogin ? "general-startup-on" : "general-startup-off"),
                "\(Brand.name) will automatically open at login", spacing: 4) {
                toggle("Open at login", model.binding(\.openAtLogin))
            }
            .gap(16.5)
            Button { NSApp.terminate(nil) } label: {
                HStack(spacing: 4) {
                    Icon(.asset("general-startup-off"), scale: 0.15)
                    label("Quit")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quit \(Brand.name)")
            .frame(maxWidth: .infinity)
            .gap(23)
        }
    }

    private var versionText: String {
        if case .available(let latest, _) = model.update { return "\(Brand.name) version \(Self.version) (\(latest) is out)" }
        return "\(Brand.name) version \(Self.version)"
    }

    @ViewBuilder private var updateButton: some View {
        switch model.update {
        case .available(let latest, _):
            Button("Update Available", action: model.openUpdate).buttonStyle(OutlineButtonStyle(width: 52.5, selected: true))
                .accessibilityLabel("Download \(Brand.name) \(latest)")
        case .checking:
            Button("Checking…") {}.buttonStyle(OutlineButtonStyle(width: 52.5)).disabled(true)
        case .current:
            Button("Up to Date", action: model.checkUpdates).buttonStyle(OutlineButtonStyle(width: 52.5))
                .accessibilityLabel("Up to date. Check for updates again")
        case .failed:
            Button("Try Again", action: model.checkUpdates).buttonStyle(OutlineButtonStyle(width: 52.5))
                .accessibilityLabel("Couldn't check for updates. Try again")
        case .idle:
            Button("Check", action: model.checkUpdates).buttonStyle(OutlineButtonStyle(width: 52.5))
                .accessibilityLabel("Check for updates")
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }


    private var character: some View {
        page(leading: 30, trailing: 30, bottom: 24.5) {
            header("Character").gap(26.5)
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 8)
                ForEach(PetCharacter.allCases, id: \.self) { c in
                    if c != PetCharacter.allCases.first { Spacer(minLength: 8).frame(maxWidth: 60) }
                    characterOption(c)
                }
                Spacer(minLength: 8)
            }
            .gap(12)
            header("Size").gap(24)
            row(.symbol("arrow.up.left.and.arrow.down.right"), "\(model.values.petSize) px", spacing: 7) {
                Slider(value: Binding(get: { Double(model.values.petSize) },
                                      set: { v in model.change { $0.petSize = PetSizes.clampSize(v) } }),
                       in: Double(PetSizes.range.lowerBound)...Double(PetSizes.range.upperBound))
                    .controlSize(.mini)
                    .tint(.white)
                    .frame(width: 190)
                    .accessibilityLabel("Size")
            }
            .gap(14)
            HStack(spacing: 6) {
                ForEach(PetSizes.presets, id: \.1) { name, px in
                    Button(name) { model.change { $0.petSize = px } }
                        .buttonStyle(OutlineButtonStyle(width: 44, selected: model.values.petSize == px))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .gap(14)
            note("Each character keeps its own size. You can also scroll over the mascot to resize it.").gap(18)
        }
    }

    private func characterOption(_ c: PetCharacter) -> some View {
        let selected = model.values.character == c.rawValue
        return Button { model.change { $0.character = c.rawValue } } label: {
            VStack(spacing: 4) {
                label(c.title)
                Image("character-\(c.rawValue)").resizable().interpolation(.high).scaledToFit()
                    .frame(width: 58, height: 58)
                    .opacity(selected ? 1 : 0.55)
                    .accessibilityHidden(true)
                Image(systemName: selected ? "checkmark.circle.fill" : "checkmark.circle")
                    .symbolRenderingMode(selected ? .palette : .monochrome)
                    .foregroundStyle(selected ? SettingsStyle.card : .white, .white.opacity(0.85))
                    .font(.system(size: 11))
                    .padding(.top, 4)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }


    private var moods: some View {
        list {
            header("Right Now").padding(.bottom, 14)
            HStack(spacing: 8) {
                Button(model.asleep ? "Wake up" : "Go to sleep") { model.command(model.asleep ? "wake" : "sleepy") }
                    .buttonStyle(OutlineButtonStyle(width: 70))
                Button("Wave") { model.command("wave") }.buttonStyle(OutlineButtonStyle(width: 52.5)).disabled(model.asleep)
                Button("Dance") { model.command("dance") }.buttonStyle(OutlineButtonStyle(width: 52.5)).disabled(model.asleep)
            }
            .padding(.bottom, 24)
            header("Behavior").padding(.bottom, 14)
            row(.symbol("figure.walk"), "Wanders around the screen", spacing: 7) {
                toggle("Wanders around", model.binding(\.autoWalk))
            }
            .padding(.bottom, 12)
            row(.symbol("eyes"), "Looks at your cursor", spacing: 7) {
                toggle("Looks at your cursor", model.binding(\.lookAtCursor))
            }
            .padding(.bottom, 12)
            row(.asset("appearance-moon"), "Falls asleep when you're away", spacing: 7) {
                Menu {
                    ForEach(Self.idleChoices, id: \.1) { title, minutes in
                        Button(title) { model.change { $0.idleSleepMin = minutes } }
                    }
                } label: {
                    Text(Self.idleChoices.first { $0.1 == model.values.idleSleepMin }?.0 ?? "\(model.values.idleSleepMin) min")
                }
                .menuStyle(.button)
                .buttonStyle(OutlineButtonStyle(width: 86))
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.bottom, 12)
            row(.asset("appearance-music-notes"), "Dances while Spotify or Music plays", spacing: 7) {
                toggle("Dance to music", model.binding(\.musicDance))
            }
            .padding(.bottom, 24)
            header("Moods").padding(.bottom, 6)
            note("Things he does by himself now and then. Turn any off and he won’t.").padding(.bottom, 12)
            ForEach(Activity.moods) { activity($0).padding(.bottom, 10) }
            header("Sleep").padding(.top, 14).padding(.bottom, 12)
            ForEach(Activity.sleep) { activity($0, canDisable: false).padding(.bottom, 10) }
        }
    }

    private static let idleChoices: [(String, Double)] = [
        ("Never", 0), ("After 30 s", 0.5), ("After 5 min", 5), ("After 15 min", 15), ("After 25 min", 25),
    ]


    private var agents: some View {
        list {
            header("Connections").padding(.bottom, 14)
            connection("Claude Code", connected: model.claudeConnected, action: model.toggleClaudeHooks)
                .padding(.bottom, 12)
            connection("Codex", connected: model.codexConnected, action: model.toggleCodexHooks)
                .padding(.bottom, 10)
            note(model.agentStatus).padding(.bottom, 22)
            header("Behavior").padding(.bottom, 14)
            row(.symbol("sparkles"), "Reacts to Claude Code and Codex", spacing: 7) {
                toggle("React to Claude Code and Codex", model.binding(\.agentReactions))
            }
            .padding(.bottom, 12)
            row(.symbol("keyboard"), "Types along with your keyboard", spacing: 7) {
                toggle("Type along", model.binding(\.typeAlong))
            }
            .padding(.bottom, 8)
            if let why = model.typingNote {
                HStack(spacing: 8) {
                    note(why, error: true)
                    Spacer(minLength: 8)
                    Button("Open Settings", action: model.openInputMonitoring).buttonStyle(OutlineButtonStyle(width: 80))
                    Button("Show App", action: model.revealApp).buttonStyle(OutlineButtonStyle(width: 58))
                }
                .padding(.bottom, 8)
            }
            header("Reactions").padding(.top, 14).padding(.bottom, 6)
            note("What he acts out while an agent works. Turn any off and he ignores it.").padding(.bottom, 12)
            ForEach(Activity.reactions) { activity($0).padding(.bottom, 10) }
        }
    }

    private func connection(_ name: String, connected: Bool, action: @escaping () -> Void) -> some View {
        row(connected ? .asset("music-connected") : .symbol("link"), connected ? "\(name) is connected" : "\(name) isn’t connected",
            spacing: 7) {
            Button(connected ? "Disconnect" : "Connect…", action: action)
                .buttonStyle(OutlineButtonStyle(width: 80))
                .accessibilityLabel(connected ? "Disconnect \(name)" : "Connect \(name)")
        }
    }


    private var keybinds: some View {
        page(leading: 29.5, trailing: 40, bottom: 29) {
            header("Mascot").gap(29)
            HStack(spacing: 0) {
                Icon(.symbol("eye")).frame(width: 29, height: 25)
                label("Show or hide the mascot").padding(.leading, 7.5)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    Icon(.asset("keybind-cmd"), scale: 0.17).accessibilityHidden(true)
                    Text("+").font(.system(size: 16, weight: .light)).foregroundStyle(SettingsStyle.secondary)
                    Icon(.asset("keybind-slash")).scaleEffect(x: -1, y: 1).frame(width: 20, height: 20)
                }
                .frame(width: 72, alignment: .leading)
                .accessibilityLabel("Command backslash")
                toggle("Enable show/hide shortcut", model.binding(\.showHideShortcut))
                    .padding(.leading, 12)
            }
            .accessibilityElement(children: .contain)
            .gap(15)
            ForEach(model.shortcutErrors, id: \.self) { note($0, error: true).gap(8) }
            header("Mouse").gap(36)
            mouseRow("cursorarrow.click.2", "Right-click the mascot", "Settings").gap(14)
            mouseRow("hand.draw", "Drag the mascot", "Carry or throw").gap(14)
            mouseRow("hand.tap", "Click the mascot", "Pet it").gap(14)
            mouseRow("scroll", "Scroll over the mascot", "Resize").gap(14)
        }
    }

    private func mouseRow(_ symbol: String, _ text: String, _ result: String) -> some View {
        HStack(spacing: 0) {
            Icon(.symbol(symbol)).frame(width: 29, height: 25)
            label(text).padding(.leading, 7.5)
            Spacer(minLength: 12)
            Text(result).font(SettingsStyle.font(9)).foregroundStyle(.white.opacity(0.85))
                .frame(width: 72, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}


struct Activity: Identifiable {
    let title: String
    let state: String
    let icon: IconName
    var id: String { state }

    static let moods: [Activity] = [
        Activity(title: "Coffee break", state: "coffee", icon: .symbol("cup.and.saucer")),
        Activity(title: "Workout", state: "workout", icon: .symbol("dumbbell")),
        Activity(title: "Meditate", state: "meditate", icon: .symbol("figure.mind.and.body")),
        Activity(title: "Bright idea", state: "idea", icon: .symbol("lightbulb")),
        Activity(title: "Happy", state: "happy", icon: .symbol("face.smiling")),
        Activity(title: "Excited", state: "excited", icon: .symbol("star")),
        Activity(title: "Curious", state: "curious", icon: .symbol("eyes")),
        Activity(title: "Sad", state: "sad", icon: .symbol("cloud.rain")),
        Activity(title: "Dance", state: "dance", icon: .symbol("figure.dance")),
        Activity(title: "Wave", state: "wave", icon: .symbol("hand.wave")),
        Activity(title: "Annoyed (lots of clicks)", state: "annoyed", icon: .symbol("cursorarrow.click.2")),
        Activity(title: "Dizzy (thrown)", state: "dizzy", icon: .symbol("tornado")),
    ]

    static let sleep: [Activity] = [
        Activity(title: "Sleepy", state: "sleepy", icon: .asset("appearance-moon")),
        Activity(title: "Asleep", state: "sleep", icon: .symbol("zzz")),
        Activity(title: "Waking up", state: "wake", icon: .asset("appearance-sun")),
    ]

    static let reactions: [Activity] = [
        Activity(title: "Thinking", state: "thinking", icon: .symbol("brain.head.profile")),
        Activity(title: "Reading a file", state: "reading", icon: .symbol("book")),
        Activity(title: "Searching", state: "searching", icon: .symbol("magnifyingglass")),
        Activity(title: "Editing (laptop)", state: "typing", icon: .symbol("laptopcomputer")),
        Activity(title: "Running a command", state: "command", icon: .symbol("terminal")),
        Activity(title: "Planning", state: "planning", icon: .symbol("checklist")),
        Activity(title: "Sending out helpers", state: "subagents", icon: .symbol("person.3")),
        Activity(title: "Needs your permission", state: "permission", icon: .symbol("hand.raised")),
        Activity(title: "Asking a question", state: "question", icon: .symbol("questionmark.bubble")),
        Activity(title: "Needs your attention", state: "attention", icon: .symbol("bell")),
        Activity(title: "Compacting", state: "compacting", icon: .symbol("rectangle.compress.vertical")),
        Activity(title: "Something failed", state: "error", icon: .symbol("exclamationmark.triangle")),
        Activity(title: "Done", state: "done", icon: .asset("music-connected")),
        Activity(title: "Waiting for you", state: "waiting", icon: .symbol("hourglass")),
    ]
}


enum SettingsStyle {
    static let window = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2A / 255)
    static let card = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let activeTab = Color(red: 0x57 / 255, green: 0x57 / 255, blue: 0x57 / 255)
    static let secondary = Color.white.opacity(0.5)
    static let errorText = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let label = font(7.5, .regular)
    static let unit: CGFloat = 0.162

    static func font(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight) }
}

private struct Icon: View {
    var name: IconName
    var scale: CGFloat

    init(_ name: IconName, scale: CGFloat = SettingsStyle.unit) {
        self.name = name
        self.scale = scale
    }

    var body: some View {
        Group {
            switch name {
            case .asset(let asset):
                let size = NSImage(named: asset)?.size ?? .zero
                Image(asset).resizable()
                    .frame(width: size.width * scale, height: size.height * scale)
            case .symbol(let symbol):
                Image(systemName: symbol)
                    .font(.system(size: 13 * scale / SettingsStyle.unit, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 18 * scale / SettingsStyle.unit, height: 18 * scale / SettingsStyle.unit)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct TabIcon: View {
    var name: IconName
    var selected: Bool

    var body: some View {
        switch name {
        case .asset(let asset):
            Icon(.asset(selected ? asset + "-active" : asset), scale: 0.2)
        case .symbol(let symbol):
            if selected {
                RoundedRectangle(cornerRadius: 5).fill(SettingsStyle.activeTab)
                    .overlay {
                        Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct SpreadGap: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

private extension View {
    func gap(_ value: CGFloat) -> some View { layoutValue(key: SpreadGap.self, value: value) }
}

private struct SpreadStack: Layout {
    var bottom: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let natural = heights(width, subviews).reduce(0, +) + gaps(subviews).reduce(0, +)
        let height = proposal.height.flatMap { $0.isFinite ? max($0, natural) : nil } ?? natural
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = heights(bounds.width, subviews), gaps = gaps(subviews)
        let totalGap = gaps.reduce(0, +)
        let extra = max(0, bounds.height - heights.reduce(0, +) - totalGap)
        let stretch = totalGap > 0 ? 1 + extra / totalGap : 1
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            y += gaps[index] * stretch
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: heights[index]))
            y += heights[index]
        }
    }

    private func heights(_ width: CGFloat, _ subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    }

    private func gaps(_ subviews: Subviews) -> [CGFloat] { subviews.map { $0[SpreadGap.self] } + [bottom] }
}

private struct OutlineButtonStyle: ButtonStyle {
    var width: CGFloat
    var selected = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsStyle.font(9))
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: width, minHeight: 19)
            .padding(.horizontal, 2)
            .foregroundStyle(selected ? SettingsStyle.card : .white)
            .background { if selected { Capsule().fill(.white) } }
            .overlay(Capsule().strokeBorder(.white, lineWidth: 1.2))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : isEnabled ? 1 : 0.4)
    }
}

private struct SwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { configuration.isOn.toggle() }
        } label: {
            Capsule().strokeBorder(.white, lineWidth: 1.2)
                .frame(width: 38.5, height: 19)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 14, height: 14).padding(.horizontal, 2.5)
                }
                .opacity(configuration.isOn ? 1 : 0.5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

let appID = "local.browserrouter.app"

struct Browser: Identifiable {
    var id: String
    var name: String
    var url: URL
}

final class Store: ObservableObject {
    @Published var preferences = Preferences()
    @Published var browsers: [Browser] = []
    @Published var message = ""
    @Published var recent = "尚未接收链接"
    @Published var isDefault = false
    let configURL: URL

    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--config"), CommandLine.arguments.count > i + 1 {
            configURL = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        } else {
            configURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BrowserRouter/preferences.json")
        }
        if FileManager.default.fileExists(atPath: configURL.path) {
            do { preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL)) }
            catch { message = "无法读取设置：\(error.localizedDescription)" }
        } else if let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
                  let id = Bundle(url: url)?.bundleIdentifier, id != appID {
            preferences.defaultBrowserID = id
        }
        refresh()
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: configURL, options: .atomic)
            message = "设置已保存"
        } catch { message = "保存失败：\(error.localizedDescription)" }
    }

    func refresh() {
        var seen = Set<String>()
        browsers = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!).compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier, id != appID, seen.insert(id).inserted else { return nil }
            return Browser(id: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), url: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isDefault = ["http", "https"].allSatisfy {
            guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\($0)://example.com")!) else { return false }
            return Bundle(url: url)?.bundleIdentifier == appID
        }
    }

    func addSource() {
        let panel = NSOpenPanel()
        panel.title = "选择来源应用"; panel.prompt = "添加规则"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        guard id != appID else { message = "请选择其他来源应用"; return }
        guard !preferences.rules.contains(where: { $0.sourceID == id }) else { message = "这个应用已有规则，可直接修改"; return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        preferences.rules.append(Rule(sourceID: id, sourceName: name, browserID: preferences.defaultBrowserID))
        save()
    }

    func setAsDefault() {
        save()
        message = "请在系统提示中确认更改"
        Task { @MainActor in
            do {
                for scheme in ["http", "https"] {
                    let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://example.com")!)
                    if current.flatMap({ Bundle(url: $0)?.bundleIdentifier }) != appID {
                        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
                    }
                }
                refresh(); message = isDefault ? "已启用，点击其他应用里的链接即可测试" : "尚未完成默认浏览器设置"
            } catch { refresh(); message = "未更改或未完成设置：\(error.localizedDescription)" }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 32, weight: .semibold)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text("链接分流").font(.system(size: 25, weight: .bold))
                    Text("让不同应用的链接，打开在合适的浏览器里。 ").foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.isDefault ? "已启用" : "待启用").foregroundStyle(store.isDefault ? .green : .secondary)
            }
            HStack {
                Text("将链接分流设为系统默认浏览器后，规则才会生效。")
                Spacer()
                Button(store.isDefault ? "刷新状态" : "设为默认浏览器") {
                    if store.isDefault { store.refresh() } else { store.setAsDefault() }
                }.buttonStyle(.borderedProminent)
            }.padding(14).background(Color.blue.opacity(0.07)).cornerRadius(10)
            HStack {
                Text("默认打开方式").font(.headline)
                Spacer()
                browserPicker(selection: $store.preferences.defaultBrowserID).frame(width: 220)
            }
            Toggle("每次打开链接时，让我选择浏览器", isOn: $store.preferences.askEveryTime)
            Divider()
            HStack {
                Text("按来源应用分配").font(.headline)
                Spacer()
                Button(action: { store.addSource() }) { Label("添加应用", systemImage: "plus") }
            }
            if store.preferences.rules.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "app.connected.to.app.below.fill").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("还没有规则").font(.headline)
                    Text("例如：邮件 → Safari，工作应用 → Chrome").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($store.preferences.rules) { $rule in
                            HStack(spacing: 12) {
                                Toggle("启用", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rule.sourceName).fontWeight(.medium)
                                    Text(rule.sourceID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                browserPicker(selection: $rule.browserID).frame(width: 190)
                                Button { store.preferences.rules.removeAll { $0.id == rule.id }; store.save() } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless).help("删除规则")
                            }.padding(12).background(Color.primary.opacity(0.035)).cornerRadius(8)
                        }
                    }
                }.frame(maxHeight: .infinity)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                Text("最近一次：\(store.recent)").lineLimit(2)
                Text("无法识别来源时使用默认浏览器；应用内置网页需先选择“在外部浏览器打开”。")
            }.font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(store.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("刷新浏览器") { store.refresh() }
            }
        }.padding(26).frame(minWidth: 680, minHeight: 540)
        .onChange(of: store.preferences.defaultBrowserID) { _ in store.save() }
        .onChange(of: store.preferences.askEveryTime) { _ in store.save() }
        .onChange(of: store.preferences.rules) { _ in store.save() }
    }

    func browserPicker(selection: Binding<String>) -> some View {
        Picker("浏览器", selection: selection) {
            if !store.browsers.contains(where: { $0.id == selection.wrappedValue }) {
                Text("不可用：\(selection.wrappedValue)").tag(selection.wrappedValue)
            }
            ForEach(store.browsers) { browser in Text(browser.name).tag(browser.id) }
        }.labelsHidden()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var window: NSWindow?
    var status: NSStatusItem?
    var receivedURL = false
    var queue: [(URL, String?)] = []
    var choosing = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "链接分流")
        let menu = NSMenu()
        let settings = NSMenuItem(title: "链接分流设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出链接分流", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); item.menu = menu; status = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if !self.receivedURL && !CommandLine.arguments.contains("--background") { self.showSettings() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }

    @objc func showSettings() {
        store.refresh()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "链接分流 · BrowserRouter"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store)); w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    @objc func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        receivedURL = true
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else { return }
        let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        let source = pid.flatMap { NSRunningApplication(processIdentifier: $0) }?.bundleIdentifier
        // Use only the sender provided by macOS; a foreground app guess can route to the wrong browser.
        queue.append((url, source)); processQueue()
    }

    func processQueue() {
        guard !choosing, !queue.isEmpty else { return }
        let (url, source) = queue.removeFirst()
        let decision = route(url: url, sourceID: source, preferences: store.preferences, selfID: appID)
        switch decision {
        case .reject: store.message = "仅支持有效的 HTTP / HTTPS 网页链接"
        case .ask: chooseBrowser(url, source: source)
        case .browser(let id):
            if let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
               Bundle(url: application)?.bundleIdentifier != appID {
                open(url, in: application, source: source)
            } else {
                store.message = "目标浏览器不可用，请重新选择"; chooseBrowser(url, source: source)
            }
        }
        if !queue.isEmpty { DispatchQueue.main.async { self.processQueue() } }
    }

    func chooseBrowser(_ url: URL, source: String?) {
        choosing = true; defer { choosing = false }
        store.refresh()
        guard !store.browsers.isEmpty else { store.message = "未找到浏览器，请安装浏览器后重试"; showSettings(); return }
        let alert = NSAlert(); alert.messageText = "用哪个浏览器打开？"
        alert.informativeText = "网站：\(url.host ?? "")\n来源：\(source ?? "无法识别")"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        picker.addItems(withTitles: store.browsers.map(\.name)); alert.accessoryView = picker
        alert.addButton(withTitle: "打开"); alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            open(url, in: store.browsers[picker.indexOfSelectedItem].url, source: source)
        }
    }

    func open(_ url: URL, in application: URL, source: String?) {
        let name = FileManager.default.displayName(atPath: application.path).replacingOccurrences(of: ".app", with: "")
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error = error { self.store.message = "打开失败：\(error.localizedDescription)"; self.showSettings() }
                else { self.store.recent = "\(source ?? "未知来源") → \(name) · \(url.host ?? "")" }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

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
    let configuration: ConfigurationFile
    @Published var recoveryNotice: String?
    @Published var failures: [FailedDelivery] = []
    @Published var activeDeliveryID: UUID?
    @Published var recentRequest: LinkRequest?
    @Published var recentReason = "尚未匹配规则"
    @Published var recentTarget = "—"
    var retryLink: ((UUID, Bool) -> Void)?
    var dismissLink: ((UUID) -> Void)?
    var canSave: Bool { configuration.writeBlock == nil }

    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--config"), CommandLine.arguments.count > i + 1 {
            configURL = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        } else {
            configURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BrowserRouter/preferences.json")
        }
        configuration = ConfigurationFile(url: configURL)
        let existed = FileManager.default.fileExists(atPath: configURL.path)
        let loaded = configuration.load()
        preferences = loaded.preferences
        recoveryNotice = loaded.notice
        if !existed, let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
           let id = Bundle(url: url)?.bundleIdentifier, id != appID {
            preferences.defaultBrowserID = id
        }
        refresh()
    }

    func save() {
        do {
            try configuration.save(preferences)
            message = "设置已保存"
        } catch { message = "保存失败：\(error.localizedDescription)" }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "导入设置（当前配置会先备份）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try configuration.importPreferences(from: url)
            preferences = imported
            recoveryNotice = "已导入设置，导入前的配置已备份（如原文件存在）。"
            message = "导入成功"
        } catch { message = "导入失败，当前设置未替换：\(error.localizedDescription)" }
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "BrowserRouter-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try configuration.export(preferences, to: url)
            message = "设置已导出"
        } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    func copyFailedLink(_ failure: FailedDelivery) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(failure.request.url.absoluteString, forType: .string)
        message = "完整链接已复制"
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
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        addSource(id: id, name: name)
    }

    func addSource(id: String, name: String) {
        guard canSave else { message = configuration.writeBlock ?? "设置只读"; return }
        guard id != appID else { message = "请选择其他来源应用"; return }
        guard !preferences.rules.contains(where: { $0.sourceID == id }) else { message = "这个应用已有规则，可直接修改"; return }
        preferences.rules.append(Rule(sourceID: id, sourceName: name, browserID: preferences.defaultBrowserID))
        save()
    }

    func setAsDefault() {
        guard canSave else { message = configuration.writeBlock ?? "设置只读"; return }
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
        VStack(alignment: .leading, spacing: 14) {
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
            if let notice = store.recoveryNotice {
                VStack(alignment: .leading, spacing: 4) {
                    Text("配置恢复提示").font(.headline)
                    Text(notice).font(.caption).textSelection(.enabled)
                    Button("打开配置文件夹") {
                        NSWorkspace.shared.open(store.configURL.deletingLastPathComponent())
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1)).cornerRadius(8)
            }
            HStack {
                Text("默认打开方式").font(.headline)
                Spacer()
                browserPicker(selection: $store.preferences.defaultBrowserID).frame(width: 220)
            }
            Toggle("每次打开链接时，让我选择浏览器", isOn: $store.preferences.askEveryTime).disabled(!store.canSave)
            Divider()
            HStack {
                Text("按来源应用分配").font(.headline)
                Spacer()
                Button(action: { store.addSource() }) { Label("添加应用", systemImage: "plus") }.disabled(!store.canSave)
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
                                Toggle("启用", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox).disabled(!store.canSave)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rule.sourceName).fontWeight(.medium)
                                    Text(rule.sourceID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                browserPicker(selection: $rule.browserID).frame(width: 190)
                                Button { store.preferences.rules.removeAll { $0.id == rule.id }; store.save() } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless).help("删除规则").disabled(!store.canSave)
                            }.padding(12).background(Color.primary.opacity(0.035)).cornerRadius(8)
                        }
                    }
                }.frame(maxHeight: .infinity)
            }
            if !store.failures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未打开的链接（\(store.failures.count)）").font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(store.failures) { failure in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(failure.request.url.host ?? "网页链接").fontWeight(.medium)
                                    Text(failure.message).font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        Button("重试") { store.retryLink?(failure.id, false) }
                                        Button("换浏览器") { store.retryLink?(failure.id, true) }
                                        Button("复制链接") { store.copyFailedLink(failure) }
                                        Spacer()
                                        Button("移除") { store.dismissLink?(failure.id) }
                                    }.disabled(store.activeDeliveryID == failure.id)
                                }
                            }
                        }
                    }.frame(maxHeight: 140)
                    Text("失败链接仅保留在本次运行中，退出应用后清除。").font(.caption).foregroundStyle(.secondary)
                }.padding(10).background(Color.orange.opacity(0.06)).cornerRadius(8)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("最近一次来源与规则").fontWeight(.semibold)
                if let request = store.recentRequest {
                    HStack {
                        Text("来源：\(request.sourceName ?? request.sourceID ?? "无法识别")")
                        Spacer()
                        if let id = request.sourceID, id != appID {
                            Button("从此来源添加规则") { store.addSource(id: id, name: request.sourceName ?? id) }
                                .disabled(!store.canSave || store.preferences.rules.contains { $0.sourceID == id })
                        }
                    }
                    if let id = request.sourceID { Text(id).textSelection(.enabled) }
                    Text("规则：\(store.recentReason)")
                    Text("目标：\(store.recentTarget)")
                }
                Text("最近成功：\(store.recent)").lineLimit(2)
                Text("来源可能是辅助进程；应用内置网页需先选择“在外部浏览器打开”。")
            }.font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(store.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("导入设置") { store.importSettings() }.disabled(!store.canSave)
                Button("导出设置") { store.exportSettings() }
                Button("刷新浏览器") { store.refresh() }
            }
        }.padding(26).frame(minWidth: 720, minHeight: 680)
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
        }.labelsHidden().disabled(!store.canSave)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var window: NSWindow?
    var status: NSStatusItem?
    var receivedURL = false
    let delivery = DeliveryQueue()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.retryLink = { [weak self] id, choose in
            self?.delivery.retry(id, chooseBrowser: choose)
            self?.processQueue()
        }
        store.dismissLink = { [weak self] id in
            self?.delivery.dismiss(id)
            self?.syncDelivery()
        }
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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 820),
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
        let sourceApp = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        // Only the actual sender is trusted; never guess using the foreground app.
        delivery.enqueue(LinkRequest(url: url, sourceID: sourceApp?.bundleIdentifier, sourceName: sourceApp?.localizedName))
        processQueue()
    }

    func syncDelivery() {
        store.failures = delivery.failures
        store.activeDeliveryID = delivery.active?.id
    }

    func advance() {
        syncDelivery()
        DispatchQueue.main.async { self.processQueue() }
    }

    func processQueue() {
        guard let request = delivery.next() else { return }
        syncDelivery()
        store.recentRequest = request
        store.recentReason = routingExplanation(sourceID: request.sourceID, preferences: store.preferences, forceChoice: request.forceChoice)
        let decision = request.forceChoice ? Route.ask : route(url: request.url, sourceID: request.sourceID, preferences: store.preferences, selfID: appID)
        switch decision {
        case .reject:
            store.message = "仅支持有效的 HTTP / HTTPS 网页链接"
            store.recentTarget = "已拒绝：无效网页链接"
            delivery.complete(request.id); advance()
        case .ask:
            store.recentTarget = "等待选择浏览器"
            chooseBrowser(request)
        case .browser(let id):
            store.recentTarget = id
            if let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
               Bundle(url: application)?.bundleIdentifier != appID {
                open(request, in: application)
            } else {
                store.message = "目标浏览器不可用，请重新选择"
                store.recentTarget = "\(id)（不可用）"
                // Record first: cancelling the chooser must not lose the original URL.
                delivery.fail(request.id, message: "目标浏览器不可用：\(id)")
                syncDelivery(); showSettings(); advance()
            }
        }
    }

    func chooseBrowser(_ request: LinkRequest) {
        store.refresh()
        let choices = store.browsers // Keep the picker and targets in the same stable order.
        guard !choices.isEmpty else {
            delivery.fail(request.id, message: "未找到浏览器，请安装浏览器后重试")
            syncDelivery(); showSettings(); advance(); return
        }
        let alert = NSAlert(); alert.messageText = "用哪个浏览器打开？"
        alert.informativeText = "网站：\(request.url.host ?? "")\n来源：\(request.sourceName ?? request.sourceID ?? "无法识别")"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        picker.addItems(withTitles: choices.map(\.name)); alert.accessoryView = picker
        alert.addButton(withTitle: "打开"); alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            open(request, in: choices[picker.indexOfSelectedItem].url)
        } else {
            store.recentTarget = "已取消选择"
            delivery.cancel(request.id); advance()
        }
    }

    func open(_ request: LinkRequest, in application: URL) {
        let name = FileManager.default.displayName(atPath: application.path).replacingOccurrences(of: ".app", with: "")
        store.recentTarget = "\(name)（正在打开）"
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        NSWorkspace.shared.open([request.url], withApplicationAt: application, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    self.delivery.fail(request.id, message: "\(name)：\(error.localizedDescription)")
                    self.store.recentTarget = "\(name)（打开失败）"
                    self.syncDelivery(); self.showSettings()
                } else {
                    self.delivery.complete(request.id)
                    self.store.recentTarget = name
                    self.store.message = "链接已打开"
                    self.store.recent = "\(request.sourceName ?? request.sourceID ?? "未知来源") → \(name) · \(request.url.host ?? "")"
                }
                self.advance()
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

import AppKit
import SpriteKit
import Security

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private var window: NSWindow!
    private var monitor = ProcessMonitor()
    private var sync = WorkspaceSync()
    private var statusItem: NSStatusItem!
    private var allApps: [ProcessRecord] = []
    private var remoteDevices: [String: DeviceSnapshot] = [:]
    private var selectedDepartment: Department?
    private var selectedDevice: String = "全部设备"
    private var deviceIDsByTitle: [String: String] = [:]
    private let table = NSTableView()
    private let office = SKView()
    private let scene = OfficeScene(size: CGSize(width: 900, height: 420))
    private let devicePicker = NSPopUpButton()
    private let departmentPicker = NSPopUpButton()
    private let pairingField = NSTextField(string: "")
    private let syncLabel = NSTextField(labelWithString: "局域网同步未开启")
    private var filteredApps: [ProcessRecord] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow(); buildMenuBar()
        monitor.onChange = { [weak self] apps in DispatchQueue.main.async { self?.allApps = apps; self?.refresh() } }
        sync.onRemoteMessage = { [weak self] message in DispatchQueue.main.async { self?.applyRemote(message) } }
        sync.onStatus = { [weak self] status in DispatchQueue.main.async { self?.syncLabel.stringValue = status } }
        monitor.start()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) { monitor.stop(); sync.stop() }
    func numberOfRows(in tableView: NSTableView) -> Int { filteredApps.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredApps.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let app = filteredApps[row]
        let text = NSTextField(labelWithString: "")
        text.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        text.stringValue = switch id {
            case "app": (app.isFrontmost ? "● " : "  ") + app.name
            case "department": app.department.rawValue
            case "cpu": app.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
            case "memory": app.memoryBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "—"
            case "device": app.deviceID
            default: ""
        }
        text.textColor = app.isFrontmost ? NSColor.systemYellow : NSColor.labelColor
        return text
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, table.selectedRow < filteredApps.count else { departmentPicker.isEnabled = false; return }
        departmentPicker.isEnabled = true; departmentPicker.selectItem(withTitle: filteredApps[table.selectedRow].department.rawValue)
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Pixel Workspace · App 监控办公室"; window.center(); window.minSize = NSSize(width: 920, height: 650)
        let root = NSView(); root.translatesAutoresizingMaskIntoConstraints = false; window.contentView = root
        let header = NSStackView(); header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 10; header.translatesAutoresizingMaskIntoConstraints = false
        let brand = NSTextField(labelWithString: "▦  PIXEL WORKSPACE"); brand.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        header.addArrangedSubview(brand); header.addArrangedSubview(NSView())
        devicePicker.addItems(withTitles: ["全部设备", "本机"]); deviceIDsByTitle["本机"] = monitor.deviceID; devicePicker.target = self; devicePicker.action = #selector(deviceChanged)
        header.addArrangedSubview(NSTextField(labelWithString: "视图")); header.addArrangedSubview(devicePicker)
        let filter = NSPopUpButton(); filter.addItem(withTitle: "全部部门"); Department.allCases.forEach { filter.addItem(withTitle: $0.rawValue) }; filter.target = self; filter.action = #selector(departmentChanged); header.addArrangedSubview(filter)
        pairingField.placeholderString = "粘贴两台设备相同的配对密钥（至少 16 字符）"; pairingField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        header.addArrangedSubview(pairingField)
        let generateButton = NSButton(title: "生成密钥", target: self, action: #selector(generatePairingCode)); generateButton.bezelStyle = .rounded; header.addArrangedSubview(generateButton)
        let syncButton = NSButton(title: "启用局域网同步", target: self, action: #selector(startSync)); syncButton.bezelStyle = .rounded; header.addArrangedSubview(syncButton)
        syncLabel.font = .systemFont(ofSize: 11); syncLabel.textColor = .secondaryLabelColor; header.addArrangedSubview(syncLabel)

        office.ignoresSiblingOrder = true; office.allowsTransparency = false; office.presentScene(scene); office.wantsLayer = true; office.layer?.cornerRadius = 8
        office.heightAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        let columns: [(String,String,CGFloat)] = [("app","App / 前台",230),("department","部门",110),("cpu","CPU",90),("memory","内存",110),("device","设备",160)]
        for (key,title,width) in columns { let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key)); column.title = title; column.width = width; table.addTableColumn(column) }
        table.delegate = self; table.dataSource = self; table.rowHeight = 23; table.usesAlternatingRowBackgroundColors = true; table.style = .inset; table.selectionHighlightStyle = .regular
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .lineBorder; scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        departmentPicker.addItems(withTitles: Department.allCases.map(\.rawValue)); departmentPicker.isEnabled = false; departmentPicker.target = self; departmentPicker.action = #selector(changeDepartment)
        let controls = NSStackView(views: [NSTextField(labelWithString: "选中 App 部门："), departmentPicker, syncLabel]); controls.orientation = .horizontal; controls.spacing = 12
        let layout = NSStackView(views: [header, office, controls, scroll]); layout.orientation = .vertical; layout.alignment = .leading; layout.spacing = 12; layout.translatesAutoresizingMaskIntoConstraints = false
        for view in [header, office, scroll] { view.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true }
        root.addSubview(layout)
        NSLayoutConstraint.activate([layout.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), layout.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), layout.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), layout.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16), header.heightAnchor.constraint(equalToConstant: 38), controls.heightAnchor.constraint(equalToConstant: 28)])
        window.makeKeyAndOrderFront(nil)
    }
    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "▦"
        let menu = NSMenu(); menu.addItem(withTitle: "打开 Pixel Workspace", action: #selector(showWindow), keyEquivalent: "o"); menu.addItem(.separator()); menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }
    private func refresh() {
        let localName = Host.current().localizedName ?? "本机"
        var merged = allApps
        for snapshot in remoteDevices.values { merged.append(contentsOf: snapshot.apps) }
        devicePicker.removeAllItems(); devicePicker.addItem(withTitle: "全部设备"); devicePicker.addItem(withTitle: localName)
        deviceIDsByTitle = ["本机": monitor.deviceID, localName: monitor.deviceID]
        remoteDevices.values.sorted { $0.deviceName < $1.deviceName }.forEach {
            let title = "\($0.deviceName) · \($0.deviceID.prefix(6))"; devicePicker.addItem(withTitle: title); deviceIDsByTitle[title] = $0.deviceID
        }
        if devicePicker.itemTitles.contains(selectedDevice) { devicePicker.selectItem(withTitle: selectedDevice) } else { selectedDevice = "全部设备" }
        if selectedDevice != "全部设备", let deviceID = deviceIDsByTitle[selectedDevice] { merged = merged.filter { $0.deviceID == deviceID } }
        if let selectedDepartment { merged = merged.filter { $0.department == selectedDepartment } }
        filteredApps = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        table.reloadData(); scene.render(filteredApps, device: selectedDevice)
        if pairingField.stringValue.nilIfBlank != nil {
            sync.publish(DeviceSnapshot(deviceID: monitor.deviceID, deviceName: localName, capturedAt: Date(), apps: allApps))
        }
    }
    private func applyRemote(_ message: WorkspaceMessage) {
        switch message {
        case .snapshot(let snapshot): remoteDevices[snapshot.deviceID] = snapshot
        case .upsert(let record):
            var snapshot = remoteDevices[record.deviceID] ?? DeviceSnapshot(deviceID: record.deviceID, deviceName: record.deviceID, capturedAt: Date(), apps: [])
            snapshot.apps.removeAll { $0.id == record.id }; snapshot.apps.append(record); snapshot.capturedAt = Date(); remoteDevices[record.deviceID] = snapshot
        case .remove(let deviceID, let pid, let bundleID):
            guard var snapshot = remoteDevices[deviceID] else { return }
            snapshot.apps.removeAll { $0.pid == pid && $0.bundleID == bundleID }; snapshot.capturedAt = Date(); remoteDevices[deviceID] = snapshot
        }
        refresh()
    }
    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func departmentChanged(_ sender: NSPopUpButton) { selectedDepartment = sender.indexOfSelectedItem == 0 ? nil : Department.allCases[sender.indexOfSelectedItem - 1]; refresh() }
    @objc private func deviceChanged() { selectedDevice = devicePicker.titleOfSelectedItem ?? "全部设备"; refresh() }
    @objc private func changeDepartment(_ sender: NSPopUpButton) {
        guard table.selectedRow >= 0, table.selectedRow < filteredApps.count, let department = Department.allCases.first(where: { $0.rawValue == sender.titleOfSelectedItem }) else { return }
        let app = filteredApps[table.selectedRow]; guard app.deviceID == monitor.deviceID else { return }
        monitor.setDepartment(department, for: app.bundleID)
    }
    @objc private func startSync() {
        do { try sync.start(pairingCode: pairingField.stringValue); syncLabel.stringValue = "正在发现配对设备…" }
        catch { syncLabel.stringValue = "配对密钥至少需要 16 个字符" }
    }
    @objc private func generatePairingCode() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        pairingField.stringValue = bytes.map { String(format: "%02x", $0) }.joined()
        syncLabel.stringValue = "请复制密钥到另一台 Mac，再分别启用同步"
    }
}

private extension String { var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self } }

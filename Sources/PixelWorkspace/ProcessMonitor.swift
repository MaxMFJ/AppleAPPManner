import AppKit
import Foundation
import Darwin

final class ProcessMonitor {
    var onChange: (([ProcessRecord]) -> Void)?
    private var timer: Timer?
    private var previousCPU: [Int32: (ticks: UInt64, time: TimeInterval)] = [:]
    private var rules = RuleStore.load()
    let deviceID: String = {
        let key = "pixelworkspace.device-id.v1"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let value = UUID().uuidString.lowercased(); UserDefaults.standard.set(value, forKey: key); return value
    }()

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func stop() { timer?.invalidate(); timer = nil; NSWorkspace.shared.notificationCenter.removeObserver(self) }
    func setDepartment(_ department: Department, for bundleID: String) { rules[bundleID] = department; RuleStore.save(rules); refresh() }
    @objc private func appChanged(_ note: Notification) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refresh() } }

    private func refresh() {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let now = ProcessInfo.processInfo.systemUptime
        var records: [ProcessRecord] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            let bundle = app.bundleIdentifier ?? "pid.\(pid)"
            let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? bundle
            let stats = metrics(pid: pid, now: now)
            records.append(ProcessRecord(bundleID: bundle, name: name, pid: pid,
                department: Classifier.department(for: bundle, name: name, rules: rules),
                isFrontmost: pid == frontPID, cpuPercent: stats.cpu, memoryBytes: stats.memory,
                deviceID: deviceID, updatedAt: Date()))
        }
        let livePIDs = Set(records.map(\.pid))
        previousCPU = previousCPU.filter { livePIDs.contains($0.key) }
        onChange?(records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private func metrics(pid: pid_t, now: TimeInterval) -> (cpu: Double?, memory: UInt64?) {
        var task = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let gotTask = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize)
        var cpu: Double? = nil
        if gotTask == taskSize {
            let ticks = task.pti_total_user + task.pti_total_system
            if let old = previousCPU[pid], now > old.time {
                cpu = max(0, min(100, Double(ticks &- old.ticks) / 1_000_000_000 / (now - old.time) * 100))
            }
            previousCPU[pid] = (ticks, now)
            return (cpu, task.pti_resident_size)
        }
        return (nil, nil) // sandbox/permission limitation: show unavailable, never estimate
    }
}

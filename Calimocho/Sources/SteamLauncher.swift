//
//  SteamLauncher.swift
//  Calimocho
//
//  Launches and manages Steam.exe inside the Wine bottle
//

import Foundation
import AppKit

class SteamLauncher {
    private let bottleManager: BottleManager
    private var steamProcess: Process?
    
    init(bottleManager: BottleManager) {
        self.bottleManager = bottleManager
    }
    
    func isSteamRunning() -> Bool {
        // Check if steam.exe process exists
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "steam.exe"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        try? task.run()
        task.waitUntilExit()
        
        return task.terminationStatus == 0
    }
    
    func launchSteam() {
        guard bottleManager.steamBottleExists() else {
            print("Cannot launch Steam: bottle does not exist")
            showError("Steam Not Installed", message: "Please run the first-time setup to install Steam.")
            return
        }
        
        // Don't launch if already running (SPECS A2.7)
        if isSteamRunning() {
            print("Steam is already running, bringing to front instead of launching duplicate")
            bringToFront()
            return
        }
        
        // Path to Steam.exe in the bottle
        let steamExe = "C:\\Program Files (x86)\\Steam\\steam.exe"
        
        let enginePath = bottleManager.getEnginePath()
        let wineBinary = enginePath.appendingPathComponent("bin/calimocho-wine")
        
        steamProcess = Process()
        steamProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        steamProcess?.arguments = [
            "-x86_64",
            wineBinary.path,
            steamExe
        ]
        steamProcess?.environment = bottleManager.getWineEnvironment()
        
        // Log steam output
        let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Calimocho")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let logFileName = "wine-STEAM-\(dateFormatter.string(from: Date())).log"
        let logPath = logDir.appendingPathComponent(logFileName)
        
        // Open or create the log file. FileHandle(forWritingAtPath:) returns nil
        // when the file does not yet exist, so create it first when needed.
        if FileHandle(forWritingAtPath: logPath.path) == nil {
            FileManager.default.createFile(atPath: logPath.path, contents: nil)
        }
        if let logFile = FileHandle(forWritingAtPath: logPath.path) {
            steamProcess?.standardOutput = logFile
            steamProcess?.standardError = logFile
        }
        
        do {
            try steamProcess?.run()
            print("Launched Steam (PID: \(steamProcess?.processIdentifier ?? -1))")
        } catch {
            print("Failed to launch Steam: \(error)")
            showError("Failed to Launch Steam", message: error.localizedDescription)
        }
    }
    
    func bringToFront() {
        // Wine windows don't have a proper NSRunningApplication entry
        // Use wmctrl-like approach: send window manager signal
        // For now, just activate wine process group
        let script = """
        osascript -e 'tell application "System Events" to set frontmost of \
        (first process whose unix id is (do shell script "pgrep -f steam.exe | head -1")) to true'
        """
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
    }
    
    func terminateAllWineProcesses() {
        // Per SPECS A2.5: graceful termination via wineserver -k
        let enginePath = bottleManager.getEnginePath()
        let wineserverBinary = enginePath.appendingPathComponent("bin/wineserver")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = [
            "-x86_64",
            wineserverBinary.path,
            "-k"
        ]
        process.environment = bottleManager.getWineEnvironment()
        
        try? process.run()
        process.waitUntilExit()
        
        // Wait up to 10 seconds for processes to die
        var attempts = 0
        while isSteamRunning() && attempts < 20 {
            Thread.sleep(forTimeInterval: 0.5)
            attempts += 1
        }
        
        if isSteamRunning() {
            print("Warning: Steam processes did not terminate cleanly after 10s")
        }
    }
    
    private func showError(_ title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

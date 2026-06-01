//
//  FirstRunWizardWindow.swift
//  Calimocho
//
//  5-step first-run wizard per SPECS A2.3
//

import SwiftUI
import AppKit
import Darwin

class FirstRunWizardWindow {
    private var window: NSWindow?
    private var onCompleteCallback: ((Bool) -> Void)?
    
    func showWindow(onComplete: @escaping (Bool) -> Void) {
        self.onCompleteCallback = onComplete
        
        let contentView = FirstRunWizardView(
            onComplete: { [weak self] success in
                self?.window?.close()
                self?.onCompleteCallback?(success)
            }
        )
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window?.title = "Welcome to Calimocho"
        window?.contentView = NSHostingView(rootView: contentView)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct FirstRunWizardView: View {
    @State private var currentStep = 0
    @State private var checkOSVersion = false
    @State private var checkAppleSilicon = false
    @State private var checkDiskSpace = false
    @State private var checkNetwork = false
    @State private var isInstalling = false
    @State private var installProgress: Double = 0.0
    @State private var installStatusMessage = ""
    @State private var installError: String?
    @State private var installComplete = false
    
    private var systemCheckPassed: Bool {
        checkOSVersion && checkAppleSilicon && checkDiskSpace && checkNetwork
    }
    
    let onComplete: (Bool) -> Void
    
    var body: some View {
        VStack {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<5) { step in
                    Circle()
                        .fill(step == currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.top, 20)
            
            Spacer()
            
            // Step content
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep()
                case 1:
                    SystemCheckStep(
                        checkOSVersion: $checkOSVersion,
                        checkAppleSilicon: $checkAppleSilicon,
                        checkDiskSpace: $checkDiskSpace,
                        checkNetwork: $checkNetwork
                    )
                case 2:
                    InstallPromptStep()
                case 3:
                    InstallProgressStep(
                        progress: $installProgress,
                        statusMessage: $installStatusMessage,
                        error: $installError
                    )
                case 4:
                    DoneStep()
                default:
                    Text("Unknown step")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            
            Spacer()
            
            // Navigation buttons
            HStack {
                if currentStep > 0 && currentStep < 3 {
                    Button("Back") {
                        currentStep -= 1
                    }
                }
                
                Spacer()
                
                if currentStep < 2 || currentStep == 4 {
                    Button(currentStep == 4 ? "Launch Steam Now" : "Continue") {
                        handleContinue()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled((currentStep == 1 && !systemCheckPassed) || (currentStep == 4 && !installComplete))
                }
                
                if currentStep == 2 {
                    Button("Install Steam") {
                        startInstallation()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInstalling)
                }
                
                if currentStep == 4 {
                    Button("Launch Later") {
                        onComplete(true)
                    }
                }
                
                if currentStep == 0 {
                    Button("Skip Setup") {
                        onComplete(false)
                    }
                }
            }
            .padding()
        }
        .frame(width: 540, height: 400)
        .onAppear {
            if currentStep == 1 {
                performSystemCheck()
            }
        }
    }
    
    private func handleContinue() {
        if currentStep == 4 {
            // Launch Steam Now was clicked.
            // launchSteam() fires onComplete(true) after a short delay —
            // do not call it here as well or completion runs twice.
            launchSteam()
        } else {
            currentStep += 1
            if currentStep == 1 {
                performSystemCheck()
            }
        }
    }
    
    private func performSystemCheck() {
        // Implement system check per SPECS A2.3 step 2
        DispatchQueue.global().async {
            // Check 1: arm64 architecture
            var size = 0
            sysctlbyname("hw.machine", nil, &size, nil, 0)
            var machine = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.machine", &machine, &size, nil, 0)
            let arch = String(cString: machine)
            let isAppleSilicon = arch.contains("arm64")
            
            // Check 2: macOS >= 15
            let osVersion = ProcessInfo.processInfo.operatingSystemVersion
            let isOSVersionOK = osVersion.majorVersion >= 15
            
            // Check 3: >= 20 GB free
            var isDiskOK = false
            if let path = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first {
                if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
                   let freeSize = attrs[.systemFreeSize] as? Int64 {
                    let freeGB = Double(freeSize) / 1_000_000_000.0
                    isDiskOK = freeGB >= 20.0
                }
            }
            
            // Check 4: Network reachable — try to resolve DNS
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/host")
            task.arguments = ["steampowered.com"]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            try? task.run()
            task.waitUntilExit()
            let isNetworkOK = task.terminationStatus == 0
            
            DispatchQueue.main.async {
                checkAppleSilicon = isAppleSilicon
                checkOSVersion = isOSVersionOK
                checkDiskSpace = isDiskOK
                checkNetwork = isNetworkOK
            }
        }
    }
    
    private func logToFile(_ message: String) {
        let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Calimocho")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let logFile = logDir.appendingPathComponent("calimocho-\(dateFormatter.string(from: Date())).log")
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(logLine.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? logLine.write(to: logFile, atomically: true, encoding: .utf8)
        }
        
        print(logLine, terminator: "")
    }
    
    private func startInstallation() {
        currentStep = 3
        isInstalling = true
        installProgress = 0.0
        installStatusMessage = "Creating Steam bottle..."
        logToFile("Starting Steam installation")
        
        DispatchQueue.global().async {
            do {
                // Step 1: Create bottle (30% progress)
                self.logToFile("Step 1: Creating Steam bottle")
                let bottleManager = BottleManager()
                try bottleManager.createSteamBottle()
                self.logToFile("Bottle created successfully")
                
                DispatchQueue.main.async {
                    installProgress = 0.3
                    installStatusMessage = "Downloading SteamSetup.exe..."
                }
                
                // Step 2: Download SteamSetup.exe (60% progress)
                self.logToFile("Step 2: Downloading SteamSetup.exe")
                let steamSetupURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!
                let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("SteamSetup.exe")
                
                self.logToFile("Downloading from \(steamSetupURL.absoluteString)")
                let data = try Data(contentsOf: steamSetupURL)
                self.logToFile("Downloaded \(data.count) bytes")
                
                try data.write(to: tempFile)
                self.logToFile("Wrote installer to \(tempFile.path)")
                
                DispatchQueue.main.async {
                    installProgress = 0.6
                    installStatusMessage = "Installing Steam..."
                }
                
                // Step 3: Run installer (90% progress)
                self.logToFile("Step 3: Running Steam installer")
                let enginePath = bottleManager.getEnginePath()
                let wineBinary = enginePath.appendingPathComponent("bin/calimocho-wine")
                self.logToFile("Wine binary: \(wineBinary.path)")
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
                process.arguments = [
                    "-x86_64",
                    wineBinary.path,
                    tempFile.path,
                    "/S"  // Silent install
                ]
                process.environment = bottleManager.getWineEnvironment()
                
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                
                self.logToFile("Starting installer process")
                try process.run()
                process.waitUntilExit()
                
                let exitCode = process.terminationStatus
                self.logToFile("Installer exited with code \(exitCode)")
                
                if let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), !output.isEmpty {
                    self.logToFile("Installer stdout: \(output)")
                }
                
                if let errorOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), !errorOutput.isEmpty {
                    self.logToFile("Installer stderr: \(errorOutput)")
                }
                
                guard exitCode == 0 else {
                    throw NSError(domain: "com.dragoshont.calimocho", code: Int(exitCode), 
                                  userInfo: [NSLocalizedDescriptionKey: "Steam installer failed with exit code \(exitCode)"])
                }
                
                self.logToFile("Installation successful")
                
                DispatchQueue.main.async {
                    installProgress = 1.0
                    installStatusMessage = "Installation complete!"
                }
                
                // Wait a moment then move to done step
                Thread.sleep(forTimeInterval: 1.0)
                DispatchQueue.main.async {
                    currentStep = 4
                    installComplete = true
                }
                
            } catch {
                let errorMsg = "Installation failed: \(error.localizedDescription)"
                self.logToFile("ERROR: \(errorMsg)")
                DispatchQueue.main.async {
                    installError = errorMsg
                    isInstalling = false
                    installComplete = false
                }
            }
        }
    }
    
    private func launchSteam() {
        let bottleManager = BottleManager()
        let launcher = SteamLauncher(bottleManager: bottleManager)
        launcher.launchSteam()
        
        // Give Steam a moment to start, then close the wizard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onComplete(true)
        }
    }
}

// MARK: - Wizard Step Views

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🍷")
                .font(.system(size: 60))
            
            Text("Welcome to Calimocho")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Calimocho lets you run Steam for Windows on your Mac, so you can play Windows-only games like Subnautica 2.")
                .multilineTextAlignment(.center)
            
            Text("It uses CodeWeavers' Wine engine, Apple's Game Porting Toolkit, and our own bottle layout to do it.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Text("This wizard takes about 5 minutes.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: "info.circle")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calimocho is free, non-commercial. If you can afford it, please consider buying CrossOver instead — they fund the Wine engine this all builds on.")
                        .font(.caption)
                    Link("Learn more about CrossOver", destination: URL(string: "https://www.codeweavers.com/crossover")!)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct SystemCheckStep: View {
    @Binding var checkOSVersion: Bool
    @Binding var checkAppleSilicon: Bool
    @Binding var checkDiskSpace: Bool
    @Binding var checkNetwork: Bool
    
    private var allPassed: Bool {
        checkOSVersion && checkAppleSilicon && checkDiskSpace && checkNetwork
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("System Check")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                CheckItem(label: "macOS 15 or later", passed: $checkOSVersion)
                CheckItem(label: "Apple Silicon", passed: $checkAppleSilicon)
                CheckItem(label: "At least 20 GB free", passed: $checkDiskSpace)
                CheckItem(label: "Network reachable", passed: $checkNetwork)
            }
            
            if allPassed {
                Text("✓ Everything looks good.")
                    .foregroundColor(.green)
                    .fontWeight(.bold)
            } else {
                Text("⚠ System requirements not met")
                    .foregroundColor(.orange)
            }
        }
    }
}

struct CheckItem: View {
    let label: String
    @Binding var passed: Bool
    
    var body: some View {
        HStack {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(passed ? .green : .gray)
            Text(label)
        }
    }
}

struct InstallPromptStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Install Steam")
                .font(.title)
                .fontWeight(.bold)
            
            Text("We'll now download and install Steam for Windows.")
                .multilineTextAlignment(.center)
            
            Text("This will:")
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                BulletPoint(text: "Create a Windows environment (~500 MB)")
                BulletPoint(text: "Download SteamSetup.exe (~3 MB)")
                BulletPoint(text: "Install Steam (~800 MB)")
            }
            
            Text("Total: about 1.3 GB, takes 3-10 minutes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

struct InstallProgressStep: View {
    @Binding var progress: Double
    @Binding var statusMessage: String
    @Binding var error: String?
    
    var body: some View {
        VStack(spacing: 20) {
            if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    
                    Text("Installation Failed")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Installing...")
                    .font(.title)
                    .fontWeight(.bold)
                
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 400)
                
                Text(statusMessage)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DoneStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("✓")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Setup Complete!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Steam is installed and ready to use.")
                .multilineTextAlignment(.center)
            
            Text("You can launch Steam now, or close this window and use the menubar icon (🍷) anytime.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
}

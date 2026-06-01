//
//  CalimochoApp.swift
//  Calimocho
//
//  Phase 2: SwiftUI menubar app that wraps the Wine 11 engine
//

import SwiftUI
import AppKit

@main
struct CalimochoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No WindowGroup - this is a menubar-only app
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var bottleManager: BottleManager?
    var steamLauncher: SteamLauncher?
    var wizardWindow: FirstRunWizardWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menubar-only app)
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize managers
        bottleManager = BottleManager()
        steamLauncher = SteamLauncher(bottleManager: bottleManager!)
        
        // Set up menubar item
        setupMenuBar()
        
        // Check if first run
        if !bottleManager!.steamBottleExists() {
            showFirstRunWizard()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean shutdown of all Wine processes
        steamLauncher?.terminateAllWineProcesses()
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Use 🍷 emoji as icon for now (will be replaced with proper icon asset)
            button.title = "🍷"
            button.toolTip = "Calimocho"
        }
        
        updateMenu()
    }
    
    func updateMenu() {
        let menu = NSMenu()
        
        // App version header
        let versionItem = NSMenuItem(title: "🍷 Calimocho v0.5.0", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Main action - changes based on state
        if !bottleManager!.steamBottleExists() {
            let item = NSMenuItem(title: "▶ Install Steam", action: #selector(installSteam), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else if steamLauncher!.isSteamRunning() {
            let item = NSMenuItem(title: "Bring Steam to Front", action: #selector(bringSteamToFront), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "▶ Open Steam for Windows", action: #selector(launchSteam), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Standard items
        let aboutItem = NSMenuItem(title: "About Calimocho", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "Quit Calimocho", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc func installSteam() {
        showFirstRunWizard()
    }
    
    @objc func launchSteam() {
        steamLauncher?.launchSteam()
        updateMenu()
    }
    
    @objc func bringSteamToFront() {
        steamLauncher?.bringToFront()
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "About Calimocho"
        alert.informativeText = """
        Calimocho v0.5.0
        
        Run Windows games on Apple Silicon Macs using Wine 11 + Apple's Game Porting Toolkit.
        
        Built with:
        • Wine 11.0 (CodeWeavers LGPL source)
        • Apple Game Porting Toolkit 3.0
        • MoltenVK (Apache 2.0)
        
        This is free, non-commercial software. If you need support, please buy CrossOver instead — they fund the Wine development this builds on.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Learn About CrossOver")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://www.codeweavers.com/crossover")!)
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func showFirstRunWizard() {
        wizardWindow = FirstRunWizardWindow()
        wizardWindow?.showWindow(onComplete: { [weak self] success in
            self?.wizardWindow = nil
            if success {
                self?.updateMenu()
            }
        })
    }
}

//
//  BottleManager.swift
//  Calimocho
//
//  Manages Wine prefix (bottle) creation, configuration, and validation
//

import Foundation

class BottleManager {
    let bottlesDir: URL
    let steamBottlePath: URL
    
    init() {
        // Per SPECS A2.8: all state under ~/Library/Application Support/Calimocho/
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        bottlesDir = appSupport.appendingPathComponent("Calimocho/Bottles")
        steamBottlePath = bottlesDir.appendingPathComponent("STEAM")
        
        // Ensure bottles directory exists
        try? FileManager.default.createDirectory(at: bottlesDir, withIntermediateDirectories: true)
    }
    
    func steamBottleExists() -> Bool {
        let systemReg = steamBottlePath.appendingPathComponent("system.reg")
        return FileManager.default.fileExists(atPath: systemReg.path)
    }
    
    func createSteamBottle() throws {
        guard !steamBottleExists() else {
            print("Steam bottle already exists at \(steamBottlePath.path)")
            return
        }
        
        // Create bottle directory
        try FileManager.default.createDirectory(at: steamBottlePath, withIntermediateDirectories: true)
        
        // Run wineboot --init to initialize the prefix
        let enginePath = getEnginePath()
        let wineBinary = enginePath.appendingPathComponent("bin/calimocho-wine")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = [
            "-x86_64",  // Force Rosetta 2
            wineBinary.path,
            "wineboot",
            "--init"
        ]
        process.environment = getWineEnvironment()
        
        // Capture output for logging
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw BottleError.winebootFailed(process.terminationStatus)
        }
        
        // Create config.json
        let config = BottleConfig(
            wineVersion: "11.0",
            windowsVersion: "win11",
            dllOverrides: ["mscoree": "n", "mshtml": "n"],
            createdAt: Date()
        )
        try saveConfig(config)
        
        print("Created Steam bottle at \(steamBottlePath.path)")
    }
    
    func getEnginePath() -> URL {
        // Per ARCHITECTURE.md: engine is at Calimocho.app/Contents/Resources/Engine
        let bundle = Bundle.main
        if let enginePath = bundle.url(forResource: "Engine", withExtension: nil) {
            return enginePath
        }
        
        // Fallback for development: check repo out/engine/
        let repoPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("out/engine")
        
        if FileManager.default.fileExists(atPath: repoPath.path) {
            return repoPath
        }
        
        fatalError("Engine not found. Expected at \(bundle.bundlePath)/Contents/Resources/Engine or \(repoPath.path)")
    }
    
    func getWineEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = steamBottlePath.path
        // Do NOT set WINEDLLOVERRIDES here. The calimocho-wine launcher script
        // owns the full override string (mscoree,mshtml=;d3d11,dxgi=n) using
        // ${VAR-default} syntax, which only substitutes when the variable is
        // unset. Setting it here would suppress the d3d11,dxgi=n DXVK redirect
        // and reintroduce the CEF GPU subprocess crashes.
        // See docs/ADR/0013-cw-hack-22434-d3dshared-env.md for root-cause details.
        // WINEDEBUG: allow the user's environment to take precedence.
        if env["WINEDEBUG"] == nil {
            env["WINEDEBUG"] = "err-all,fixme-all"
        }
        
        return env
    }
    
    func saveConfig(_ config: BottleConfig) throws {
        let configPath = steamBottlePath.appendingPathComponent("config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configPath)
    }
    
    func loadConfig() -> BottleConfig? {
        let configPath = steamBottlePath.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configPath) else {
            return nil
        }
        return try? JSONDecoder().decode(BottleConfig.self, from: data)
    }
}

struct BottleConfig: Codable {
    let wineVersion: String
    let windowsVersion: String
    let dllOverrides: [String: String]
    let createdAt: Date
}

enum BottleError: Error {
    case winebootFailed(Int32)
    case engineNotFound
}

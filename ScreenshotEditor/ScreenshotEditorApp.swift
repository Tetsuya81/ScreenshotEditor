//
//  ScreenshotEditorApp.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import SwiftUI

@main
struct ScreenshotEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var captureViewModel = CaptureViewModel()
    
    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .environmentObject(captureViewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        // メニューバーの項目を追加
        MenuBarExtra("Screenshot Editor", systemImage: "camera.viewfinder") {
            VStack(spacing: 8) {
                Button("全画面撮影") {
                    captureViewModel.captureMode = .fullScreen
                    captureViewModel.prepareCapture()
                }
                
                Button("範囲選択撮影") {
                    captureViewModel.captureMode = .selection
                    captureViewModel.prepareCapture()
                }
                
                Divider()
                
                Button("終了") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // ドックアイコンを非表示にする
    func applicationDidFinishLaunching(_ notification: Notification) {
        // ドックアイコンの表示/非表示を制御
        NSApp.setActivationPolicy(.accessory)
        
        // スクリーンショット権限を確認
        checkScreenCapturePermission()
    }
    
    private func checkScreenCapturePermission() {
        let screenCaptureManager = ScreenCaptureManager.shared
        screenCaptureManager.checkPermission { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.requestScreenCapturePermission()
                }
            }
        }
    }
    
    private func requestScreenCapturePermission() {
        let alert = NSAlert()
        alert.messageText = "スクリーンショット権限が必要です"
        alert.informativeText = "Screenshot Editorがスクリーンショットを撮影するには、スクリーン録画の権限が必要です。システム環境設定から権限を許可してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "設定を開く")
        alert.addButton(withTitle: "後で")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}

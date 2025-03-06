//
//  CaptureViewModel.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import Foundation
import SwiftUI
import Combine

class CaptureViewModel: ObservableObject {
    @Published var captureMode: CaptureMode = .fullScreen
    @Published var capturedImage: NSImage?
    @Published var isCapturing = false
    @Published var isEditing = false
    @Published var showCaptureOverlay = false
    @Published var showEditor = false
    @Published var errorMessage: String?
    
    private let screenCaptureManager = ScreenCaptureManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // スクリーンショット完了時の処理を設定
        screenCaptureManager.captureComplete
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isCapturing = false
                    
                    if case .failure(let error) = completion {
                        self.errorMessage = "スクリーンショットの取得に失敗しました: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] image in
                    guard let self = self else { return }
                    self.capturedImage = image
                    self.isEditing = true
                    self.showEditor = true
                    self.isCapturing = false
                    self.showCaptureOverlay = false
                }
            )
            .store(in: &cancellables)
    }
    
    func prepareCapture() {
        // スクリーンショット前の準備
        isCapturing = true
        errorMessage = nil
        capturedImage = nil
        
        // アプリを一時的に隠す処理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.showCaptureOverlay = true
            
            // モードに応じたキャプチャ処理
            Task {
                switch self.captureMode {
                case .fullScreen:
                    await self.captureFullScreen()
                case .selection:
                    await self.captureSelection()
                }
            }
        }
    }
    
    func captureFullScreen() async {
        // ユーザーがスクリーンショットを取るためのカウントダウン
        DispatchQueue.main.async {
            // カーソルを変更してユーザーに準備を促す
            NSCursor.crosshair.push()
        }
        
        // ユーザーがクリックするまで待機
        await waitForUserClick()
        
        // カーソルを元に戻す
        DispatchQueue.main.async {
            NSCursor.pop()
        }
        
        // スクリーンショット実行
        await screenCaptureManager.captureFullScreen()
    }
    
    func captureSelection() async {
        await screenCaptureManager.captureSelection()
    }
    
    private func waitForUserClick() async {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { event in
                    NSEvent.removeMonitor(eventMonitor)
                    continuation.resume()
                }
                
                // ESCキーでキャンセルできるようにする
                let keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
                    if event.keyCode == 53 { // ESCキー
                        NSEvent.removeMonitor(eventMonitor)
                        NSEvent.removeMonitor(keyEventMonitor)
                        self.isCapturing = false
                        self.showCaptureOverlay = false
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func cancelCapture() {
        isCapturing = false
        showCaptureOverlay = false
        screenCaptureManager.stopCapture()
    }
    
    func exitEditor() {
        isEditing = false
        showEditor = false
        capturedImage = nil
    }
    
    func saveToClipboard(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
    
    func saveToFile(_ image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "スクリーンショットを保存"
        savePanel.message = "スクリーンショットの保存先を選択してください"
        savePanel.nameFieldLabel = "ファイル名:"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        savePanel.nameFieldStringValue = "Screenshot-\(dateFormatter.string(from: Date()))"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                if let pngData = image.pngData() {
                    do {
                        try pngData.write(to: url)
                    } catch {
                        self.errorMessage = "保存に失敗しました: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

// NSImageの拡張
extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

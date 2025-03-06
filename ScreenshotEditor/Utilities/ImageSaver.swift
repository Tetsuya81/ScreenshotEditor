//
//  ImageSaver.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// スクリーンショットの保存先
enum SaveDestination {
    case file(URL)
    case clipboard
}

// 保存形式
enum ImageFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"
    case tiff = "TIFF"
    
    var id: String { self.rawValue }
    
    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        }
    }
    
    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        }
    }
    
    func data(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        switch self {
        case .png:
            return bitmapImage.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        case .tiff:
            return bitmapImage.representation(using: .tiff, properties: [:])
        }
    }
}

class ImageSaver: NSObject {
    // シングルトンインスタンス
    static let shared = ImageSaver()
    
    private override init() {}
    
    // クリップボードに保存
    func saveToClipboard(_ image: NSImage) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([image])
    }
    
    // ファイルに保存（ダイアログ表示）
    func saveToFile(_ image: NSImage, format: ImageFormat = .png, initialFileName: String? = nil) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.contentType]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "スクリーンショットを保存"
        savePanel.message = "スクリーンショットの保存先を選択してください"
        savePanel.nameFieldLabel = "ファイル名:"
        
        // デフォルトのファイル名を設定
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let defaultFileName = initialFileName ?? "Screenshot-\(dateFormatter.string(from: Date()))"
        savePanel.nameFieldStringValue = defaultFileName
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                if let imageData = format.data(from: image) {
                    do {
                        try imageData.write(to: url)
                        
                        // 保存成功通知
                        self.showSaveSuccessNotification(url: url)
                        
                        // スクリーンショット履歴に追加
                        self.addToHistory(image: image, url: url)
                    } catch {
                        self.showSaveErrorAlert(error: error)
                    }
                } else {
                    self.showSaveErrorAlert(error: nil)
                }
            }
        }
    }
    
    // 指定パスに保存（ダイアログなし）
    func saveToPath(_ image: NSImage, path: URL, format: ImageFormat = .png) -> Bool {
        guard let imageData = format.data(from: image) else {
            return false
        }
        
        do {
            try imageData.write(to: path)
            
            // 保存成功通知
            showSaveSuccessNotification(url: path)
            
            // スクリーンショット履歴に追加
            addToHistory(image: image, url: path)
            
            return true
        } catch {
            showSaveErrorAlert(error: error)
            return false
        }
    }
    
    // デフォルトの保存場所に保存
    func saveToDefaultLocation(_ image: NSImage, format: ImageFormat = .png) -> URL? {
        // デフォルトの保存先を取得 (ピクチャフォルダのScreenshotsディレクトリ)
        let fileManager = FileManager.default
        guard let picturesURL = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let screenshotsURL = picturesURL.appendingPathComponent("Screenshots", isDirectory: true)
        
        // Screenshotsディレクトリが存在しない場合は作成
        if !fileManager.fileExists(atPath: screenshotsURL.path) {
            do {
                try fileManager.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }
        
        // ファイル名を生成
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let fileName = "Screenshot-\(dateFormatter.string(from: Date())).\(format.fileExtension)"
        
        let fileURL = screenshotsURL.appendingPathComponent(fileName)
        
        // 保存
        if saveToPath(image, path: fileURL, format: format) {
            return fileURL
        } else {
            return nil
        }
    }
    
    // 保存成功通知
    private func showSaveSuccessNotification(url: URL) {
        let notification = NSUserNotification()
        notification.title = "スクリーンショットを保存しました"
        notification.informativeText = url.lastPathComponent
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.userInfo = ["url": url.path]
        
        // Finderで表示するアクション
        let showAction = NSUserNotificationAction(
            identifier: "showInFinder",
            title: "Finderで表示"
        )
        notification.additionalActions = [showAction]
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // 保存エラーアラート
    private func showSaveErrorAlert(error: Error?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "スクリーンショットの保存に失敗しました"
            
            if let error = error {
                alert.informativeText = error.localizedDescription
            }
            
            alert.runModal()
        }
    }
    
    // 履歴に追加
    private func addToHistory(image: NSImage, url: URL) {
        var screenshotModel = ScreenshotModel(image: image)
        screenshotModel.path = url
        ScreenshotHistory.shared.addScreenshot(screenshotModel)
    }

// NSUserNotificationCenterデリゲート（通知の処理用）
class NotificationDelegate: NSObject, NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if notification.activationType == .additionalActionClicked {
            if notification.additionalActivationAction?.identifier == "showInFinder" {
                if let urlPath = notification.userInfo?["url"] as? String {
                    let url = URL(fileURLWithPath: urlPath)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
    
    // 通知を常に表示
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
}

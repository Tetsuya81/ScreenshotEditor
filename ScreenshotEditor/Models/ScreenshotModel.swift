//
//  ScreenshotModel.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import Foundation
import SwiftUI

struct ScreenshotModel: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var filename: String
    var imageData: Data
    var path: URL?
    
    // コード化のために必要なキー
    enum CodingKeys: String, CodingKey {
        case id, date, filename, imageData, path
    }
    
    init(image: NSImage, filename: String = "") {
        self.date = Date()
        self.imageData = image.pngData() ?? Data()
        
        if filename.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            self.filename = "Screenshot-\(dateFormatter.string(from: date))"
        } else {
            self.filename = filename
        }
    }
    
    // NSImageへの変換
    func image() -> NSImage? {
        guard let bitmap = NSBitmapImageRep(data: imageData) else { return nil }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }
    
    // 新しいファイル名でコピーを作成
    func renamed(to newFilename: String) -> ScreenshotModel {
        var copy = self
        copy.filename = newFilename
        return copy
    }
    
    // エンコーダー
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(filename, forKey: .filename)
        try container.encode(imageData, forKey: .imageData)
        try container.encodeIfPresent(path, forKey: .path)
    }
    
    // デコーダー
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        filename = try container.decode(String.self, forKey: .filename)
        imageData = try container.decode(Data.self, forKey: .imageData)
        path = try container.decodeIfPresent(URL.self, forKey: .path)
    }
}

// スクリーンショット履歴の保存と読み込みを担当するクラス
class ScreenshotHistory {
    static let shared = ScreenshotHistory()
    
    private let historyKey = "screenshot_history"
    private let maxHistoryItems = 20
    
    @Published var screenshots: [ScreenshotModel] = []
    
    private init() {
        loadHistory()
    }
    
    // スクリーンショットを追加
    func addScreenshot(_ screenshot: ScreenshotModel) {
        screenshots.insert(screenshot, at: 0)
        
        // 最大数を超えたら古いものを削除
        if screenshots.count > maxHistoryItems {
            screenshots.removeLast(screenshots.count - maxHistoryItems)
        }
        
        saveHistory()
    }
    
    // スクリーンショットを削除
    func removeScreenshot(id: UUID) {
        screenshots.removeAll(where: { $0.id == id })
        saveHistory()
    }
    
    // 全ての履歴を削除
    func clearHistory() {
        screenshots.removeAll()
        saveHistory()
    }
    
    // 履歴を保存
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(screenshots)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            print("スクリーンショット履歴の保存に失敗しました: \(error)")
        }
    }
    
    // 履歴を読み込み
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        
        do {
            screenshots = try JSONDecoder().decode([ScreenshotModel].self, from: data)
        } catch {
            print("スクリーンショット履歴の読み込みに失敗しました: \(error)")
        }
    }
}

// 編集履歴（Undo/Redo）を管理するクラス
class EditHistory {
    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    
    private let maxHistorySize = 20
    
    struct EditState {
        let drawingItems: [DrawingItem]
    }
    
    // 現在の状態を追加
    func addState(drawingItems: [DrawingItem]) {
        let state = EditState(drawingItems: drawingItems)
        undoStack.append(state)
        
        // 最大数を超えたら古いものを削除
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst()
        }
        
        // 新しい状態を追加したので、Redoスタックをクリア
        redoStack.removeAll()
    }
    
    // Undo操作
    func undo() -> [DrawingItem]? {
        guard undoStack.count > 1 else { return nil }
        
        let currentState = undoStack.removeLast()
        redoStack.append(currentState)
        
        return undoStack.last?.drawingItems
    }
    
    // Redo操作
    func redo() -> [DrawingItem]? {
        guard !redoStack.isEmpty else { return nil }
        
        let nextState = redoStack.removeLast()
        undoStack.append(nextState)
        
        return nextState.drawingItems
    }
    
    // 履歴をクリア
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    
    // Undoが可能かどうか
    var canUndo: Bool {
        return undoStack.count > 1
    }
    
    // Redoが可能かどうか
    var canRedo: Bool {
        return !redoStack.isEmpty
    }
}

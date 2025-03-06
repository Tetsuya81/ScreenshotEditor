//
//  EditorViewModel.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import SwiftUI
import Combine

class EditorViewModel: ObservableObject {
    // 編集中の画像
    @Published var originalImage: NSImage
    @Published var drawingItems: [DrawingItem] = []
    @Published var selectedDrawingItem: DrawingItem?
    
    // ツール設定
    @Published var currentTool: DrawingTool = .pen
    @Published var currentColor: Color = .red
    @Published var currentLineWidth: CGFloat = 2
    
    // 編集履歴
    private var editHistory = EditHistory()
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    // 選択状態
    @Published var selectionRect: CGRect?
    
    // テキスト編集
    @Published var isEditingText: Bool = false
    @Published var editingTextItem: UUID?
    @Published var textInput: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    
    init(image: NSImage) {
        self.originalImage = image
        
        // 初期状態を履歴に追加
        editHistory.addState(drawingItems: [])
        updateUndoRedoState()
        
        // 選択ツールの監視
        $currentTool
            .sink { [weak self] tool in
                guard let self = self else { return }
                
                // 選択ツール以外に変更された場合、選択状態をクリア
                if tool != .select {
                    self.clearSelection()
                }
                
                // テキスト編集中なら確定する
                if self.isEditingText {
                    self.commitTextEdit()
                }
            }
            .store(in: &cancellables)
    }
    
    // 描画アイテムを追加
    func addDrawingItem(_ item: DrawingItem) {
        drawingItems.append(item)
        editHistory.addState(drawingItems: drawingItems)
        updateUndoRedoState()
    }
    
    // 描画アイテムを更新
    func updateDrawingItem(id: UUID, update: (inout DrawingItem) -> Void) {
        if let index = drawingItems.firstIndex(where: { $0.id == id }) {
            var updatedItem = drawingItems[index]
            update(&updatedItem)
            drawingItems[index] = updatedItem
            
            if updatedItem.isSelected {
                selectedDrawingItem = updatedItem
            }
        }
    }
    
    // 描画アイテムを削除
    func removeDrawingItem(id: UUID) {
        drawingItems.removeAll(where: { $0.id == id })
        
        if selectedDrawingItem?.id == id {
            selectedDrawingItem = nil
        }
        
        editHistory.addState(drawingItems: drawingItems)
        updateUndoRedoState()
    }
    
    // 選択中のアイテムを削除
    func removeSelectedItems() {
        let selectedIds = drawingItems.filter { $0.isSelected }.map { $0.id }
        
        for id in selectedIds {
            removeDrawingItem(id: id)
        }
    }
    
    // アイテムを選択
    func selectItem(id: UUID) {
        // 現在の選択をクリア
        clearSelection()
        
        // 指定されたアイテムを選択
        if let index = drawingItems.firstIndex(where: { $0.id == id }) {
            drawingItems[index].isSelected = true
            selectedDrawingItem = drawingItems[index]
        }
    }
    
    // 矩形内のアイテムを選択
    func selectItemsInRect(_ rect: CGRect) {
        // 選択状態をリセット
        clearSelection()
        
        // 矩形内のアイテムを選択
        for i in 0..<drawingItems.count {
            if itemIntersectsRect(drawingItems[i], rect: rect) {
                drawingItems[i].isSelected = true
                
                // 最初に見つかったアイテムを選択アイテムとする
                if selectedDrawingItem == nil {
                    selectedDrawingItem = drawingItems[i]
                }
            }
        }
    }
    
    // 選択をクリア
    func clearSelection() {
        for i in 0..<drawingItems.count {
            drawingItems[i].isSelected = false
        }
        selectedDrawingItem = nil
        selectionRect = nil
    }
    
    // アイテムが矩形と交差するかチェック
    private func itemIntersectsRect(_ item: DrawingItem, rect: CGRect) -> Bool {
        switch item.tool {
        case .rectangle, .circle, .text:
            return item.rect?.intersects(rect) ?? false
        case .arrow:
            return item.rect?.intersects(rect) ?? false
        case .pen, .highlighter, .eraser:
            // いずれかの点が矩形内にあるかチェック
            for p in item.points {
                if rect.contains(p) {
                    return true
                }
            }
            return false
        case .select:
            return false
        }
    }
    
    // テキスト編集を開始
    func startTextEdit(at position: CGPoint) {
        isEditingText = true
        textInput = ""
        
        let newItem = DrawingItem(
            tool: .text,
            points: [position],
            color: currentColor,
            lineWidth: currentLineWidth,
            text: ""
        )
        
        drawingItems.append(newItem)
        editingTextItem = newItem.id
    }
    
    // テキスト編集を確定
    func commitTextEdit() {
        guard isEditingText, let id = editingTextItem else { return }
        
        if textInput.isEmpty {
            // 空のテキストなら削除
            removeDrawingItem(id: id)
        } else {
            // テキストを更新
            updateDrawingItem(id: id) { item in
                item.text = textInput
                
                // テキストサイズに基づいて矩形を設定
                let font = NSFont.systemFont(ofSize: 16)
                let textSize = (textInput as NSString).size(withAttributes: [.font: font])
                let point = item.points[0]
                
                item.rect = CGRect(
                    x: point.x,
                    y: point.y - textSize.height/2,
                    width: textSize.width,
                    height: textSize.height
                )
            }
            
            editHistory.addState(drawingItems: drawingItems)
            updateUndoRedoState()
        }
        
        isEditingText = false
        editingTextItem = nil
        textInput = ""
    }
    
    // 選択中のアイテムの色を変更
    func changeColorOfSelectedItems(to color: Color) {
        var changed = false
        
        for i in 0..<drawingItems.count {
            if drawingItems[i].isSelected {
                drawingItems[i].color = color
                changed = true
            }
        }
        
        if changed {
            editHistory.addState(drawingItems: drawingItems)
            updateUndoRedoState()
        }
    }
    
    // 選択中のアイテムの線幅を変更
    func changeLineWidthOfSelectedItems(to width: CGFloat) {
        var changed = false
        
        for i in 0..<drawingItems.count {
            if drawingItems[i].isSelected {
                drawingItems[i].lineWidth = width
                changed = true
            }
        }
        
        if changed {
            editHistory.addState(drawingItems: drawingItems)
            updateUndoRedoState()
        }
    }
    
    // アイテムのリサイズ
    func resizeSelectedItem(to rect: CGRect) {
        guard let selectedItem = selectedDrawingItem else { return }
        
        updateDrawingItem(id: selectedItem.id) { item in
            item.rect = rect
        }
        
        editHistory.addState(drawingItems: drawingItems)
        updateUndoRedoState()
    }
    
    // Undo操作
    func undo() {
        if let previousItems = editHistory.undo() {
            drawingItems = previousItems
            updateUndoRedoState()
            clearSelection()
        }
    }
    
    // Redo操作
    func redo() {
        if let nextItems = editHistory.redo() {
            drawingItems = nextItems
            updateUndoRedoState()
            clearSelection()
        }
    }
    
    // Undo/Redoの状態を更新
    private func updateUndoRedoState() {
        canUndo = editHistory.canUndo
        canRedo = editHistory.canRedo
    }
    
    // 編集済み画像を取得
    func getEditedImage() -> NSImage {
        let renderer = ImageRenderer(content:
            ZStack {
                Image(nsImage: originalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                
                ForEach(drawingItems) { item in
                    DrawingItemView(item: item, isSelected: false)
                }
            }
            .frame(width: originalImage.size.width, height: originalImage.size.height)
        )
        
        if let nsImage = renderer.nsImage {
            return nsImage
        }
        
        return originalImage
    }
    
    // キーボードショートカットのハンドリング
    func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        // 削除キー
        if event.keyCode == 51 || event.keyCode == 117 {
            removeSelectedItems()
            return true
        }
        
        // Undoショートカット (Cmd+Z)
        if event.modifierFlags.contains(.command) && event.keyCode == 6 {
            undo()
            return true
        }
        
        // Redoショートカット (Cmd+Shift+Z)
        if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) && event.keyCode == 6 {
            redo()
            return true
        }
        
        // すべて選択 (Cmd+A)
        if event.modifierFlags.contains(.command) && event.keyCode == 0 {
            for i in 0..<drawingItems.count {
                drawingItems[i].isSelected = true
            }
            if !drawingItems.isEmpty {
                selectedDrawingItem = drawingItems.first
            }
            return true
        }
        
        return false
    }
}

// ImageRendererはSwiftUIのViewをNSImageに変換するためのユーティリティクラス
struct ImageRenderer {
    let content: AnyView
    
    init<V: View>(content: V) {
        self.content = AnyView(content)
    }
    
    var nsImage: NSImage? {
        let controller = NSHostingController(rootView: content)
        let targetSize = controller.view.fittingSize
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: targetSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.view
        
        guard let bitmapRep = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
            return nil
        }
        
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmapRep)
        
        let image = NSImage(size: bitmapRep.size)
        image.addRepresentation(bitmapRep)
        
        return image
    }
}

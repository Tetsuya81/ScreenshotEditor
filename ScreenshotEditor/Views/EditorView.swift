//
//  EditorView.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import SwiftUI

enum DrawingTool: String, CaseIterable, Identifiable {
    case select
    case arrow
    case rectangle
    case circle
    case text
    case highlighter
    case pen
    case eraser
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .text: return "text.cursor"
        case .highlighter: return "highlighter"
        case .pen: return "pencil"
        case .eraser: return "eraser"
        }
    }
    
    var name: String {
        switch self {
        case .select: return "選択"
        case .arrow: return "矢印"
        case .rectangle: return "四角形"
        case .circle: return "円"
        case .text: return "テキスト"
        case .highlighter: return "ハイライト"
        case .pen: return "ペン"
        case .eraser: return "消しゴム"
        }
    }
}

struct DrawingItem: Identifiable {
    let id = UUID()
    var tool: DrawingTool
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
    var text: String = ""
    var rect: CGRect?
    var isSelected: Bool = false
}

struct EditorView: View {
    let image: NSImage
    let onSave: (NSImage) -> Void
    let onCancel: () -> Void
    
    @State private var drawingItems: [DrawingItem] = []
    @State private var currentDrawingItem: DrawingItem?
    @State private var selectedDrawingItem: DrawingItem?
    @State private var currentTool: DrawingTool = .pen
    @State private var currentColor: Color = .red
    @State private var currentLineWidth: CGFloat = 2
    @State private var textInput: String = ""
    @State private var isEditing: Bool = false
    @State private var editingItemId: UUID?
    @State private var currentTextPosition: CGPoint?
    @State private var dragStart: CGPoint?
    @State private var selectionRect: CGRect?
    @State private var isResizing: Bool = false
    @State private var resizeHandle: ResizeHandle?
    @State private var originalRect: CGRect?
    
    enum ResizeHandle {
        case topLeft, topRight, bottomLeft, bottomRight, none
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ツールバー
            ToolbarView(
                selectedTool: $currentTool,
                selectedColor: $currentColor,
                lineWidth: $currentLineWidth,
                onSave: {
                    saveImage()
                },
                onCancel: onCancel
            )
            
            // メインエディター
            GeometryReader { geometry in
                ZStack {
                    // 背景（透明グリッド）
                    TransparentBackgroundView()
                    
                    // 元の画像
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // 描画アイテム
                    ForEach(drawingItems) { item in
                        DrawingItemView(item: item, isSelected: item.isSelected)
                    }
                    
                    // 現在描画中のアイテム
                    if let currentItem = currentDrawingItem {
                        DrawingItemView(item: currentItem, isSelected: false)
                    }
                    
                    // 選択範囲
                    if let selectionRect = selectionRect, currentTool == .select {
                        SelectionRectView(rect: selectionRect)
                    }
                    
                    // テキスト入力フィールド
                    if isEditing, let position = currentTextPosition, let editingItem = editingItemId {
                        TextField("", text: $textInput, onCommit: {
                            if !textInput.isEmpty {
                                updateTextItem(id: editingItem, text: textInput)
                            }
                            isEditing = false
                            editingItemId = nil
                        })
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16))
                        .foregroundColor(currentColor)
                        .position(position)
                        .background(Color.white.opacity(0.5))
                    }
                    
                    // 透明なビューでタッチイベントをキャプチャ
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    handleDragChanged(value, in: geometry)
                                }
                                .onEnded { value in
                                    handleDragEnded(value, in: geometry)
                                }
                        )
                        .onTapGesture { location in
                            handleTap(at: location, in: geometry)
                        }
                }
            }
        }
        .frame(width: image.size.width, height: image.size.height + 50) // ツールバーの高さを考慮
        .background(Color(NSColor.windowBackgroundColor))
        .ignoresSafeArea()
    }
    
    // タップ処理
    private func handleTap(at location: CGPoint, in geometry: GeometryProxy) {
        if currentTool == .text {
            // テキスト追加モード
            currentTextPosition = location
            editingItemId = UUID()
            textInput = ""
            isEditing = true
            
            let textItem = DrawingItem(
                tool: .text,
                points: [location],
                color: currentColor,
                lineWidth: currentLineWidth,
                text: ""
            )
            drawingItems.append(textItem)
            editingItemId = textItem.id
            
        } else if currentTool == .select {
            // 既存アイテムの選択
            selectItemAt(location)
        }
    }
    
    // ドラッグ開始/変更時の処理
    private func handleDragChanged(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        let location = value.location
        
        if dragStart == nil {
            dragStart = location
            
            // 選択ツールの場合、選択状態をリセット
            if currentTool == .select {
                // リサイズハンドルのチェック
                if let selectedItem = selectedDrawingItem, let rect = selectedItem.rect {
                    let handleSize: CGFloat = 10
                    
                    // 各ハンドルの領域をチェック
                    let topLeft = CGRect(x: rect.minX - handleSize/2, y: rect.minY - handleSize/2, width: handleSize, height: handleSize)
                    let topRight = CGRect(x: rect.maxX - handleSize/2, y: rect.minY - handleSize/2, width: handleSize, height: handleSize)
                    let bottomLeft = CGRect(x: rect.minX - handleSize/2, y: rect.maxY - handleSize/2, width: handleSize, height: handleSize)
                    let bottomRight = CGRect(x: rect.maxX - handleSize/2, y: rect.maxY - handleSize/2, width: handleSize, height: handleSize)
                    
                    if topLeft.contains(location) {
                        isResizing = true
                        resizeHandle = .topLeft
                        originalRect = rect
                        return
                    } else if topRight.contains(location) {
                        isResizing = true
                        resizeHandle = .topRight
                        originalRect = rect
                        return
                    } else if bottomLeft.contains(location) {
                        isResizing = true
                        resizeHandle = .bottomLeft
                        originalRect = rect
                        return
                    } else if bottomRight.contains(location) {
                        isResizing = true
                        resizeHandle = .bottomRight
                        originalRect = rect
                        return
                    }
                }
                
                // リサイズでなければ新しい選択を開始
                for i in 0..<drawingItems.count {
                    drawingItems[i].isSelected = false
                }
                selectedDrawingItem = nil
                selectionRect = CGRect(origin: location, size: .zero)
                return
            }
            
            // 描画開始
            switch currentTool {
            case .pen, .highlighter, .eraser:
                currentDrawingItem = DrawingItem(
                    tool: currentTool,
                    points: [location],
                    color: currentTool == .eraser ? .white : currentColor,
                    lineWidth: currentTool == .highlighter ? 20 : currentLineWidth
                )
            case .arrow, .rectangle, .circle:
                let rect = CGRect(origin: location, size: .zero)
                currentDrawingItem = DrawingItem(
                    tool: currentTool,
                    points: [location],
                    color: currentColor,
                    lineWidth: currentLineWidth,
                    rect: rect
                )
            default:
                break
            }
        } else {
            if isResizing, let selectedItem = selectedDrawingItem, let originalRect = originalRect {
                // リサイズ処理
                var newRect = originalRect
                
                switch resizeHandle {
                case .topLeft:
                    newRect = CGRect(
                        x: min(location.x, originalRect.maxX),
                        y: min(location.y, originalRect.maxY),
                        width: abs(originalRect.maxX - location.x),
                        height: abs(originalRect.maxY - location.y)
                    )
                case .topRight:
                    newRect = CGRect(
                        x: originalRect.minX,
                        y: min(location.y, originalRect.maxY),
                        width: max(0, location.x - originalRect.minX),
                        height: abs(originalRect.maxY - location.y)
                    )
                case .bottomLeft:
                    newRect = CGRect(
                        x: min(location.x, originalRect.maxX),
                        y: originalRect.minY,
                        width: abs(originalRect.maxX - location.x),
                        height: max(0, location.y - originalRect.minY)
                    )
                case .bottomRight:
                    newRect = CGRect(
                        x: originalRect.minX,
                        y: originalRect.minY,
                        width: max(0, location.x - originalRect.minX),
                        height: max(0, location.y - originalRect.minY)
                    )
                default:
                    break
                }
                
                if let index = drawingItems.firstIndex(where: { $0.id == selectedItem.id }) {
                    drawingItems[index].rect = newRect
                }
                
            } else if currentTool == .select {
                // 選択範囲の更新
                if let start = dragStart {
                    let minX = min(start.x, location.x)
                    let minY = min(start.y, location.y)
                    let width = abs(location.x - start.x)
                    let height = abs(location.y - start.y)
                    selectionRect = CGRect(x: minX, y: minY, width: width, height: height)
                }
            } else if var item = currentDrawingItem {
                // 描画アイテムの更新
                switch currentTool {
                case .pen, .highlighter, .eraser:
                    item.points.append(location)
                    currentDrawingItem = item
                case .arrow, .rectangle, .circle:
                    if let start = dragStart {
                        let minX = min(start.x, location.x)
                        let minY = min(start.y, location.y)
                        let width = abs(location.x - start.x)
                        let height = abs(location.y - start.y)
                        item.rect = CGRect(x: minX, y: minY, width: width, height: height)
                        currentDrawingItem = item
                    }
                default:
                    break
                }
            }
        }
    }
    
    // ドラッグ終了時の処理
    private func handleDragEnded(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        let location = value.location
        
        if isResizing {
            // リサイズ終了
            isResizing = false
            resizeHandle = nil
            originalRect = nil
        } else if currentTool == .select {
            // 選択範囲内のアイテムを選択
            if let rect = selectionRect {
                selectItemsInRect(rect)
            }
            selectionRect = nil
        } else if let item = currentDrawingItem {
            // 描画アイテムの確定
            drawingItems.append(item)
            currentDrawingItem = nil
        }
        
        dragStart = nil
    }
    
    // テキストアイテムの更新
    private func updateTextItem(id: UUID, text: String) {
        if let index = drawingItems.firstIndex(where: { $0.id == id }) {
            drawingItems[index].text = text
            
            // テキストサイズに基づいて矩形を設定
            let font = NSFont.systemFont(ofSize: 16)
            let textSize = (text as NSString).size(withAttributes: [.font: font])
            let point = drawingItems[index].points[0]
            
            drawingItems[index].rect = CGRect(
                x: point.x,
                y: point.y - textSize.height/2,
                width: textSize.width,
                height: textSize.height
            )
        }
    }
    
    // 指定位置のアイテム選択
    private func selectItemAt(_ location: CGPoint) {
        // 選択状態をリセット
        for i in 0..<drawingItems.count {
            drawingItems[i].isSelected = false
        }
        selectedDrawingItem = nil
        
        // 逆順で走査して、最も前面のアイテムを選択
        for i in stride(from: drawingItems.count - 1, through: 0, by: -1) {
            if itemContains(drawingItems[i], point: location) {
                drawingItems[i].isSelected = true
                selectedDrawingItem = drawingItems[i]
                break
            }
        }
    }
    
    // 矩形内のアイテム選択
    private func selectItemsInRect(_ rect: CGRect) {
        // 選択状態をリセット
        for i in 0..<drawingItems.count {
            drawingItems[i].isSelected = false
        }
        selectedDrawingItem = nil
        
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
    
    // アイテムが点を含むかチェック
    private func itemContains(_ item: DrawingItem, point: CGPoint) -> Bool {
        switch item.tool {
        case .rectangle, .circle, .text:
            return item.rect?.contains(point) ?? false
        case .arrow:
            // 簡易的な判定 - より正確にするには線分の距離チェックが必要
            return item.rect?.insetBy(dx: -10, dy: -10).contains(point) ?? false
        case .pen, .highlighter, .eraser:
            // 点との距離をチェック
            for p in item.points {
                let distance = sqrt(pow(p.x - point.x, 2) + pow(p.y - point.y, 2))
                if distance <= max(5, item.lineWidth / 2) {
                    return true
                }
            }
            return false
        case .select:
            return false
        }
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
    
    // 編集結果を画像として保存
    private func saveImage() {
        let renderer = ImageRenderer(content:
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                
                ForEach(drawingItems) { item in
                    DrawingItemView(item: item, isSelected: false)
                }
            }
            .frame(width: image.size.width, height: image.size.height)
        )
        
        // 通常のnsBitmapチェックではなく、Swiftの方法でNSImageに変換
        if let nsImage = renderer.nsImage {
            onSave(nsImage)
        }
    }
}

// 描画アイテムの表示
struct DrawingItemView: View {
    let item: DrawingItem
    let isSelected: Bool
    
    var body: some View {
        switch item.tool {
        case .pen, .highlighter, .eraser:
            if item.points.count > 1 {
                Path { path in
                    path.move(to: item.points[0])
                    for point in item.points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(item.color, lineWidth: item.lineWidth)
                .opacity(item.tool == .highlighter ? 0.5 : 1.0)
                .overlay(
                    isSelected ?
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.blue, lineWidth: 1)
                            .opacity(0.8) : nil
                )
            }
        case .arrow:
            if let rect = item.rect {
                ArrowShape(start: CGPoint(x: rect.minX, y: rect.minY),
                           end: CGPoint(x: rect.maxX, y: rect.maxY))
                    .stroke(item.color, lineWidth: item.lineWidth)
                    .overlay(
                        isSelected ?
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.blue, lineWidth: 1)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .opacity(0.8) : nil
                    )
            }
        case .rectangle:
            if let rect = item.rect {
                Rectangle()
                    .stroke(item.color, lineWidth: item.lineWidth)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .overlay(
                        isSelected ?
                            Rectangle()
                                .stroke(Color.blue, lineWidth: 1)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .opacity(0.8) : nil
                    )
                
                if isSelected {
                    ResizeHandlesView(rect: rect)
                }
            }
        case .circle:
            if let rect = item.rect {
                Ellipse()
                    .stroke(item.color, lineWidth: item.lineWidth)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .overlay(
                        isSelected ?
                            Rectangle()
                                .stroke(Color.blue, lineWidth: 1)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .opacity(0.8) : nil
                    )
                
                if isSelected {
                    ResizeHandlesView(rect: rect)
                }
            }
        case .text:
            if !item.text.isEmpty, let rect = item.rect {
                Text(item.text)
                    .font(.system(size: 16))
                    .foregroundColor(item.color)
                    .position(x: rect.minX + rect.width/2, y: rect.minY + rect.height/2)
                    .overlay(
                        isSelected ?
                            Rectangle()
                                .stroke(Color.blue, lineWidth: 1)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .opacity(0.8) : nil
                    )
                
                if isSelected {
                    ResizeHandlesView(rect: rect)
                }
            }
        case .select:
            EmptyView()
        }
    }
}

// リサイズハンドルの表示
struct ResizeHandlesView: View {
    let rect: CGRect
    private let handleSize: CGFloat = 8
    
    var body: some View {
        ZStack {
            // 左上
            ResizeHandle()
                .position(x: rect.minX, y: rect.minY)
            
            // 右上
            ResizeHandle()
                .position(x: rect.maxX, y: rect.minY)
            
            // 左下
            ResizeHandle()
                .position(x: rect.minX, y: rect.maxY)
            
            // 右下
            ResizeHandle()
                .position(x: rect.maxX, y: rect.maxY)
        }
    }
    
    struct ResizeHandle: View {
        var body: some View {
            Rectangle()
                .fill(Color.white)
                .border(Color.blue, width: 1)
                .frame(width: 8, height: 8)
        }
    }
}

// 矢印の形状
struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: start)
        path.addLine(to: end)
        
        // 矢印のヘッド部分
        let length: CGFloat = 15
        let angle: CGFloat = .pi / 6 // 30度
        
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance > 0 {
            let nx = dx / distance
            let ny = dy / distance
            
            let arrowPoint1 = CGPoint(
                x: end.x - length * (nx * cos(angle) + ny * sin(angle)),
                y: end.y - length * (ny * cos(angle) - nx * sin(angle))
            )
            
            let arrowPoint2 = CGPoint(
                x: end.x - length * (nx * cos(angle) - ny * sin(angle)),
                y: end.y - length * (ny * cos(angle) + nx * sin(angle))
            )
            
            path.move(to: end)
            path.addLine(to: arrowPoint1)
            path.move(to: end)
            path.addLine(to: arrowPoint2)
        }
        
        return path
    }
}

// 選択範囲の表示
struct SelectionRectView: View {
    let rect: CGRect
    
    var body: some View {
        Rectangle()
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

// 透明な背景（チェック柄）
struct TransparentBackgroundView: View {
    let size: CGFloat = 10
    
    var body: some View {
        Canvas { context, size in
            for row in 0...Int(size.height / self.size) {
                for col in 0...Int(size.width / self.size) {
                    let rect = CGRect(
                        x: CGFloat(col) * self.size,
                        y: CGFloat(row) * self.size,
                        width: self.size,
                        height: self.size
                    )
                    
                    let color = (row + col) % 2 == 0 ?
                        CGColor(gray: 0.9, alpha: 1.0) :
                        CGColor(gray: 0.8, alpha: 1.0)
                    
                    context.fill(Path(rect), with: .color(Color(cgColor: color)))
                }
            }
        }
    }
}

struct EditorView_Previews: PreviewProvider {
    static var previews: some View {
        EditorView(
            image: NSImage(named: "preview") ?? NSImage(),
            onSave: { _ in },
            onCancel: {}
        )
    }
}

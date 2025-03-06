//
//  Extentions.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import Foundation
import SwiftUI
import Combine

// NSImageの拡張
extension NSImage {
    // NSImageをData（PNG形式）に変換
    func pngData() -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
    
    // リサイズ
    func resize(to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: size),
                  operation: .copy,
                  fraction: 1.0)
        
        newImage.unlockFocus()
        return newImage
    }
    
    // 指定された領域を切り抜く
    func cropping(to rect: CGRect) -> NSImage? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: scaledRect) else {
            return nil
        }
        
        let croppedImage = NSImage(cgImage: croppedCGImage, size: rect.size)
        return croppedImage
    }
    
    // CGImageプロパティへのアクセス
    var cgImage: CGImage? {
        var imageRect = NSRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }
}

// SwiftUI Colorの拡張
extension Color {
    // NSColorに変換
    func toNSColor() -> NSColor {
        NSColor(self)
    }
    
    // CGColorに変換
    func toCGColor() -> CGColor {
        NSColor(self).cgColor
    }
    
    // 16進数文字列から初期化
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // 16進数文字列に変換
    func toHex() -> String? {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            return nil
        }
        
        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))
        
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

// NSViewの拡張
extension NSView {
    // ビューのスクリーンショット
    func takeScreenshot() -> NSImage? {
        guard let bitmapRep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        
        cacheDisplay(in: bounds, to: bitmapRep)
        
        let image = NSImage(size: bitmapRep.size)
        image.addRepresentation(bitmapRep)
        
        return image
    }
}

// Dateの拡張
extension Date {
    // ファイル名に適した形式
    func fileNameFormat() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.string(from: self)
    }
    
    // 表示用の形式
    func displayFormat() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: self)
    }
}

// Viewの拡張
extension View {
    // 条件付きで修飾子を適用
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    // マウス位置を取得するモディファイア
    func onMouseLocation(perform action: @escaping (NSPoint) -> Void) -> some View {
        self.background(MouseLocationView(onMouseMoved: action))
    }
}

// マウス位置を追跡するためのビュー
struct MouseLocationView: NSViewRepresentable {
    let onMouseMoved: (NSPoint) -> Void
    
    func makeNSView(context: Context) -> MouseLocationNSView {
        let view = MouseLocationNSView()
        view.onMouseMoved = onMouseMoved
        return view
    }
    
    func updateNSView(_ nsView: MouseLocationNSView, context: Context) {
        nsView.onMouseMoved = onMouseMoved
    }
    
    class MouseLocationNSView: NSView {
        var onMouseMoved: ((NSPoint) -> Void)?
        var trackingArea: NSTrackingArea?
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            
            if let trackingArea = trackingArea {
                removeTrackingArea(trackingArea)
            }
            
            trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
            
            if let trackingArea = trackingArea {
                addTrackingArea(trackingArea)
            }
        }
        
        override func mouseMoved(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            onMouseMoved?(location)
        }
    }
}

// Published値を監視するモディファイア
extension Published.Publisher {
    func sink(receiveValue: @escaping (Value) -> Void) -> AnyCancellable {
        sink(receiveCompletion: { _ in }, receiveValue: receiveValue)
    }
}

// UserDefaults拡張
extension UserDefaults {
    // Codable型を保存
    func setCodable<T: Codable>(_ value: T, forKey key: String) {
        if let encoded = try? JSONEncoder().encode(value) {
            set(encoded, forKey: key)
        }
    }
    
    // Codable型を取得
    func codable<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        if let data = data(forKey: key) {
            return try? JSONDecoder().decode(type, from: data)
        }
        return nil
    }
}

// NSCursor拡張
extension NSCursor {
    // クロスヘアカーソル
    static var crosshair: NSCursor {
        NSCursor.crosshair
    }
    
    // カスタムカーソルの作成（スクリーンショット用）
    static func createCameraShapedCursor() -> NSCursor {
        // デフォルトカメラアイコンのNSImageを作成
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)!
        let size = NSSize(width: 24, height: 24)
        let resizedImage = image.resize(to: size)
        
        return NSCursor(image: resizedImage, hotSpot: NSPoint(x: 12, y: 12))
    }
}

// Bundle拡張
extension Bundle {
    // バージョン情報
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

// アニメーション拡張
extension Animation {
    // フェード効果
    static var easeInOutFast: Animation {
        Animation.easeInOut(duration: 0.2)
    }
}

// ビューサイズ取得用
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    // ビューのサイズを取得
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

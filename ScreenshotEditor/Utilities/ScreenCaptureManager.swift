//
//  ScreenCaptureManager.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import Foundation
import ScreenCaptureKit
import SwiftUI
import Combine

enum CaptureMode {
    case fullScreen
    case selection
}

class ScreenCaptureManager: NSObject {
    static let shared = ScreenCaptureManager()
    
    private var availableContent: SCShareableContent?
    private var captureSession: SCStreamSession?
    private var stream: SCStream?
    private var streamOutput: CaptureSessionOutput?
    private var selectedDisplayID: CGDirectDisplayID?
    private var selectionRect: CGRect?
    
    private var permissionGranted = false
    
    var captureComplete = PassthroughSubject<NSImage, Error>()
    
    override init() {
        super.init()
        Task {
            do {
                availableContent = try await SCShareableContent.current
            } catch {
                print("Failed to get shareable content: \(error)")
            }
        }
    }
    
    func checkPermission(completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let authorizationStatus = await SCShareableContent.checkAuthorization(options: [])
                switch authorizationStatus {
                case .authorized:
                    permissionGranted = true
                    completion(true)
                default:
                    permissionGranted = false
                    completion(false)
                }
            }
        }
    }
    
    func requestPermission() async -> Bool {
        do {
            availableContent = try await SCShareableContent.current
            permissionGranted = true
            return true
        } catch {
            print("Failed to get permission: \(error)")
            permissionGranted = false
            return false
        }
    }
    
    func captureFullScreen() async {
        guard permissionGranted else {
            if await requestPermission() == false {
                return
            }
        }
        
        do {
            // 最初の利用可能なディスプレイを使用
            guard let availableContent = availableContent,
                  let display = availableContent.displays.first else {
                throw NSError(domain: "ScreenCaptureError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display available"])
            }
            
            selectedDisplayID = display.displayID
            
            // キャプチャ設定を構成
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.capturesAudio = false
            configuration.showsCursor = false
            
            // アプリ自体をキャプチャから除外
            if let runningApps = availableContent.applications {
                let appBundleID = Bundle.main.bundleIdentifier ?? ""
                let currentApp = runningApps.first(where: { $0.bundleIdentifier == appBundleID })
                
                if let currentApp = currentApp {
                    let filterExcludingApp = SCContentFilter(display: display,
                                                           excludingApplications: [currentApp],
                                                           exceptingWindows: [])
                    streamOutput = CaptureSessionOutput()
                    stream = SCStream(filter: filterExcludingApp, configuration: configuration, delegate: streamOutput)
                } else {
                    streamOutput = CaptureSessionOutput()
                    stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)
                }
            } else {
                streamOutput = CaptureSessionOutput()
                stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)
            }
            
            guard let stream = stream, let streamOutput = streamOutput else {
                throw NSError(domain: "ScreenCaptureError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create stream"])
            }
            
            // キャプチャ完了ハンドラの設定
            streamOutput.didOutputSampleBuffer = { [weak self] image in
                self?.captureComplete.send(image)
                self?.stopCapture()
            }
            
            // キャプチャ開始
            try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
            captureSession = SCStreamSession()
            try stream.startCapture()
            
        } catch {
            print("Error capturing screen: \(error)")
            captureComplete.send(completion: .failure(error))
        }
    }
    
    func captureSelection() async {
        guard permissionGranted else {
            if await requestPermission() == false {
                return
            }
        }
        
        DispatchQueue.main.async {
            // セレクション用の半透明ウィンドウを表示
            let selectionWindow = SelectionWindow()
            selectionWindow.onSelectionComplete = { [weak self] rect in
                guard let self = self else { return }
                // 選択された範囲を保存
                self.selectionRect = rect
                // 選択後にキャプチャ実行
                Task {
                    await self.captureSelectionArea()
                }
            }
            selectionWindow.makeKeyAndOrderFront(nil)
        }
    }
    
    private func captureSelectionArea() async {
        guard let selectionRect = selectionRect,
              let availableContent = availableContent,
              let display = availableContent.displays.first else {
            return
        }
        
        do {
            selectedDisplayID = display.displayID
            
            // キャプチャ設定を構成
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.capturesAudio = false
            configuration.showsCursor = false
            
            // アプリ自体をキャプチャから除外
            if let runningApps = availableContent.applications {
                let appBundleID = Bundle.main.bundleIdentifier ?? ""
                let currentApp = runningApps.first(where: { $0.bundleIdentifier == appBundleID })
                
                if let currentApp = currentApp {
                    let filterExcludingApp = SCContentFilter(display: display,
                                                           excludingApplications: [currentApp],
                                                           exceptingWindows: [])
                    streamOutput = CaptureSessionOutput()
                    stream = SCStream(filter: filterExcludingApp, configuration: configuration, delegate: streamOutput)
                } else {
                    streamOutput = CaptureSessionOutput()
                    stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)
                }
            } else {
                streamOutput = CaptureSessionOutput()
                stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)
            }
            
            guard let stream = stream, let streamOutput = streamOutput else {
                throw NSError(domain: "ScreenCaptureError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create stream"])
            }
            
            // 選択範囲のみのキャプチャハンドラの設定
            streamOutput.didOutputSampleBuffer = { [weak self] fullImage in
                guard let self = self else { return }
                
                // 選択範囲を切り抜く
                if let croppedImage = self.cropImage(fullImage, toRect: selectionRect) {
                    self.captureComplete.send(croppedImage)
                } else {
                    self.captureComplete.send(fullImage) // フォールバック
                }
                
                self.stopCapture()
            }
            
            // キャプチャ開始
            try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
            captureSession = SCStreamSession()
            try stream.startCapture()
            
        } catch {
            print("Error capturing selection: \(error)")
            captureComplete.send(completion: .failure(error))
        }
    }
    
    private func cropImage(_ image: NSImage, toRect rect: CGRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
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
    
    func stopCapture() {
        stream?.stopCapture()
        stream = nil
        captureSession = nil
        streamOutput = nil
    }
}

// キャプチャ出力を処理するクラス
class CaptureSessionOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var didOutputSampleBuffer: ((NSImage) -> Void)?
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // IOSurfaceからNSImageを作成
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            DispatchQueue.main.async {
                self.didOutputSampleBuffer?(image)
            }
        }
    }
}

// 選択範囲を指定するためのウィンドウ
class SelectionWindow: NSWindow {
    var startPoint: NSPoint?
    var currentRect: NSRect?
    var onSelectionComplete: ((CGRect) -> Void)?
    
    init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // ウィンドウの設定
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = SelectionView()
        
        if let contentView = self.contentView as? SelectionView {
            contentView.onSelectionComplete = { [weak self] rect in
                self?.onSelectionComplete?(rect)
                self?.close()
            }
        }
    }
}

// 選択範囲の描画を行うビュー
class SelectionView: NSView {
    var startPoint: NSPoint?
    var currentRect: NSRect?
    var onSelectionComplete: ((CGRect) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentRect = nil
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = startPoint else { return }
        
        let currentPoint = event.locationInWindow
        currentRect = NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
        
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let currentRect = currentRect, currentRect.size.width > 10, currentRect.size.height > 10 else {
            // 選択範囲が小さすぎる場合はキャンセル
            self.window?.close()
            return
        }
        
        onSelectionComplete?(currentRect)
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESCキー
            self.window?.close()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if let context = NSGraphicsContext.current?.cgContext {
            // 半透明の背景を描画
            context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
            context.fill(bounds)
            
            // 選択範囲があれば、その部分を透明にする
            if let rect = currentRect {
                context.setBlendMode(.clear)
                context.fill(rect)
                
                // 選択範囲の境界を描画
                context.setBlendMode(.normal)
                context.setStrokeColor(NSColor.white.cgColor)
                context.setLineWidth(1.0)
                context.stroke(rect)
            }
        }
    }
}

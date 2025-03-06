//
//  MainMenuView.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var captureViewModel: CaptureViewModel
    @State private var showingErrorAlert = false
    
    var body: some View {
        ZStack {
            // メインコンテンツ - キャプチャしていない時の表示
            if !captureViewModel.isCapturing && !captureViewModel.isEditing {
                VStack(spacing: 20) {
                    Text("Screenshot Editor")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 30) {
                        captureButton(
                            title: "全画面撮影",
                            systemImage: "rectangle.dashed",
                            action: {
                                captureViewModel.captureMode = .fullScreen
                                captureViewModel.prepareCapture()
                            }
                        )
                        
                        captureButton(
                            title: "範囲選択撮影",
                            systemImage: "rectangle.and.pencil.and.ellipsis",
                            action: {
                                captureViewModel.captureMode = .selection
                                captureViewModel.prepareCapture()
                            }
                        )
                    }
                    
                    Text("または、メニューバーのアイコンから選択することもできます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top)
                }
                .padding()
                .frame(width: 400, height: 300)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            
            // キャプチャ中のオーバーレイ
            if captureViewModel.showCaptureOverlay {
                CaptureOverlayView(
                    isFullScreen: captureViewModel.captureMode == .fullScreen,
                    onCancel: {
                        captureViewModel.cancelCapture()
                    }
                )
            }
            
            // 編集画面
            if captureViewModel.showEditor, let image = captureViewModel.capturedImage {
                EditorView(
                    image: image,
                    onSave: { editedImage in
                        // 保存アクションの選択を表示
                        showSaveOptions(for: editedImage)
                    },
                    onCancel: {
                        captureViewModel.exitEditor()
                    }
                )
            }
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(
                title: Text("エラー"),
                message: Text(captureViewModel.errorMessage ?? "不明なエラーが発生しました"),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: captureViewModel.errorMessage) { newValue in
            showingErrorAlert = newValue != nil
        }
    }
    
    // キャプチャボタンのビュー
    private func captureButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack {
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                
                Text(title)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(width: 120, height: 120)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
    
    // 保存オプションを表示
    private func showSaveOptions(for image: NSImage) {
        let alert = NSAlert()
        alert.messageText = "スクリーンショットの保存"
        alert.informativeText = "スクリーンショットの保存方法を選択してください"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "ファイルに保存")
        alert.addButton(withTitle: "クリップボードにコピー")
        alert.addButton(withTitle: "キャンセル")
        
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            captureViewModel.saveToFile(image)
        case .alertSecondButtonReturn:
            captureViewModel.saveToClipboard(image)
            // 保存完了通知
            let notification = NSUserNotification()
            notification.title = "コピー完了"
            notification.informativeText = "スクリーンショットがクリップボードにコピーされました"
            NSUserNotificationCenter.default.deliver(notification)
            captureViewModel.exitEditor()
        default:
            break
        }
    }
}

// キャプチャ中のオーバーレイビュー
struct CaptureOverlayView: View {
    let isFullScreen: Bool
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.01) // ほぼ透明だがイベントをキャッチするため
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Button(action: onCancel) {
                        Text("キャンセル")
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Spacer()
                }
                
                Spacer()
                
                if isFullScreen {
                    Text("画面をクリックしてスクリーンショットを撮影")
                        .font(.headline)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .padding(.bottom, 40)
                } else {
                    Text("範囲を選択してスクリーンショットを撮影")
                        .font(.headline)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .padding(.bottom, 40)
                }
            }
            .padding()
        }
    }
}

struct MainMenuView_Previews: PreviewProvider {
    static var previews: some View {
        MainMenuView()
            .environmentObject(CaptureViewModel())
    }
}

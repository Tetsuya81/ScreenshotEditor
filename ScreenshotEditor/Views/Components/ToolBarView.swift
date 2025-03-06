//
//  ToolBarView.swift
//  ScreenshotEditor
//
//  Created by Tokunaga Tetsuya on 2025/03/06.
//

import SwiftUI

struct ToolbarView: View {
    @Binding var selectedTool: DrawingTool
    @Binding var selectedColor: Color
    @Binding var lineWidth: CGFloat
    
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @State private var showColorPicker = false
    @State private var showLineWidthPicker = false
    
    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .black, .white
    ]
    
    private let lineWidths: [CGFloat] = [1, 2, 4, 8, 12, 16]
    
    var body: some View {
        HStack {
            // ツール選択部分
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(DrawingTool.allCases) { tool in
                        Button(action: {
                            selectedTool = tool
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 18))
                                    .foregroundColor(selectedTool == tool ? .accentColor : .primary)
                                    .frame(width: 24, height: 24)
                                
                                Text(tool.name)
                                    .font(.caption2)
                                    .foregroundColor(selectedTool == tool ? .accentColor : .primary)
                            }
                            .padding(6)
                            .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 50)
            
            Divider()
                .padding(.vertical, 4)
            
            // 色選択部分
            Button(action: {
                showColorPicker.toggle()
            }) {
                Circle()
                    .fill(selectedColor)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showColorPicker) {
                ColorPickerView(selectedColor: $selectedColor)
            }
            
            // 線幅選択部分
            Button(action: {
                showLineWidthPicker.toggle()
            }) {
                Image(systemName: "lineweight")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showLineWidthPicker) {
                LineWidthPickerView(lineWidth: $lineWidth)
            }
            
            Spacer()
            
            // キャンセルボタン
            Button(action: onCancel) {
                Text("キャンセル")
                    .font(.system(size: 14))
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            
            // 保存ボタン
            Button(action: onSave) {
                Text("保存")
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .frame(height: 50)
    }
}

struct ColorPickerView: View {
    @Binding var selectedColor: Color
    
    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink,
        .black, .gray, .white
    ]
    
    @State private var customColor: Color = .red
    
    var body: some View {
        VStack(spacing: 12) {
            Text("色を選択")
                .font(.headline)
                .padding(.top, 8)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 30))
            ], spacing: 12) {
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .opacity(color == selectedColor ? 1 : 0)
                        )
                        .onTapGesture {
                            selectedColor = color
                        }
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            Text("カスタムカラー")
                .font(.subheadline)
            
            ColorPicker("", selection: $customColor)
                .labelsHidden()
                .padding(.horizontal)
            
            Button("適用") {
                selectedColor = customColor
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.bottom, 8)
        }
        .frame(width: 250)
        .padding(.vertical, 8)
    }
}

struct LineWidthPickerView: View {
    @Binding var lineWidth: CGFloat
    
    private let lineWidths: [CGFloat] = [1, 2, 4, 8, 12, 16]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("線の太さ")
                .font(.headline)
                .padding(.top, 8)
            
            VStack(spacing: 12) {
                ForEach(lineWidths, id: \.self) { width in
                    Button(action: {
                        lineWidth = width
                    }) {
                        HStack {
                            Rectangle()
                                .fill(Color.primary)
                                .frame(width: 60, height: width)
                                .cornerRadius(width / 2)
                            
                            Text("\(Int(width)) px")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if lineWidth == width {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // カスタム太さスライダー
            VStack(alignment: .leading) {
                Text("カスタム: \(Int(lineWidth)) px")
                    .font(.system(size: 14))
                
                Slider(value: $lineWidth, in: 1...30, step: 1)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 200)
        .padding(.vertical, 8)
    }
}

struct ToolbarView_Previews: PreviewProvider {
    static var previews: some View {
        ToolbarView(
            selectedTool: .constant(.pen),
            selectedColor: .constant(.red),
            lineWidth: .constant(2),
            onSave: {},
            onCancel: {}
        )
    }
}

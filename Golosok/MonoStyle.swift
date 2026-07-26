//
//  MonoStyle.swift
//  Golosok
//
//  Created by kozak_dev on 26.07.2026.
//

import SwiftUI

// MARK: - Shadcn / Vercel Color Tokens
extension Color {
    static let uiCanvas = Color(hex: "#f5f5f5")      // Фон окна
    static let uiPaper = Color(hex: "#ffffff")       // Поверхность карточек
    static let uiSidebar = Color(hex: "#fafafa")     // Фон сайдбара
    static let uiInk = Color(hex: "#0a0a0a")         // Основной текст
    static let uiInkSoft = Color(hex: "#171717")     // Второстепенные темные элементы
    static let uiMidGray = Color(hex: "#737373")     // Мутовый серый текст
    static let uiHairline = Color(hex: "#e5e5e5")    // Тонкие рамки 1px
    static let uiEmber = Color(hex: "#e7000b")       // Деструктивный красный
}

// MARK: - Typography & Fonts
struct UIStyleFont {
    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return Font.system(size: size, weight: weight, design: .default)
    }
    
    static func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        return Font.system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Reusable UI Components

// Карточка с микро-рамкой и скруглением 24px
struct UICard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(20)
            .background(Color.uiPaper)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.uiHairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
    }
}

// Заполненная главная кнопка (Пилюля 18px)
struct UIPrimaryButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(UIStyleFont.body(size: 13, weight: .medium))
                .foregroundColor(.uiPaper)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.uiInk)
                .cornerRadius(18)
        }
        .buttonStyle(.plain)
    }
}

// Контурная secondary кнопка
struct UIOutlineButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(UIStyleFont.body(size: 13, weight: .medium))
                .foregroundColor(.uiInk)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.uiPaper)
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.uiHairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// Деструктивная красная кнопка (Удаление)
struct UIDestructiveButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(UIStyleFont.body(size: 13, weight: .medium))
                .foregroundColor(.uiEmber)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.uiEmber.opacity(0.06))
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.uiEmber.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// Бейдж / Таг
struct UIBadge: View {
    let text: String
    
    var body: some View {
        Text(text.uppercased())
            .font(UIStyleFont.body(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(.uiMidGray)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Color.uiCanvas)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.uiHairline, lineWidth: 1)
            )
    }
}

// MARK: - Hex Color Helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

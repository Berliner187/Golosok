import SwiftUI
import AppKit

// MARK: - Тактильный стиль кнопок
struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Hex Initializer for NSColor
extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    static let transcriptHighlight: NSColor = NSColor(name: nil) { appearance in
        if appearance.name == .darkAqua {
            return NSColor.systemBlue.withAlphaComponent(0.5)
        } else {
            return NSColor.blue.withAlphaComponent(0.18)
        }
    }
}

// MARK: - Hex & Dynamic Initializers for SwiftUI Color
extension Color {
    init(hex: String) {
        self.init(NSColor(hex: hex))
    }
    
    static func dynamic(light: String, dark: String) -> Color {
        return Color(NSColor(name: nil) { appearance in
            if appearance.name == .darkAqua {
                return NSColor(hex: dark)
            } else {
                return NSColor(hex: light)
            }
        })
    }
    
    // MARK: - Shadcn / Vercel Dynamic Tokens
    static let uiCanvas = dynamic(light: "#f5f5f5", dark: "#000000")
    static let uiPaper = dynamic(light: "#ffffff", dark: "#121212")
    static let uiSidebar = dynamic(light: "#fafafa", dark: "#09090b")
    static let uiInk = dynamic(light: "#0a0a0a", dark: "#fafafa")
    static let uiInkSoft = dynamic(light: "#171717", dark: "#d4d4d8")
    static let uiMidGray = dynamic(light: "#737373", dark: "#a1a1aa")
    static let uiHairline = dynamic(light: "#e5e5e5", dark: "#27272a")
    static let uiWarn = dynamic(light: "#FF9F0A", dark: "#F59E0B")
    static let uiEmber = dynamic(light: "#e7000b", dark: "#ef4444")
    
    static let uiInverseBlock = dynamic(light: "#0a0a0a", dark: "#18181b")
    static let uiInverseBorder = dynamic(light: "#0a0a0a", dark: "#27272a")
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

// MARK: - Базовые ТАКТИЛЬНЫЕ UI Компоненты

struct UICard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.uiPaper))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.uiHairline, lineWidth: 1))
    }
}

struct UIOutlineButton: View {
    let title: LocalizedStringKey
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
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.uiHairline, lineWidth: 1))
        }
        .buttonStyle(TactileButtonStyle()) // ТАКТИЛЬНЫЙ СТИЛЬ
    }
}

struct UIDestructiveButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(UIStyleFont.body(size: 13, weight: .medium))
                .foregroundColor(.uiEmber)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.uiEmber.opacity(0.1))
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.uiEmber.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(TactileButtonStyle()) // ТАКТИЛЬНЫЙ СТИЛЬ
    }
}

struct UIPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(UIStyleFont.body(size: 13, weight: .medium))
                .foregroundColor(Color.dynamic(light: "#ffffff", dark: "#000000"))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.uiInk)
                .cornerRadius(18)
        }
        .buttonStyle(TactileButtonStyle()) // ТАКТИЛЬНЫЙ СТИЛЬ
    }
}

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
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.uiHairline, lineWidth: 1))
    }
}

// MARK: - Шиммер (бегущий блик для скелетонов)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.5), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: geo.size.width * (phase * 1.8 - 0.5))
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

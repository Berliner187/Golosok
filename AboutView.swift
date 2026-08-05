import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    var currentVersionStr: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.8.1"
        return "v\(ver)"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 1. ИКОНКА И ЗАГОЛОВОК
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                
                Text("Голосок")
                    .font(UIStyleFont.display(size: 20, weight: .bold))
                    .foregroundColor(.uiInk)
                
                UIBadge(text: currentVersionStr)
            }
            
            // 2. ОПИСАНИЕ
            Text("Автоматический ввод надиктованного текста и расшифровка аудиофайлов. Локальная обработка речи без передачи данных посторонним.")
                .font(UIStyleFont.body(size: 12, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(.uiMidGray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
            
            Divider().background(Color.uiHairline)
            
            // 3. ТЕХНИЧЕСКИЙ СТЕК
            HStack(spacing: 8) {
                TechBadge(text: "GIGAAM V3")
                TechBadge(text: "APPLE SILICON")
                TechBadge(text: "CORE ML")
            }
            
            Divider().background(Color.uiHairline)
            
            // 4. КНОПКИ
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    AboutLinkButton(title: "GitHub", icon: "terminal.fill") {
                        openURL(URL(string: "https://github.com/Berliner187/Golosok")!)
                    }
                    AboutLinkButton(title: "Сайт", icon: "globe") {
                        openURL(URL(string: "https://golosok.space")!)
                    }
                }
                
                HStack(spacing: 8) {
                    AboutLinkButton(title: "Поддержка", icon: "envelope") {
                        openURL(URL(string: "mailto:support@golosok.space")!)
                    }
                    AboutLinkButton(title: "Релизы", icon: "doc.text") {
                        openURL(URL(string: "https://github.com/Berliner187/Golosok/releases")!)
                    }
                }
            }
            
            Divider().background(Color.uiHairline)
            
            // 5. КНОПКА ЗАКРЫТИЯ И ПОДВАЛ
            HStack {
                Text("Design & Development by Kozak • 2026")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.uiMidGray)
                
                Spacer()
                
                UIOutlineButton(title: "Закрыть") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(Color.uiPaper)
    }
}

struct TechBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.uiCanvas)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.uiHairline, lineWidth: 1))
            .foregroundColor(.uiInk)
    }
}

struct AboutLinkButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(UIStyleFont.body(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.uiCanvas)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.uiHairline, lineWidth: 1))
            .foregroundColor(.uiInk)
        }
        .buttonStyle(TactileButtonStyle())
    }
}

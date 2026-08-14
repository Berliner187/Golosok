import SwiftUI

// MARK: - Менеджер промптов (список / удалить / редактировать / создать)

struct PromptManagerView: View {
    @ObservedObject private var store = PromptStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var editing: AIPromptTemplate?
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.uiHairline)
            list
            Divider().background(Color.uiHairline)
            footer
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 420, idealHeight: 560)
        .background(Color.uiPaper)
        .sheet(item: $editing) { prompt in
            PromptEditorView(prompt: prompt)
        }
        .sheet(isPresented: $creating) {
            PromptEditorView(prompt: nil)
        }
    }

    private var header: some View {
        HStack {
            Text("Промпты")
                .font(UIStyleFont.display(size: 15, weight: .bold))
                .foregroundColor(.uiInk)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.uiMidGray)
                    .frame(width: 28, height: 28)
                    .background(Color.uiSidebar)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.uiHairline, lineWidth: 1))
            }
            .buttonStyle(TactileButtonStyle())
        }
        .padding(20)
        .padding(.bottom, 4)
    }

    private var list: some View {
        List {
            ForEach(store.templates) { prompt in
                row(prompt)
                    .contextMenu {
                        if !prompt.isProtected {
                            Button(role: .destructive) {
                                store.delete(id: prompt.id)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func row(_ prompt: AIPromptTemplate) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.uiCanvas)
                        .frame(width: 30, height: 30)
                    Image(systemName: prompt.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.uiInk)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if prompt.isCustom {
                        Text(prompt.title)
                            .font(UIStyleFont.body(size: 13, weight: .medium))
                            .foregroundColor(.uiInk)
                    } else {
                        Text(LocalizedStringKey(prompt.title))
                            .font(UIStyleFont.body(size: 13, weight: .medium))
                            .foregroundColor(.uiInk)
                    }
                    Text(prompt.system)
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(.uiMidGray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { editing = prompt }

            if prompt.isProtected {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.uiMidGray)
                    .help("Этот промпт нельзя удалить")
            } else {
                Button(action: { store.delete(id: prompt.id) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.uiMidGray)
                        .frame(width: 26, height: 26)
                        .background(Color.uiCanvas)
                        .clipShape(Circle())
                }
                .buttonStyle(TactileButtonStyle())
                .help("Удалить")
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: { creating = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Новый промпт")
                        .font(UIStyleFont.body(size: 13, weight: .medium))
                }
                .foregroundColor(.uiInk)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.uiSidebar)
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.uiHairline, lineWidth: 1))
            }
            .buttonStyle(TactileButtonStyle())
            Spacer()
            Text("\(store.templates.count)")
                .font(UIStyleFont.body(size: 12, weight: .regular))
                .foregroundColor(.uiMidGray)
        }
        .padding(20)
    }
}

// MARK: - Редактор/создание промпта

struct PromptEditorView: View {
    let prompt: AIPromptTemplate?
    @ObservedObject private var store = PromptStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var icon: String = "sparkles"
    @State private var system: String = ""

    private static let palette: [String] = [
        "sparkles", "wrench.and.screwdriver", "briefcase", "pencil.and.outline",
        "text.quote", "checklist", "doc.text", "character.cursor.ibeam",
        "globe", "waveform", "bolt.fill", "tag",
        "lightbulb", "target", "envelope", "questionmark"
    ]

    private var isEditingExisting: Bool { prompt != nil }
    private var isBuiltin: Bool { prompt.map { AIPromptDefaults.builtinIDs.contains($0.id) } ?? false }

    private var canSave: Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = system.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !s.isEmpty
    }

    private var titleKey: LocalizedStringKey {
        isEditingExisting ? "Редактировать промпт" : "Новый промпт"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.uiHairline)
            ScrollView {
                content
            }
            Divider().background(Color.uiHairline)
            footer
        }
        .frame(minWidth: 540, idealWidth: 560, minHeight: 520, idealHeight: 620)
        .background(Color.uiPaper)
        .onAppear { seed() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.uiCanvas).frame(width: 30, height: 30)
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(.uiInk)
            }
            Text(titleKey)
                .font(UIStyleFont.display(size: 15, weight: .bold))
                .foregroundColor(.uiInk)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.uiMidGray)
                    .frame(width: 28, height: 28)
                    .background(Color.uiSidebar)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.uiHairline, lineWidth: 1))
            }
            .buttonStyle(TactileButtonStyle())
        }
        .padding(20)
        .padding(.bottom, 4)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Заголовок
            VStack(alignment: .leading, spacing: 6) {
                Text("Заголовок")
                    .font(UIStyleFont.body(size: 11, weight: .medium))
                    .foregroundColor(.uiMidGray)
                TextField("Например: Краткий пересказ", text: $title)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(UIStyleFont.body(size: 13, weight: .regular))
                    .foregroundColor(.uiInk)
                    .padding(8)
                    .background(Color.uiCanvas)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
            }

            // Иконка
            VStack(alignment: .leading, spacing: 8) {
                Text("Иконка")
                    .font(UIStyleFont.body(size: 11, weight: .medium))
                    .foregroundColor(.uiMidGray)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Self.palette, id: \.self) { symbol in
                        Button {
                            icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(icon == symbol ? Color.uiPaper : Color.uiInk)
                                .frame(height: 34)
                                .frame(maxWidth: .infinity)
                                .background(icon == symbol ? AnyShapeStyle(Color.uiInk) : AnyShapeStyle(Color.uiCanvas))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(icon == symbol ? Color.uiInk : Color.uiHairline, lineWidth: 1))
                        }
                        .buttonStyle(TactileButtonStyle())
                    }
                }
            }

            // Инструкция
            VStack(alignment: .leading, spacing: 6) {
                Text("Инструкция")
                    .font(UIStyleFont.body(size: 11, weight: .medium))
                    .foregroundColor(.uiMidGray)
                TextEditor(text: $system)
                    .font(UIStyleFont.body(size: 13, weight: .regular))
                    .foregroundColor(.uiInk)
                    .scrollContentBackground(.hidden)
                    .frame(height: 180)
                    .padding(8)
                    .background(Color.uiCanvas)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
                Text("Опишите задачу: что ИИ должен сделать с расшифрованным текстом.")
                    .font(UIStyleFont.body(size: 10, weight: .regular))
                    .foregroundColor(.uiMidGray)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if isBuiltin {
                UIOutlineButton(title: "Сбросить") {
                    if let id = prompt?.id { store.reset(id: id); seed() }
                }
            }
            Spacer()
            UIOutlineButton(title: "Отмена") { dismiss() }
            UIPrimaryButton(title: "Сохранить") { save() }
                .disabled(!canSave)
        }
        .padding(20)
    }

    // MARK: - Private

    private func seed() {
        guard let p = prompt else { return }
        title = p.title
        icon = p.icon
        system = p.system
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = system.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !s.isEmpty else { return }
        if let p = prompt {
            var updated = p
            updated.title = t
            updated.icon = icon
            updated.system = s
            store.update(updated)
        } else {
            store.create(title: t, icon: icon, system: s)
        }
        dismiss()
    }
}
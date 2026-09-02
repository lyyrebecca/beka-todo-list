import SwiftUI
import AppKit

struct WidgetView: View {
    @ObservedObject var store: TodoStore
    var onSizeChange: (CGSize) -> Void
    var onMinimize: () -> Void
    var onRequestTextInput: () -> Void
    var onTextInputSessionChanged: (Bool) -> Void
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var shownItems: [TodoItem] {
        store.isExpanded ? store.items : Array(store.items.prefix(store.maxVisible))
    }

    var body: some View {
        Group {
            if store.isMinimized {
                miniWidget
            } else {
                normalWidget
            }
        }
        .onChange(of: store.isAdding) { _, isAdding in
            onTextInputSessionChanged(isAdding || store.editingTextId != nil)
        }
        .onChange(of: store.editingTextId) { _, editingId in
            onTextInputSessionChanged(store.isAdding || editingId != nil)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ContentSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(ContentSizeKey.self) { onSizeChange($0) }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        // 临界阻尼，避免缩小/恢复时出现“果冻式”二次回弹。
        .animation(.spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.08),
                   value: store.isMinimized)
    }

    private var normalWidget: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if let error = store.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
            if store.isShowingArchive {
                archiveRows
            } else {
                rows
            }
            if store.isAdding && !store.isShowingArchive {
                AddRowView(store: store, dark: dark, onRequestTextInput: onRequestTextInput)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(15)
        .frame(width: 350)
        .background(Theme.gradientFill(dark),
                    in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .liquidGlass(tint: Theme.glassTint(dark))
        .overlay(alignment: .top) {
            Theme.topHighlight(dark)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Color.white.opacity(dark ? 0.16 : 0.38), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .padding(6)
        .animation(.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.08), value: store.items)
        .animation(.spring(response: 0.30, dampingFraction: 0.90, blendDuration: 0.05), value: store.isAdding)
        .animation(.spring(response: 0.30, dampingFraction: 0.90, blendDuration: 0.05), value: store.isExpanded)
    }

    private var miniWidget: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        // 从内到外逐步变浅，没有独立白色描边。
                        colors: [Color(red: 0.28, green: 0.22, blue: 0.64).opacity(0.84),
                                 Color(red: 123 / 255, green: 104 / 255, blue: 238 / 255).opacity(0.76),
                                 Color(red: 0.66, green: 0.58, blue: 0.96).opacity(0.76),
                                 Color(red: 0.84, green: 0.79, blue: 1.00).opacity(0.88)],
                        center: UnitPoint(x: 0.38, y: 0.36),
                        startRadius: 0,
                        endRadius: 30
                    )
                )
            Ellipse()
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.62), Color.white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 26, height: 11)
                .blur(radius: 1.6)
                .offset(x: -3, y: -10)
                .blendMode(.screen)
                .allowsHitTesting(false)
            Group {
                Image(systemName: "sparkle")
                    .font(.system(size: 4.5, weight: .semibold))
                    .offset(x: 9, y: -8)
                Circle().frame(width: 2, height: 2).offset(x: -11, y: -3)
                Circle().frame(width: 1.5, height: 1.5).offset(x: 11, y: 7)
                Circle().frame(width: 1.3, height: 1.3).offset(x: -7, y: 11)
            }
            .foregroundStyle(Color.white.opacity(0.78))
            .shadow(color: Color.white.opacity(0.65), radius: 1.5)
            .allowsHitTesting(false)
            Text("干")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color(red: 0.34, green: 0.28, blue: 0.42).opacity(0.42),
                        radius: 1.5, y: 1)
        }
        .frame(width: 40, height: 40)
        // 不使用 Material/glassEffect：它会在透明窗口里产生未裁切的方形底。
        // 圆球的玻璃感完全由由内到外变浅的径向渐变和高光构成。
        .shadow(color: Color(red: 0.52, green: 0.43, blue: 0.80).opacity(0.20),
                radius: 6, y: 3)
        .padding(4)
        .scaleEffect(store.isMiniDragging ? 1.07 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.86, blendDuration: 0.04),
                   value: store.isMiniDragging)
        .contentShape(Circle())
        .allowsHitTesting(false)
        .accessibilityLabel("展开贝卡待办")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent(dark))
            Text("贝卡の Todo list 🌟")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary(dark))
            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent(dark))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Theme.rowFill(dark)))
            }
            Spacer()
            Button {
                store.isShowingArchive.toggle()
                store.isAdding = false
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: store.isShowingArchive
                          ? "checklist" : "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .medium))
                    if !store.archived.isEmpty && !store.isShowingArchive {
                        Circle()
                            .fill(Theme.accent(dark))
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -1)
                    }
                }
                .foregroundStyle(store.isShowingArchive
                                 ? Theme.accent(dark) : Theme.textSecondary(dark))
            }
            .buttonStyle(.plain)
            .help(store.isShowingArchive ? "返回待办" : "查看已完成")
            Button(action: onMinimize) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.textSecondary(dark))
            }
            .buttonStyle(.plain)
            .help("最小化为屏幕右侧圆圈")
            Button {
                let willAdd = !store.isAdding
                if willAdd { onRequestTextInput() }
                store.isAdding = willAdd
                store.isShowingArchive = false
                if willAdd { store.isExpanded = false }
            } label: {
                Image(systemName: store.isAdding ? "xmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(store.isAdding ? Theme.textSecondary(dark) : Theme.accent(dark))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(store.isAdding ? "关闭添加框" : "添加待办（⌘N）")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rows: some View {
        if store.items.isEmpty && !store.isAdding {
            Text("暂无待办，点右上角 + 添加")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary(dark))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else if store.isExpanded && store.items.count > store.maxVisible {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        TodoRowView(item: item, store: store, dark: dark,
                                    index: index, count: store.items.count)
                    }
                }
            }
            .frame(maxHeight: 46 * 8)
        } else {
            ForEach(Array(shownItems.enumerated()), id: \.element.id) { index, item in
                TodoRowView(item: item, store: store, dark: dark,
                            index: index, count: shownItems.count)
            }
            if !store.isExpanded && store.overflowCount > 0 {
                Button {
                    store.isExpanded = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 12))
                        Text("还有 \(store.overflowCount) 条")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(Theme.accent(dark))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.rowFill(dark))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        if store.isExpanded && store.items.count > store.maxVisible {
            Button {
                store.isExpanded = false
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 12))
                    Text("收起")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    Spacer()
                }
                .foregroundStyle(Theme.textSecondary(dark))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var archiveRows: some View {
        if store.archived.isEmpty {
            Text("还没有已完成的待办")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary(dark))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(store.archived) { item in
                        HStack(spacing: 9) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.accent(dark).opacity(0.75))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary(dark))
                                    .lineLimit(2)
                                if let completedAt = item.completedAt {
                                    Text(Self.archiveDateFormatter.string(from: completedAt))
                                        .font(.system(size: 10, design: .rounded))
                                        .foregroundStyle(Theme.textSecondary(dark))
                                }
                            }
                            Spacer(minLength: 4)
                            Button { store.restoreArchived(item.id) } label: {
                                Image(systemName: "arrow.uturn.backward.circle")
                            }
                            .buttonStyle(.plain)
                            .help("恢复为待办")
                            Button { store.deleteArchived(item.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.textSecondary(dark))
                            .help("永久删除")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Theme.rowFill(dark)))
                    }
                }
            }
            .frame(maxHeight: 46 * 7)
            Button("清空全部已完成") { store.clearArchived() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary(dark))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
    }

    private static let archiveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm 完成"
        return formatter
    }()
}

// MARK: - Row

struct TodoRowView: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    let dark: Bool
    let index: Int
    let count: Int
    @State private var dragOffset: CGFloat = 0

    private var overdue: Bool { store.isOverdue(item) }
    private var isDragging: Bool { store.draggingId == item.id }
    private static let rowStride: CGFloat = 45

    var body: some View {
        HStack(spacing: 9) {
            checkButton
            if item.priority != .normal {
                Image(systemName: item.priority == .urgent ? "exclamationmark.2" : "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.priority == .urgent
                                     ? Color(red: 0.94, green: 0.42, blue: 0.56)
                                     : Color(red: 0.93, green: 0.68, blue: 0.20))
                    .help(item.priority.title)
            }
            Text(item.text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .strikethrough(item.completed, color: Theme.textSecondary(dark))
                .foregroundStyle(item.completed
                                 ? Theme.textSecondary(dark)
                                 : Theme.textPrimary(dark))
                .lineLimit(2)
                .contentShape(Rectangle())
                .onTapGesture { beginEditing() }
                .help("点按编辑内容和截止时间")
            Spacer(minLength: 4)
            if let schedule = item.schedule {
                scheduleLabel(schedule)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing() }
                    .help("点按修改截止时间")
            }
            Button(action: beginEditing) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary(dark))
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .help("编辑内容和截止时间")
            handle
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(item.completed ? Color.clear : Theme.rowFill(dark))
        )
        .opacity(item.completed ? 0.45 : 1)
        .offset(y: isDragging ? dragOffset : 0)
        .zIndex(isDragging ? 10 : 0)
        .contextMenu {
            Button("编辑待办…") { beginEditing() }
            if item.dueDate != nil {
                Button("清除截止时间") { store.setDue(item.id, nil) }
            }
            Divider()
            Button("删除", role: .destructive) { store.delete(item.id) }
        }
        .popover(isPresented: Binding(
            get: { store.editingTextId == item.id },
            set: { if !$0 { store.editingTextId = nil } }
        )) {
            TodoEditorView(item: item, store: store)
        }
    }

    private func beginEditing() {
        store.editingTextId = item.id
    }

    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isDragging
                             ? Theme.accent(dark)
                             : Theme.textSecondary(dark).opacity(0.8))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .highPriorityGesture(reorderGesture)
            .help("按住拖动调整顺序")
    }

    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if store.draggingId == nil { store.draggingId = item.id }
                let minY = -CGFloat(index) * Self.rowStride
                let maxY = CGFloat(count - 1 - index) * Self.rowStride
                dragOffset = min(max(value.translation.height, minY), maxY)
            }
            .onEnded { _ in
                let steps = Int((dragOffset / Self.rowStride).rounded())
                store.draggingId = nil
                if steps != 0 {
                    dragOffset = 0
                    store.moveItem(id: item.id, to: index + steps)
                } else {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.90)) { dragOffset = 0 }
                }
            }
    }

    private var checkButton: some View {
        Button {
            if item.completed {
                store.undoCompletion(item.id)
            } else {
                store.complete(item.id)
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Theme.accent(dark).opacity(0.65), lineWidth: 1.5)
                if item.completed {
                    Circle().fill(Theme.accent(dark))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 19, height: 19)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(item.completed ? "撤销完成" : "标记为完成")
    }

    private func dueLabel(_ due: Date) -> some View {
        HStack(spacing: 3) {
            if overdue {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(Self.format(due))
                .font(.system(size: 11, weight: overdue ? .bold : .medium,
                              design: .rounded))
        }
        .foregroundStyle(overdue ? Color(red: 0.94, green: 0.42, blue: 0.62)
                                 : Theme.accent(dark).opacity(0.85))
    }

    private func scheduleLabel(_ schedule: TodoSchedule) -> some View {
        HStack(spacing: 3) {
            if overdue {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(Self.format(schedule))
                .font(.system(size: 10, weight: overdue ? .bold : .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(overdue ? Color(red: 0.94, green: 0.42, blue: 0.62)
                                 : Theme.accent(dark).opacity(0.88))
    }

    static func format(_ schedule: TodoSchedule) -> String {
        switch schedule.mode {
        case .none:
            return ""
        case .deadline:
            return schedule.date.map { "截止 " + format($0) } ?? "截止"
        case .day:
            return schedule.date.map(format) ?? "某一天"
        case .period:
            guard let start = schedule.startDate, let end = schedule.endDate else { return "期间" }
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            var result = formatter.string(from: start) + "–" + formatter.string(from: end)
            if schedule.reminderMode == .dailyDuringPeriod {
                result += String(format: " 每天%02d:%02d",
                                 schedule.reminderTimeMinutes / 60,
                                 schedule.reminderTimeMinutes % 60)
            }
            return result
        }
    }

    static func format(_ date: Date) -> String {
        let cal = Calendar.current
        let hm = DateFormatter()
        hm.dateFormat = "HH:mm"
        if cal.isDateInToday(date) { return "今天 " + hm.string(from: date) }
        if cal.isDateInTomorrow(date) { return "明天 " + hm.string(from: date) }
        let md = DateFormatter()
        md.dateFormat = "M月d日"
        return md.string(from: date)
    }
}

// MARK: - Schedule & Priority Fields

struct ScheduleEditorFields: View {
    @Binding var draft: TodoDraft
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("重要级别", systemImage: "flag")
                    .foregroundStyle(Theme.textSecondary(dark))
                Spacer()
                Picker("", selection: $draft.priority) {
                    ForEach(TodoPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            HStack {
                Label("时间模式", systemImage: "calendar")
                    .foregroundStyle(Theme.textSecondary(dark))
                Spacer()
                Picker("", selection: $draft.timeMode) {
                    ForEach(TodoTimeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            scheduleFields
        }
        .font(.system(size: 12, design: .rounded))
        .onChange(of: draft.timeMode) { _, mode in draft.selectTimeMode(mode) }
        .onChange(of: draft.reminderMode) { _, mode in draft.selectReminderMode(mode) }
    }

    @ViewBuilder
    private var scheduleFields: some View {
        switch draft.timeMode {
        case .none:
            EmptyView()
        case .deadline, .day:
            DatePicker(draft.timeMode == .deadline ? "截止" : "日期",
                       selection: $draft.date,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "zh_CN"))
            reminderPicker(options: [
                (.none, "不提醒"),
                (.atTime, draft.timeMode == .deadline ? "截止时" : "当天设定时间"),
                (.dayBefore, "提前一天")
            ])
            if draft.reminderMode == .dayBefore {
                DatePicker("提前一天提醒时间", selection: $draft.reminderClock,
                           displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.compact)
                Text("默认前一天晚上 9:00")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.textSecondary(dark))
            }
        case .period:
            DatePicker("开始", selection: $draft.periodStart, displayedComponents: .date)
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "zh_CN"))
            DatePicker("结束", selection: $draft.periodEnd, displayedComponents: .date)
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "zh_CN"))
            reminderPicker(options: [(.none, "不提醒"), (.dailyDuringPeriod, "期间内每天")])
            if draft.reminderMode == .dailyDuringPeriod {
                DatePicker("每天提醒时间", selection: $draft.reminderClock,
                           displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.compact)
            }
        }
    }

    private func reminderPicker(options: [(TodoReminderMode, String)]) -> some View {
        HStack {
            Label("提醒方式", systemImage: "bell")
                .foregroundStyle(Theme.textSecondary(dark))
            Spacer()
            Picker("", selection: $draft.reminderMode) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

// MARK: - Add Row

struct AddRowView: View {
    @ObservedObject var store: TodoStore
    let dark: Bool
    @State private var draft = TodoDraft()
    var onRequestTextInput: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            IMETextField(text: $draft.text,
                         placeholder: "写下新待办…",
                         font: .systemFont(ofSize: 13),
                         textColor: .labelColor,
                         roundedBorder: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(dark ? Color.black.opacity(0.18) : Color.white.opacity(0.5)))

            ScheduleEditorFields(draft: $draft, dark: dark)

            Button(action: commit) {
                HStack(spacing: 6) {
                    Image(systemName: draft.priority == .normal ? "checkmark" : "star.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(draft.priority == .normal ? "添加" : "添加并置顶")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(draft.text.trimmingCharacters(in: .whitespaces).isEmpty
                                           ? Theme.accent(dark).opacity(0.35)
                                           : Theme.accent(dark)))
            }
            .buttonStyle(.plain)
            .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.rowFill(dark)))
        .onAppear { onRequestTextInput() }
        .onExitCommand { store.isAdding = false }
    }

    private func commit() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(text: trimmed, priority: draft.priority, schedule: draft.schedule)
        draft = TodoDraft()
        onRequestTextInput()
    }
}

// MARK: - Todo Editor

struct TodoEditorView: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    @State private var draft: TodoDraft
    @Environment(\.colorScheme) private var scheme

    init(item: TodoItem, store: TodoStore) {
        self.item = item
        self.store = store
        _draft = State(initialValue: TodoDraft(item: item))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑待办")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            IMETextField(text: $draft.text,
                         placeholder: "待办内容",
                         font: .systemFont(ofSize: 13),
                         textColor: .labelColor,
                         roundedBorder: true)
                .frame(height: 22)
            ScheduleEditorFields(draft: $draft, dark: scheme == .dark)
            HStack {
                Button("取消") { store.editingTextId = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存", action: save)
                    .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            (NSApp.delegate as? AppDelegate)?.activateForTextInput()
        }
    }

    private func save() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.update(item.id, text: trimmed, priority: draft.priority, schedule: draft.schedule)
        store.editingTextId = nil
    }
}

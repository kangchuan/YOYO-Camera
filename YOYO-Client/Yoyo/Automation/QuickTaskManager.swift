import Foundation
import SwiftUI

/// Quick task manager - manages tasks added to the quick panel
final class QuickTaskManager: ObservableObject {
    static let shared = QuickTaskManager()

    /// Rule ID list for quick tasks
    @Published var quickTaskRuleIds: [String] = []

    private let userDefaultsKey = "com.anyan.yoyo.quicktask.ruleIds"

    /// A-17: pre-rename key, migrated once so existing quick tasks survive.
    private static let legacyUserDefaultsKey = "com.day1-labs.yoyo.quicktask.ruleIds"

    private static func migrateLegacyDefaultsKey() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: legacyUserDefaultsKey) != nil,
              defaults.data(forKey: "com.anyan.yoyo.quicktask.ruleIds") == nil
        else { return }
        defaults.set(defaults.data(forKey: legacyUserDefaultsKey),
                     forKey: "com.anyan.yoyo.quicktask.ruleIds")
        defaults.removeObject(forKey: legacyUserDefaultsKey)
        debugLog("🔀 已把快捷任务从旧 key 迁移到 com.anyan.yoyo.quicktask.ruleIds")
    }

    private init() {
        Self.migrateLegacyDefaultsKey()
        loadQuickTasks()
    }

    /// Add a task to the quick panel
    func addQuickTask(ruleId: String) {
        guard !quickTaskRuleIds.contains(ruleId) else { return }
        quickTaskRuleIds.append(ruleId)
        saveQuickTasks()
    }

    /// Remove a task from the quick panel
    func removeQuickTask(ruleId: String) {
        quickTaskRuleIds.removeAll { $0 == ruleId }
        saveQuickTasks()
    }

    /// Check whether a task is in the quick panel
    func isInQuickTasks(ruleId: String) -> Bool {
        quickTaskRuleIds.contains(ruleId)
    }

    /// Toggle the quick panel state of a task
    func toggleQuickTask(ruleId: String) {
        if isInQuickTasks(ruleId: ruleId) {
            removeQuickTask(ruleId: ruleId)
        } else {
            addQuickTask(ruleId: ruleId)
        }
    }

    /// Reorder quick tasks
    func reorderQuickTasks(from source: IndexSet, to destination: Int) {
        quickTaskRuleIds.move(fromOffsets: source, toOffset: destination)
        saveQuickTasks()
    }

    // MARK: - persistence

    private func saveQuickTasks() {
        do {
            let data = try JSONEncoder().encode(quickTaskRuleIds)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            debugLog("✅ 快捷任务已保存: \(quickTaskRuleIds.count) 个")
        } catch {
            debugLog("❌ 保存快捷任务失败: \(error)")
        }
    }

    private func loadQuickTasks() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            debugLog("ℹ️ 未找到已保存的快捷任务")
            return
        }

        do {
            quickTaskRuleIds = try JSONDecoder().decode([String].self, from: data)
            debugLog("✅ 已加载快捷任务: \(quickTaskRuleIds.count) 个")
        } catch {
            debugLog("❌ 加载快捷任务失败: \(error)")
            quickTaskRuleIds = []
        }
    }
}

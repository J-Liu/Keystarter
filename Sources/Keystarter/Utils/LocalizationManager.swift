// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}

/// Manages localization for the app.
final class LocalizationManager {

    static let shared = LocalizationManager()

    enum Language: String, CaseIterable {
        case english = "en"
        case simplifiedChinese = "zh-Hans"
        case traditionalChinese = "zh-Hant"

        var displayName: String {
            switch self {
            case .english: return "English"
            case .simplifiedChinese: return "简体中文"
            case .traditionalChinese: return "繁體中文"
            }
        }
    }

    private var strings: [String: String] = [:]

    private init() {
        loadLanguage()
    }

    var currentLanguage: Language {
        get {
            let code = UserDefaults.standard.string(forKey: "app.language") ?? Language.english.rawValue
            return Language(rawValue: code) ?? .english
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "app.language")
            loadLanguage()
        }
    }

    private func loadLanguage() {
        strings = localizedStrings[currentLanguage] ?? [:]
        // Post notification for menu updates
        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }

    func localized(_ key: String) -> String {
        return strings[key] ?? key
    }

    // MARK: - Localized Strings

    private let localizedStrings: [Language: [String: String]] = [
        .english: [
            // Settings Window
            "settings.title": "Keystarter Settings",
            "settings.tab.general": "General",
            "settings.tab.clipboard": "Clipboard",
            "settings.tab.advanced": "Advanced",
            "settings.tab.about": "About",

            // General Tab
            "settings.language": "Language:",
            "settings.hotkey": "Hotkey:",
            "settings.hotkey.hint": "Click to record",
            "settings.statusbar": "Status Bar:",
            "settings.statusbar.system": "System Default",
            "settings.statusbar.light": "Light",
            "settings.statusbar.dark": "Dark",
            "settings.statusbar.hidden": "Hidden",
            "settings.cornerRadius": "Corner Radius:",
            "settings.opacity": "Opacity:",
            "settings.groupBy": "Group By:",
            "settings.groupBy.frequency": "Most Used",
            "settings.groupBy.category": "Category",
            "settings.groupBy.letter": "Letter",
            "settings.startAtLogin": "Start at Login:",
            "settings.startAtLogin.checkbox": "Automatically start at login",
            "settings.dockIcon": "Dock Icon:",
            "settings.dockIcon.checkbox": "Show Dock icon",
            "settings.log": "Log:",
            "settings.log.enable": "Enable",
            "settings.log.choose": "Choose...",
            "settings.permissions": "Check Permissions...",

            // Update Settings
            "settings.update": "Update:",
            "settings.update.frequency": "Check for updates:",
            "settings.update.frequency.everyLaunch": "Every launch",
            "settings.update.frequency.daily": "Daily",
            "settings.update.frequency.weekly": "Weekly",
            "settings.update.frequency.monthly": "Monthly",
            "settings.update.frequency.never": "Never",
            "settings.update.checkNow": "Check Now",

            // Clipboard Tab
            "settings.clipboard.hotkey": "Hotkey:",
            "settings.clipboard.maxCount": "Max Count:",
            "settings.clipboard.maxCount.hint": "entries (groups: %@)",
            "settings.clipboard.maxDays": "Max Days:",
            "settings.clipboard.maxDays.hint": "days",
            "settings.clipboard.clear": "Clear Clipboard History",

            // About Tab
            "settings.about.version": "Version %@",
            "settings.about.copyright": "© 2026 Jia Liu. All rights reserved.",

            // Advanced Tab
            "settings.advanced.ignoredApps": "Ignored Apps:",
            "settings.advanced.ignoredApps.empty": "No ignored apps",
            "settings.advanced.ignoredApps.add": "Add...",
            "settings.advanced.ignoredApps.remove": "Remove",
            "settings.advanced.ignoredApps.addTitle": "Select App to Ignore",

            // Launcher Window
            "launcher.search.placeholder": "Search apps, files...",
            "launcher.grid.recent": "Recent",
            "launcher.grid.allApps": "All Apps",

            // Clipboard Panel
            "clipboard.empty": "No clipboard history",
            "clipboard.clear": "Clear History",
            "clipboard.settings": "Settings...",
            "clipboard.group.title": "Clipboard History",

            // Menu Items
            "menu.about": "About Keystarter",
            "menu.settings": "Settings...",
            "menu.checkUpdates": "Check for Updates...",
            "menu.checkPermissions": "Check Permissions...",
            "menu.closeWindow": "Close Window",
            "menu.quit": "Quit Keystarter",

            // Alerts
            "alert.clearHistory.title": "Clear Clipboard History?",
            "alert.clearHistory.message": "This will delete all clipboard entries.",
            "alert.clear": "Clear",
            "alert.cancel": "Cancel",
            "alert.permissions.title": "Accessibility Permission Required",
            "alert.permissions.message": "Keystarter needs Accessibility permission to paste content.",
            "alert.grant": "Grant Permission",

            // Permissions Status
            "permissions.status.title": "Permission Status",
            "permissions.status.allGranted": "All required permissions have been granted:",
            "permissions.status.ok": "OK",
            "permissions.status.accessibility": "Accessibility",
            "permissions.status.inputMonitoring": "Input Monitoring",

            // System Commands
            "command.sleep": "Sleep",
            "command.lock": "Lock Screen",
            "command.empty.trash": "Empty Trash",
            "command.restart": "Restart",
            "command.shutdown": "Shut Down",
            "command.logout": "Log Out",
            "command.pressEnter": "Press Enter to %@",
        ],

        .simplifiedChinese: [
            // Settings Window
            "settings.title": "Keystarter 设置",
            "settings.tab.general": "通用",
            "settings.tab.clipboard": "剪切板",
            "settings.tab.advanced": "高级",
            "settings.tab.about": "关于",

            // General Tab
            "settings.language": "语言：",
            "settings.hotkey": "快捷键：",
            "settings.hotkey.hint": "点击录制",
            "settings.statusbar": "状态栏：",
            "settings.statusbar.system": "跟随系统",
            "settings.statusbar.light": "浅色",
            "settings.statusbar.dark": "深色",
            "settings.statusbar.hidden": "隐藏",
            "settings.cornerRadius": "圆角：",
            "settings.opacity": "透明度：",
            "settings.groupBy": "分组方式：",
            "settings.groupBy.frequency": "最常使用",
            "settings.groupBy.category": "按类别",
            "settings.groupBy.letter": "按字母",
            "settings.startAtLogin": "开机启动：",
            "settings.startAtLogin.checkbox": "开机时自动启动",
            "settings.dockIcon": "Dock 图标：",
            "settings.dockIcon.checkbox": "显示 Dock 图标",
            "settings.log": "日志：",
            "settings.log.enable": "启用",
            "settings.log.choose": "选择...",
            "settings.permissions": "检查权限...",

            // Update Settings
            "settings.update": "更新：",
            "settings.update.frequency": "检查更新：",
            "settings.update.frequency.everyLaunch": "每次启动",
            "settings.update.frequency.daily": "每天",
            "settings.update.frequency.weekly": "每周",
            "settings.update.frequency.monthly": "每月",
            "settings.update.frequency.never": "从不",
            "settings.update.checkNow": "立即检查",

            // Clipboard Tab
            "settings.clipboard.hotkey": "快捷键：",
            "settings.clipboard.maxCount": "最大条数：",
            "settings.clipboard.maxCount.hint": "条 (分组: %@)",
            "settings.clipboard.maxDays": "保留天数：",
            "settings.clipboard.maxDays.hint": "天",
            "settings.clipboard.clear": "清空剪切板历史",

            // About Tab
            "settings.about.version": "版本 %@",
            "settings.about.copyright": "© 2026 Jia Liu. 保留所有权利。",

            // Advanced Tab
            "settings.advanced.ignoredApps": "忽略的应用：",
            "settings.advanced.ignoredApps.empty": "没有忽略的应用",
            "settings.advanced.ignoredApps.add": "添加...",
            "settings.advanced.ignoredApps.remove": "移除",
            "settings.advanced.ignoredApps.addTitle": "选择要忽略的应用",

            // Launcher Window
            "launcher.search.placeholder": "搜索应用、文件...",
            "launcher.grid.recent": "最近使用",
            "launcher.grid.allApps": "所有应用",

            // Clipboard Panel
            "clipboard.empty": "无剪切板历史",
            "clipboard.clear": "清空历史",
            "clipboard.settings": "设置...",
            "clipboard.group.title": "剪切板历史",

            // Menu Items
            "menu.about": "关于 Keystarter",
            "menu.settings": "设置...",
            "menu.checkUpdates": "检查更新...",
            "menu.checkPermissions": "检查权限...",
            "menu.closeWindow": "关闭窗口",
            "menu.quit": "退出 Keystarter",

            // Alerts
            "alert.clearHistory.title": "清空剪切板历史？",
            "alert.clearHistory.message": "这将删除所有剪切板条目。",
            "alert.clear": "清空",
            "alert.cancel": "取消",
            "alert.permissions.title": "需要辅助功能权限",
            "alert.permissions.message": "Keystarter 需要辅助功能权限来粘贴内容。",
            "alert.grant": "授予权限",

            // Permissions Status
            "permissions.status.title": "权限状态",
            "permissions.status.allGranted": "所有必需权限已授予：",
            "permissions.status.ok": "确定",
            "permissions.status.accessibility": "辅助功能",
            "permissions.status.inputMonitoring": "输入监控",

            // System Commands
            "command.sleep": "睡眠",
            "command.lock": "锁定屏幕",
            "command.empty.trash": "清空废纸篓",
            "command.restart": "重新启动",
            "command.shutdown": "关机",
            "command.logout": "注销",
            "command.pressEnter": "按回车执行%@",
        ],

        .traditionalChinese: [
            // Settings Window
            "settings.title": "Keystarter 設定",
            "settings.tab.general": "一般",
            "settings.tab.clipboard": "剪貼簿",
            "settings.tab.advanced": "進階",
            "settings.tab.about": "關於",

            // General Tab
            "settings.language": "語言：",
            "settings.hotkey": "快速鍵：",
            "settings.hotkey.hint": "點擊錄製",
            "settings.statusbar": "狀態列：",
            "settings.statusbar.system": "跟隨系統",
            "settings.statusbar.light": "淺色",
            "settings.statusbar.dark": "深色",
            "settings.statusbar.hidden": "隱藏",
            "settings.cornerRadius": "圓角：",
            "settings.opacity": "透明度：",
            "settings.groupBy": "分組方式：",
            "settings.groupBy.frequency": "最常使用",
            "settings.groupBy.category": "按類別",
            "settings.groupBy.letter": "按字母",
            "settings.startAtLogin": "開機啟動：",
            "settings.startAtLogin.checkbox": "開機時自動啟動",
            "settings.dockIcon": "Dock 圖示：",
            "settings.dockIcon.checkbox": "顯示 Dock 圖示",
            "settings.log": "日誌：",
            "settings.log.enable": "啟用",
            "settings.log.choose": "選擇...",
            "settings.permissions": "檢查權限...",

            // Update Settings
            "settings.update": "更新：",
            "settings.update.frequency": "檢查更新：",
            "settings.update.frequency.everyLaunch": "每次啟動",
            "settings.update.frequency.daily": "每天",
            "settings.update.frequency.weekly": "每週",
            "settings.update.frequency.monthly": "每月",
            "settings.update.frequency.never": "從不",
            "settings.update.checkNow": "立即檢查",

            // Clipboard Tab
            "settings.clipboard.hotkey": "快速鍵：",
            "settings.clipboard.maxCount": "最大條數：",
            "settings.clipboard.maxCount.hint": "條 (分組: %@)",
            "settings.clipboard.maxDays": "保留天數：",
            "settings.clipboard.maxDays.hint": "天",
            "settings.clipboard.clear": "清空剪貼簿歷史",

            // About Tab
            "settings.about.version": "版本 %@",
            "settings.about.copyright": "© 2026 Jia Liu. 保留所有權利。",

            // Advanced Tab
            "settings.advanced.ignoredApps": "忽略的應用：",
            "settings.advanced.ignoredApps.empty": "沒有忽略的應用",
            "settings.advanced.ignoredApps.add": "新增...",
            "settings.advanced.ignoredApps.remove": "移除",
            "settings.advanced.ignoredApps.addTitle": "選擇要忽略的應用",

            // Launcher Window
            "launcher.search.placeholder": "搜尋應用、檔案...",
            "launcher.grid.recent": "最近使用",
            "launcher.grid.allApps": "所有應用",

            // Clipboard Panel
            "clipboard.empty": "無剪貼簿歷史",
            "clipboard.clear": "清空歷史",
            "clipboard.settings": "設定...",
            "clipboard.group.title": "剪貼簿歷史",

            // Menu Items
            "menu.about": "關於 Keystarter",
            "menu.settings": "設定...",
            "menu.checkUpdates": "檢查更新...",
            "menu.checkPermissions": "檢查權限...",
            "menu.closeWindow": "關閉視窗",
            "menu.quit": "結束 Keystarter",

            // Alerts
            "alert.clearHistory.title": "清空剪貼簿歷史？",
            "alert.clearHistory.message": "這將刪除所有剪貼簿條目。",
            "alert.clear": "清空",
            "alert.cancel": "取消",
            "alert.permissions.title": "需要輔助功能權限",
            "alert.permissions.message": "Keystarter 需要輔助功能權限來貼上內容。",
            "alert.grant": "授予權限",

            // Permissions Status
            "permissions.status.title": "權限狀態",
            "permissions.status.allGranted": "所有必需權限已授予：",
            "permissions.status.ok": "確定",
            "permissions.status.accessibility": "輔助功能",
            "permissions.status.inputMonitoring": "輸入監控",

            // System Commands
            "command.sleep": "睡眠",
            "command.lock": "鎖定螢幕",
            "command.empty.trash": "清空垃圾桶",
            "command.restart": "重新啟動",
            "command.shutdown": "關機",
            "command.logout": "登出",
            "command.pressEnter": "按 Enter 執行%@",
        ]
    ]
}

// MARK: - Convenience Function

func L(_ key: String) -> String {
    return LocalizationManager.shared.localized(key)
}

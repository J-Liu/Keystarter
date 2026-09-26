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
            "settings.tab.monitor": "Monitor",
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
            "settings.monitor.modules": "Status Bar Modules",
            "settings.monitor.log.enable": "Enable Monitor Log",
            "settings.cpu.enabled": "CPU Usage",
            "settings.memory.enabled": "Memory Usage",
            "settings.contentIndex": "File Content Index:",
            "settings.contentIndex.checkbox": "Index file contents for search",
            "settings.log": "Log:",
            "settings.log.path": "Log Path:",
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
            "settings.clipboard.log.enable": "Enable Clipboard Log",
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
            // Launcher Log
            "settings.launcher.log.enable": "Enable Launcher Log",

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
            "alert.indexLimit.title": "Index File Limit Exceeded",
            "alert.indexLimit.message": "Found %d files, exceeding the limit of %d. Please narrow your scan scope.",
            "alert.ok": "OK",

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

            // Status Modules
            "status.cpu.displayName": "CPU Usage",
            "status.memory.displayName": "Memory Usage",
            "status.network.displayName": "Network",
            "status.disk.displayName": "Disk",
            "status.gpu.displayName": "GPU",
            "status.sensor.displayName": "Temperature",
            "status.gpu.note": "GPU info may vary by hardware",
            "status.sensor.note": "More sensors coming soon",
            "status.process.name": "Process",
            "status.process.cpu": "CPU",
            "status.process.memory": "Memory",

            // Stock Plugin
            "stock.enterNameOrCode": "Enter stock name or code",
            "stock.example": "Example: AAPL or TSLA",
            "stock.noMatch": "No matching stock found",
            "stock.checkInput": "Please check your input",
            "stock.queryFailed": "Query failed",
            "stock.invalidURL": "Invalid URL",
            "stock.noData": "No data available",
            "stock.parseFailed": "Failed to parse data",
            "stock.unknown": "Unknown",
            "stock.detail.code": "Code",
            "stock.detail.name": "Name",
            "stock.detail.initials": "Initials",
            "stock.detail.price": "Current Price",
            "stock.detail.open": "Open",
            "stock.detail.high": "High",
            "stock.detail.low": "Low",
            "stock.detail.volume": "Volume",
            "stock.detail.shares": " shares",
            "stock.detail.amount": "Amount",
            "stock.detail.turnover": "Turnover Rate",
            "stock.detail.marketCap": "Market Cap",
            "stock.detail.circCap": "Circulating Cap",
            "stock.detail.peRatio": "P/E Ratio",
            "stock.detail.industry": "Industry",
            "stock.unit.trillion": "T",
            "stock.unit.hundredMillion": "B",
            "stock.unit.tenThousand": "K",
        ],

        .simplifiedChinese: [
            // Settings Window
            "settings.title": "Keystarter 设置",
            "settings.tab.general": "通用",
            "settings.tab.monitor": "监控",
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
            "settings.monitor.modules": "状态栏模块",
            "settings.monitor.log.enable": "启用监控日志",
            "settings.cpu.enabled": "CPU 使用率",
            "settings.memory.enabled": "内存使用",
            "settings.contentIndex": "文件内容索引：",
            "settings.contentIndex.checkbox": "索引文件内容以便搜索",
            "settings.log": "日志：",
            "settings.log.path": "日志路径：",
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
            "settings.clipboard.log.enable": "启用剪贴板日志",
            "settings.clipboard.maxCount": "最大条数：",
            "settings.clipboard.maxCount.hint": "条 (分组: %@)",
            "settings.clipboard.maxDays": "保留天数：",
            "settings.clipboard.maxDays.hint": "天",
            "settings.clipboard.clear": "清空剪切板历史",

            // About Tab
            "settings.about.version": "版本 %@",
            "settings.about.copyright": "© 2026 Jia Liu. 保留所有权利。",

            // Launcher Log
            "settings.launcher.log.enable": "启用启动器日志",

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
            "alert.indexLimit.title": "索引文件数量超限",
            "alert.indexLimit.message": "发现 %d 个文件，超过上限 %d。请缩小扫描范围。",
            "alert.ok": "确定",

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

            // Status Modules
            "status.cpu.displayName": "CPU 使用率",
            "status.memory.displayName": "内存使用",
            "status.network.displayName": "网络",
            "status.disk.displayName": "硬盘",
            "status.gpu.displayName": "GPU",
            "status.sensor.displayName": "温度",
            "status.gpu.note": "GPU 信息因硬件而异",
            "status.sensor.note": "更多传感器即将推出",
            "status.process.name": "进程",
            "status.process.cpu": "CPU",
            "status.process.memory": "内存",

            // Stock Plugin
            "stock.enterNameOrCode": "请输入股票名称或代码",
            "stock.example": "例如：AAPL 或 TSLA",
            "stock.noMatch": "未找到匹配的股票",
            "stock.checkInput": "请检查输入是否正确",
            "stock.queryFailed": "查询失败",
            "stock.invalidURL": "无效的URL",
            "stock.noData": "无数据",
            "stock.parseFailed": "解析数据失败",
            "stock.unknown": "未知",
            "stock.detail.code": "股票代码",
            "stock.detail.name": "股票名称",
            "stock.detail.initials": "首字母",
            "stock.detail.price": "当前价格",
            "stock.detail.open": "今日开盘",
            "stock.detail.high": "今日最高",
            "stock.detail.low": "今日最低",
            "stock.detail.volume": "成交量",
            "stock.detail.shares": "股",
            "stock.detail.amount": "成交额",
            "stock.detail.turnover": "换手率",
            "stock.detail.marketCap": "总市值",
            "stock.detail.circCap": "流通市值",
            "stock.detail.peRatio": "市盈率",
            "stock.detail.industry": "所属行业",
            "stock.unit.trillion": "万亿",
            "stock.unit.hundredMillion": "亿",
            "stock.unit.tenThousand": "万",
        ],

        .traditionalChinese: [
            // Settings Window
            "settings.title": "Keystarter 設定",
            "settings.tab.general": "一般",
            "settings.tab.monitor": "監控",
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
            "settings.monitor.modules": "狀態列模組",
            "settings.monitor.log.enable": "啟用監控日誌",
            "settings.cpu.enabled": "CPU 使用率",
            "settings.memory.enabled": "記憶體使用",
            "settings.contentIndex": "檔案內容索引：",
            "settings.contentIndex.checkbox": "索引檔案內容以便搜尋",
            "settings.log": "日誌：",
            "settings.log.path": "日誌路徑：",
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
            "settings.clipboard.log.enable": "啟用剪貼簿日誌",
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

            // Launcher Log
            "settings.launcher.log.enable": "啟用啟動器日誌",

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
            "alert.indexLimit.title": "索引檔案數量超限",
            "alert.indexLimit.message": "發現 %d 個檔案，超過上限 %d。請縮小掃描範圍。",
            "alert.ok": "確定",

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

            // Status Modules
            "status.cpu.displayName": "CPU 使用率",
            "status.memory.displayName": "記憶體使用",
            "status.network.displayName": "網路",
            "status.disk.displayName": "硬碟",
            "status.gpu.displayName": "GPU",
            "status.sensor.displayName": "溫度",
            "status.gpu.note": "GPU 資訊因硬體而異",
            "status.sensor.note": "更多感應器即將推出",
            "status.process.name": "程序",
            "status.process.cpu": "CPU",
            "status.process.memory": "記憶體",

            // Stock Plugin
            "stock.enterNameOrCode": "請輸入股票名稱或代碼",
            "stock.example": "例如：AAPL 或 TSLA",
            "stock.noMatch": "未找到匹配的股票",
            "stock.checkInput": "請檢查輸入是否正確",
            "stock.queryFailed": "查詢失敗",
            "stock.invalidURL": "無效的URL",
            "stock.noData": "無數據",
            "stock.parseFailed": "解析數據失敗",
            "stock.unknown": "未知",
            "stock.detail.code": "股票代碼",
            "stock.detail.name": "股票名稱",
            "stock.detail.initials": "首字母",
            "stock.detail.price": "當前價格",
            "stock.detail.open": "今日開盤",
            "stock.detail.high": "今日最高",
            "stock.detail.low": "今日最低",
            "stock.detail.volume": "成交量",
            "stock.detail.shares": "股",
            "stock.detail.amount": "成交額",
            "stock.detail.turnover": "換手率",
            "stock.detail.marketCap": "總市值",
            "stock.detail.circCap": "流通市值",
            "stock.detail.peRatio": "市盈率",
            "stock.detail.industry": "所屬行業",
            "stock.unit.trillion": "萬億",
            "stock.unit.hundredMillion": "億",
            "stock.unit.tenThousand": "萬",
        ]
    ]
}

// MARK: - Convenience Function

func L(_ key: String) -> String {
    return LocalizationManager.shared.localized(key)
}

// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Foundation

/// 股票查询插件
/// 支持通过 "stock" 命令或直接输入股票名称/代码/首字母
final class StockPlugin: Plugin {
    let keyword = "stock"
    let pluginDescription = "查询股票信息"

    private var stockList: [StockInfo] = []
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval = 60 // 缓存1分钟

    struct StockInfo {
        let code: String
        let name: String
        let initials: String
        let price: Double
        let open: Double
        let high: Double
        let low: Double
        let volume: Double
        let amount: Double
        let turnoverRate: Double
        let marketCap: Double
        let circulatingCap: Double
        let peRatio: Double
        let industry: String
    }

    func matchesDirect(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

        // 只匹配6位数字股票代码
        if trimmed.count == 6 && trimmed.allSatisfy({ $0.isNumber }) {
            return true
        }

        // 不匹配其他输入，避免卡顿
        return false
    }

    func queryDirect(_ input: String) -> [PluginResult] {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            return [PluginResult(title: "请输入股票名称或代码", subtitle: "例如：宇树科技 或 YSKJ")]
        }

        // 同步获取股票数据
        let results = fetchStockDataSync(query: query)

        if results.isEmpty {
            return [PluginResult(title: "未找到匹配的股票", subtitle: "请检查输入是否正确")]
        }

        return results
    }

    func query(_ input: String) -> [PluginResult] {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            return [PluginResult(title: "请输入股票名称或代码", subtitle: "例如：宇树科技 或 YSKJ")]
        }

        // 同步获取股票数据
        let results = fetchStockDataSync(query: query)

        if results.isEmpty {
            return [PluginResult(title: "未找到匹配的股票", subtitle: "请检查输入是否正确")]
        }

        return results
    }

    private func fetchStockDataSync(query: String) -> [PluginResult] {
        // 检查缓存
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration,
           !stockList.isEmpty {
            return filterAndFormatStocks(query: query)
        }

        // 使用东方财富API获取A股数据
        let urlString = "https://push2.eastmoney.com/api/qt/clist/get?pn=1&pz=5000&po=1&np=1&fltt=2&invt=2&fields=f2,f3,f4,f5,f6,f7,f8,f9,f10,f12,f14,f15,f16,f17,f18,f20,f21,f23,f100&fs=m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23"

        guard let url = URL(string: urlString) else {
            return [PluginResult(title: "查询失败", subtitle: "无效的URL")]
        }

        var results: [PluginResult] = []
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            defer { semaphore.signal() }

            guard let self = self else { return }

            if let error = error {
                results = [PluginResult(title: "查询失败", subtitle: error.localizedDescription)]
                return
            }

            guard let data = data else {
                results = [PluginResult(title: "查询失败", subtitle: "无数据")]
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataObj = json["data"] as? [String: Any],
                   let diff = dataObj["diff"] as? [[String: Any]] {

                    var stocks: [StockInfo] = []

                    for item in diff {
                        guard let code = item["f12"] as? String,
                              let name = item["f14"] as? String else {
                            continue
                        }

                        let initials = self.getInitials(from: name)
                        let price = item["f2"] as? Double ?? 0
                        let open = item["f17"] as? Double ?? 0
                        let high = item["f15"] as? Double ?? 0
                        let low = item["f16"] as? Double ?? 0
                        let volume = item["f5"] as? Double ?? 0
                        let amount = item["f6"] as? Double ?? 0
                        let turnoverRate = item["f8"] as? Double ?? 0
                        let marketCap = item["f20"] as? Double ?? 0
                        let circulatingCap = item["f21"] as? Double ?? 0
                        let peRatio = item["f9"] as? Double ?? 0
                        let industry = item["f100"] as? String ?? "未知"

                        let stockInfo = StockInfo(
                            code: code,
                            name: name,
                            initials: initials,
                            price: price,
                            open: open,
                            high: high,
                            low: low,
                            volume: volume,
                            amount: amount,
                            turnoverRate: turnoverRate,
                            marketCap: marketCap,
                            circulatingCap: circulatingCap,
                            peRatio: peRatio,
                            industry: industry
                        )

                        stocks.append(stockInfo)
                    }

                    self.stockList = stocks
                    self.lastFetchTime = Date()

                    results = self.filterAndFormatStocks(query: query)
                } else {
                    results = [PluginResult(title: "查询失败", subtitle: "解析数据失败")]
                }
            } catch {
                results = [PluginResult(title: "查询失败", subtitle: error.localizedDescription)]
            }
        }.resume()

        semaphore.wait()
        return results
    }

    private func filterAndFormatStocks(query: String) -> [PluginResult] {
        let lowercasedQuery = query.lowercased()

        let matchedStocks = stockList.filter { stock in
            let matchesCode = stock.code.contains(query)
            let matchesName = stock.name.localizedCaseInsensitiveContains(query)
            let matchesInitials = stock.initials.lowercased().contains(lowercasedQuery)

            return matchesCode || matchesName || matchesInitials
        }

        // 只返回前10个结果
        let limitedStocks = Array(matchedStocks.prefix(10))

        return limitedStocks.map { formatStockResult($0) }
    }

    private func getInitials(from name: String) -> String {
        // 简化的拼音首字母映射表
        let pinyinMap: [String: String] = [
            "阿": "A", "啊": "A", "爱": "A", "安": "A", "暗": "A",
            "八": "B", "把": "B", "百": "B", "办": "B", "半": "B", "报": "B", "北": "B", "本": "B", "比": "B", "必": "B", "边": "B", "变": "B", "标": "B", "表": "B", "别": "B", "兵": "B", "病": "B", "并": "B", "不": "B", "部": "B",
            "才": "C", "菜": "C", "参": "C", "草": "C", "层": "C", "查": "C", "产": "C", "常": "C", "场": "C", "车": "C", "成": "C", "城": "C", "程": "C", "吃": "C", "持": "C", "出": "C", "初": "C", "处": "C", "传": "C", "创": "C", "春": "C", "此": "C", "从": "C", "村": "C", "存": "C", "寸": "C", "错": "C",
            "大": "D", "打": "D", "代": "D", "带": "D", "单": "D", "但": "D", "当": "D", "到": "D", "道": "D", "的": "D", "得": "D", "等": "D", "低": "D", "地": "D", "第": "D", "点": "D", "电": "D", "店": "D", "东": "D", "动": "D", "都": "D", "读": "D", "度": "D", "段": "D", "对": "D", "多": "D",
            "而": "E", "儿": "E", "耳": "E", "二": "E",
            "发": "F", "法": "F", "反": "F", "饭": "F", "方": "F", "房": "F", "放": "F", "飞": "F", "非": "F", "分": "F", "风": "F", "服": "F", "福": "F", "父": "F", "复": "F", "副": "F", "富": "F",
            "该": "G", "改": "G", "盖": "G", "干": "G", "感": "G", "刚": "G", "高": "G", "个": "G", "各": "G", "给": "G", "工": "G", "公": "G", "功": "G", "共": "G", "关": "G", "观": "G", "管": "G", "光": "G", "广": "G", "规": "G", "国": "G", "果": "G", "过": "G",
            "还": "H", "海": "H", "好": "H", "号": "H", "合": "H", "和": "H", "河": "H", "很": "H", "红": "H", "后": "H", "候": "H", "花": "H", "华": "H", "化": "H", "话": "H", "欢": "H", "换": "H", "黄": "H", "回": "H", "会": "H", "活": "H", "火": "H", "或": "H",
            "机": "J", "几": "J", "己": "J", "记": "J", "计": "J", "技": "J", "际": "J", "季": "J", "家": "J", "加": "J", "价": "J", "间": "J", "建": "J", "将": "J", "江": "J", "教": "J", "接": "J", "街": "J", "节": "J", "结": "J", "解": "J", "金": "J", "今": "J", "进": "J", "近": "J", "京": "J", "经": "J", "精": "J", "景": "J", "九": "J", "久": "J", "就": "J", "军": "J",
            "开": "K", "看": "K", "科": "K", "可": "K", "克": "K", "客": "K", "空": "K", "口": "K", "快": "K", "块": "K",
            "来": "L", "老": "L", "了": "L", "乐": "L", "离": "L", "里": "L", "力": "L", "利": "L", "立": "L", "连": "L", "联": "L", "脸": "L", "练": "L", "良": "L", "两": "L", "亮": "L", "量": "L", "料": "L", "林": "L", "领": "L", "另": "L", "六": "L", "路": "L", "陆": "L", "绿": "L", "论": "L", "罗": "L", "落": "L",
            "妈": "M", "马": "M", "买": "M", "卖": "M", "满": "M", "慢": "M", "忙": "M", "毛": "M", "没": "M", "美": "M", "门": "M", "们": "M", "米": "M", "面": "M", "民": "M", "名": "M", "明": "M", "命": "M", "母": "M", "木": "M", "目": "M", "牧": "M",
            "那": "N", "哪": "N", "南": "N", "男": "N", "难": "N", "内": "N", "能": "N", "你": "N", "年": "N", "念": "N", "农": "N", "女": "N",
            "哦": "O", "欧": "O",
            "怕": "P", "排": "P", "跑": "P", "片": "P", "票": "P", "平": "P", "破": "P", "普": "P",
            "七": "Q", "期": "Q", "其": "Q", "奇": "Q", "起": "Q", "气": "Q", "汽": "Q", "千": "Q", "前": "Q", "钱": "Q", "强": "Q", "墙": "Q", "亲": "Q", "青": "Q", "清": "Q", "情": "Q", "请": "Q", "庆": "Q", "秋": "Q", "求": "Q", "球": "Q", "区": "Q", "曲": "Q", "取": "Q", "去": "Q", "全": "Q", "权": "Q", "却": "Q", "确": "Q",
            "然": "R", "让": "R", "热": "R", "人": "R", "认": "R", "任": "R", "日": "R", "容": "R", "如": "R", "入": "R",
            "三": "S", "色": "S", "山": "S", "上": "S", "少": "S", "社": "S", "身": "S", "深": "S", "什": "S", "神": "S", "生": "S", "声": "S", "省": "S", "胜": "S", "师": "S", "十": "S", "时": "S", "实": "S", "食": "S", "使": "S", "世": "S", "市": "S", "事": "S", "是": "S", "室": "S", "收": "S", "手": "S", "首": "S", "受": "S", "书": "S", "树": "S", "数": "S", "术": "S", "双": "S", "水": "S", "说": "S", "思": "S", "四": "S", "送": "S", "速": "S", "算": "S", "虽": "S", "岁": "S", "随": "S", "孙": "S", "所": "S", "索": "S",
            "他": "T", "她": "T", "它": "T", "台": "T", "太": "T", "态": "T", "谈": "T", "特": "T", "提": "T", "体": "T", "天": "T", "条": "T", "听": "T", "通": "T", "同": "T", "头": "T", "图": "T", "土": "T", "团": "T", "推": "T",
            "外": "W", "完": "W", "万": "W", "王": "W", "往": "W", "望": "W", "为": "W", "位": "W", "未": "W", "文": "W", "问": "W", "我": "W", "五": "W", "午": "W", "物": "W", "务": "W",
            "西": "X", "希": "X", "息": "X", "习": "X", "系": "X", "细": "X", "下": "X", "先": "X", "现": "X", "线": "X", "相": "X", "想": "X", "向": "X", "象": "X", "像": "X", "小": "X", "校": "X", "笑": "X", "效": "X", "些": "X", "写": "X", "谢": "X", "新": "X", "信": "X", "星": "X", "形": "X", "性": "X", "姓": "X", "兄": "X", "休": "X", "修": "X", "需": "X", "许": "X", "选": "X", "学": "X", "雪": "X",
            "压": "Y", "呀": "Y", "牙": "Y", "言": "Y", "研": "Y", "眼": "Y", "演": "Y", "样": "Y", "要": "Y", "也": "Y", "业": "Y", "叶": "Y", "夜": "Y", "一": "Y", "医": "Y", "已": "Y", "以": "Y", "义": "Y", "意": "Y", "因": "Y", "音": "Y", "银": "Y", "应": "Y", "英": "Y", "影": "Y", "用": "Y", "由": "Y", "有": "Y", "又": "Y", "于": "Y", "与": "Y", "语": "Y", "元": "Y", "园": "Y", "原": "Y", "源": "Y", "远": "Y", "院": "Y", "愿": "Y", "月": "Y", "越": "Y", "云": "Y", "运": "Y",
            "在": "Z", "再": "Z", "早": "Z", "造": "Z", "则": "Z", "怎": "Z", "增": "Z", "展": "Z", "站": "Z", "张": "Z", "章": "Z", "找": "Z", "者": "Z", "这": "Z", "着": "Z", "真": "Z", "正": "Z", "整": "Z", "知": "Z", "之": "Z", "支": "Z", "只": "Z", "纸": "Z", "指": "Z", "至": "Z", "制": "Z", "治": "Z", "中": "Z", "重": "Z", "种": "Z", "众": "Z", "主": "Z", "住": "Z", "注": "Z", "专": "Z", "转": "Z", "装": "Z", "状": "Z", "追": "Z", "准": "Z", "资": "Z", "子": "Z", "自": "Z", "字": "Z", "总": "Z", "走": "Z", "最": "Z", "昨": "Z", "作": "Z", "做": "Z", "座": "Z"
        ]

        var initials = ""
        for char in name {
            if char.isASCII {
                initials.append(char)
            } else if let initial = pinyinMap[String(char)] {
                initials.append(initial)
            }
        }
        return initials
    }

    private func formatStockResult(_ stock: StockInfo) -> PluginResult {
        let priceStr = String(format: "%.2f", stock.price)
        let openStr = String(format: "%.2f", stock.open)
        let highStr = String(format: "%.2f", stock.high)
        let lowStr = String(format: "%.2f", stock.low)

        let volumeStr = formatLargeNumber(stock.volume * 100) // 手转股
        let amountStr = formatLargeNumber(stock.amount)
        let turnoverStr = String(format: "%.2f%%", stock.turnoverRate)
        let marketCapStr = formatLargeNumber(stock.marketCap)
        let circCapStr = formatLargeNumber(stock.circulatingCap)
        let peStr = String(format: "%.2f", stock.peRatio)

        let detail = """
        股票代码：\(stock.code)
        股票名称：\(stock.name)
        首字母：\(stock.initials)

        当前价格：¥\(priceStr)
        今日开盘：¥\(openStr)
        今日最高：¥\(highStr)
        今日最低：¥\(lowStr)

        成交量：\(volumeStr)股
        成交额：¥\(amountStr)
        换手率：\(turnoverStr)

        总市值：¥\(marketCapStr)
        流通市值：¥\(circCapStr)
        市盈率：\(peStr)

        所属行业：\(stock.industry)
        """

        return PluginResult(
            title: "\(stock.name) (\(stock.code))",
            subtitle: "¥\(priceStr) | \(stock.industry)",
            icon: NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: nil),
            detailText: detail,
            action: {
                if let url = URL(string: "https://quote.eastmoney.com/\(stock.code).html") {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }

    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 100_000_000_000 {
            return String(format: "%.2f万亿", value / 100_000_000_000)
        } else if value >= 100_000_000 {
            return String(format: "%.2f亿", value / 100_000_000)
        } else if value >= 10000 {
            return String(format: "%.2f万", value / 10000)
        } else {
            return String(format: "%.0f", value)
        }
    }
}

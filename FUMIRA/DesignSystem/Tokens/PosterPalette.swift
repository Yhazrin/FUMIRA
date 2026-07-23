import SwiftUI

/// Direction H — 公园时间海报版
///
/// 米白纸张 · 青蓝天空 · 草地分层 · 深松绿 · 手写墨色 · 克制苔黄点睛。
/// 原色值只允许出现在本文件；Feature / Component 必须通过语义 token 取色。
enum PosterPalette {

    // MARK: - Core semantic

    /// 米白纸张底色 — 主画布
    static let paper = Color(red: 246 / 255, green: 243 / 255, blue: 232 / 255) // #F6F3E8

    /// 更亮纸面 — 卡片与浅色控件填充
    static let paperWhite = Color(red: 255 / 255, green: 253 / 255, blue: 247 / 255) // #FFFDF7

    /// 天空青蓝 — 大面积背景、相机叠层、时间强调
    static let sky = Color(red: 123 / 255, green: 200 / 255, blue: 235 / 255) // #7BC8EB

    /// 天空近地 / 底部渐变
    static let skySoft = Color(red: 184 / 255, green: 224 / 255, blue: 245 / 255) // #B8E0F5

    /// 深青蓝 — 叠层、生成标题、深色天空面
    static let skyDeep = Color(red: 61 / 255, green: 139 / 255, blue: 181 / 255) // #3D8BB5

    /// 草地浅绿 — 分层地形近层、浅色自然面
    static let grassLight = Color(red: 143 / 255, green: 203 / 255, blue: 126 / 255) // #8FCB7E

    /// 深松绿 — 地形深部、进度、主按钮与生成页大色块
    static let pine = Color(red: 42 / 255, green: 90 / 255, blue: 60 / 255) // #2A5A3C

    /// 苔黄 / 暖黄 — 仅选中态、关键字下划线、时间游标等 ≤5% 强调
    static let moss = Color(red: 201 / 255, green: 179 / 255, blue: 90 / 255) // #C9B35A

    /// 深墨黑 — 标题与重要操作
    static let ink = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255) // #111111

    /// 次要墨色 — 辅助标签
    static let mutedInk = Color(red: 165 / 255, green: 163 / 255, blue: 155 / 255) // #A5A39B

    /// 波形时间轴非选中竖条 — 低对比，可叠在纸面或软渐层上
    static let waveIdle = ink.opacity(0.22)

    /// 可恢复错误
    static let errorCoral = Color(red: 233 / 255, green: 94 / 255, blue: 82 / 255) // #E95E52

    /// 分割线 / 细描边
    static let line = Color(red: 201 / 255, green: 198 / 255, blue: 188 / 255) // #C9C6BC

    // MARK: - Scene temporal variants (park interpolation)

    /// 过去天空顶 — 暖纸感
    static let skyPastTop = Color(red: 209 / 255, green: 184 / 255, blue: 148 / 255) // #D1B894

    /// 过去天空底
    static let skyPastBottom = Color(red: 230 / 255, green: 209 / 255, blue: 179 / 255) // #E6D1B3

    /// 未来天空顶 — 更冷的青蓝
    static let skyFutureTop = Color(red: 107 / 255, green: 140 / 255, blue: 209 / 255) // #6B8CD1

    /// 未来天空底
    static let skyFutureBottom = Color(red: 148 / 255, green: 179 / 255, blue: 230 / 255) // #94B3E6

    // MARK: - Compatibility aliases (legacy names → Direction H)

    /// - Important: Prefer ``sky``. Kept so existing call sites compile.
    static let timeBlue = sky

    /// - Important: Prefer ``skyDeep``.
    static let deepTimeBlue = skyDeep

    /// - Important: Prefer ``pine``.
    static let parkGreen = pine

    /// - Important: Prefer ``pine`` for generation surfaces / large park blocks.
    static let growthGreen = pine

    /// Fluorescent accent from the prior palette.
    ///
    /// - Warning: **Deprecated / accent-only.** Use ``moss`` for new code.
    ///   Never use as a page background or full primary button fill.
    ///   Maps to ``moss`` so large fluorescent lime surfaces disappear.
    @available(*, deprecated, renamed: "moss", message: "Energy Lime is accent-only; use moss (苔黄) for ≤5% emphasis.")
    static let energyLime = moss
}

import SwiftUI

/// Direction H — 公园时间海报版
///
/// 纯白画布 · 青蓝天空 · 草地分层 · 深松绿 · 手写墨色 · 清新叶绿点睛。
/// 米色 `paper` 仅保留给海报合成 / 公园装饰形的局部纸感，不再作 App 主背景。
/// 原色值只允许出现在本文件；Feature / Component 必须通过语义 token 取色。
enum PosterPalette {

    // MARK: - Core semantic

    /// 纯白画布 — App chrome、设置、结果留白、默认页背景
    static let canvas = Color(red: 1, green: 1, blue: 1) // #FFFFFF

    /// 页面背景别名 — 与 ``canvas`` 同值，便于语义阅读
    static let pageBackground = canvas

    /// 米白纸张 — **仅**海报合成区、公园装饰形、场景叠色的局部纸感
    static let paper = Color(red: 246 / 255, green: 243 / 255, blue: 232 / 255) // #F6F3E8

    /// 浅色控件 / 卡片填充 — 纯白；白底上靠描边或阴影建立层级
    static let paperWhite = canvas

    /// 浅色信息卡 — 必须保持完全不透明，避免照片透过卡片干扰阅读
    static let cardLight = canvas

    /// 深色信息卡 — 必须保持完全不透明；空间透明度只留给画面遮罩
    static let cardDark = ink

    /// 天空青蓝 — Connection 气质基准：大面积天空、相机叠层、时间强调
    static let sky = Color(red: 123 / 255, green: 200 / 255, blue: 235 / 255) // #7BC8EB

    /// 天空近地 / 底部渐变
    static let skySoft = Color(red: 184 / 255, green: 224 / 255, blue: 245 / 255) // #B8E0F5

    /// 选中态信息卡 — 纯色浅蓝，不使用半透明蓝叠在页面上
    static let cardActive = skySoft

    /// 深青蓝 — 叠层、生成标题、深色天空面
    static let skyDeep = Color(red: 61 / 255, green: 139 / 255, blue: 181 / 255) // #3D8BB5

    /// 相机快门蓝 — 蓝白轻拟物快门外壳；仅用于拍摄主按钮
    static let cameraShutterBlue = Color(red: 0 / 255, green: 153 / 255, blue: 255 / 255) // #0099FF

    /// 相机快门蓝暗面 — 快门底座与极短投影
    static let cameraShutterBlueDeep = Color(red: 0 / 255, green: 116 / 255, blue: 194 / 255) // #0074C2

    /// 取景器实体圆钮蓝 — 轻微深于快门面，保证白色 SF Symbol 超过 3:1
    static let cameraChromeBlue = Color(red: 0 / 255, green: 150 / 255, blue: 250 / 255) // #0096FA

    /// 主题蓝 — 所有可操作主按钮、进度与时间选中态
    static let actionBlue = cameraShutterBlue

    /// 主题蓝暗面 — 按压、描边与高对比文字
    static let actionBlueDeep = cameraShutterBlueDeep

    /// 相机机身蓝 — 取景卡后方的实体底层与控制甲板。
    /// 与首屏液体扩散终点统一为 ``actionBlue``，避免阶段切换色差。
    static let cameraBody = actionBlue

    /// 相机机身亮面 — 快门、选中态与短促反馈
    static let cameraBodyAccent = actionBlue

    /// 玩具红 — 首屏镜头口袋 / 快门点睛，不用于错误状态
    static let toyRed = Color(red: 232 / 255, green: 42 / 255, blue: 52 / 255)

    /// 铃铛黄 — 首屏启动镜头的温暖点睛色
    static let bellYellow = Color(red: 255 / 255, green: 211 / 255, blue: 58 / 255)

    /// 主题蓝暗线 — 首屏圆形镜头的阴影与外描边
    static let actionBlueShadow = Color(red: 0 / 255, green: 92 / 255, blue: 153 / 255) // #005C99

    /// 草地浅绿 — 分层地形近层、浅色自然面
    static let grassLight = Color(red: 143 / 255, green: 203 / 255, blue: 126 / 255) // #8FCB7E

    /// 深松绿 — 仅用于自然场景的地形深部与插画结构
    static let pine = Color(red: 42 / 255, green: 90 / 255, blue: 60 / 255) // #2A5A3C

    /// 清新叶绿 — 仅用于自然场景与品牌下划线，不用于交互状态
    static let leafGreen = Color(red: 95 / 255, green: 168 / 255, blue: 104 / 255) // #5FA868

    /// 深墨黑 — 标题与重要操作
    static let ink = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255) // #111111

    /// 次要墨色 — 白底辅助标签（约 4.6:1，满足 WCAG AA）
    static let mutedInk = Color(red: 110 / 255, green: 108 / 255, blue: 100 / 255) // #6E6C64

    /// 波形时间轴非选中竖条 — 低对比，可叠在白底或软渐层上
    static let waveIdle = ink.opacity(0.18)

    /// 可恢复错误
    static let errorCoral = Color(red: 233 / 255, green: 94 / 255, blue: 82 / 255) // #E95E52

    /// 分割线 / 细描边 — 白底卡片边缘
    static let line = Color(red: 210 / 255, green: 208 / 255, blue: 200 / 255) // #D2D0C8

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

    /// - Important: Prefer ``pine`` for natural scene surfaces.
    static let growthGreen = pine

}

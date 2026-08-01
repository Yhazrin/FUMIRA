import SwiftUI

/// Clay OS — 全局色板桥接。
/// 所有原色值只允许出现在本文件和 Clay/Foundation/ClayPalette.swift；
/// Feature / Component 通过语义 token 取色。
///
/// 本文件将旧 Direction H 名称映射到 Clay 色系，
/// 使现有调用点无需逐一修改即可获得新配色。
enum PosterPalette {

    // MARK: - Core semantic

    /// 主背景 — Clay 深炭
    static let canvas = ClayPalette.charcoal

    /// 页面背景别名
    static let pageBackground = canvas

    /// 米白纸张 — Clay 暖白
    static let paper = ClayPalette.warmWhite

    /// 浅色控件 / 卡片填充
    static let paperWhite = ClayPalette.warmWhite

    /// 浅色信息卡
    static let cardLight = ClayPalette.warmWhite

    /// 深色信息卡
    static let cardDark = ClayPalette.charcoal

    // MARK: - Blue → Time Blue

    /// 天空青蓝 → Time Blue
    static let sky = ClayPalette.timeBlue

    /// 天空近地 → Time Blue 暗面
    static let skySoft = ClayPalette.timeBlueRim

    /// 选中态信息卡
    static let cardActive = ClayPalette.timeBlue

    /// 深青蓝 → Time Blue 暗面
    static let skyDeep = ClayPalette.timeBlueRim

    /// 相机快门蓝 → Time Blue
    static let cameraShutterBlue = ClayPalette.timeBlue

    /// 相机快门蓝暗面
    static let cameraShutterBlueDeep = ClayPalette.timeBlueRim

    /// 取景器圆钮蓝
    static let cameraChromeBlue = ClayPalette.timeBlue

    /// 主题蓝 → Time Blue
    static let actionBlue = ClayPalette.timeBlue

    /// 主题蓝暗面
    static let actionBlueDeep = ClayPalette.timeBlueRim

    /// 相机机身蓝
    static let cameraBody = ClayPalette.timeBlue

    /// 相机机身亮面
    static let cameraBodyAccent = ClayPalette.timeBlue

    /// 主题蓝暗线
    static let actionBlueShadow = ClayPalette.timeBlueRim

    // MARK: - Warm accents

    /// 玩具红 → Clay 橙（保持活力）
    static let toyRed = ClayPalette.orange

    /// 铃铛黄 → Clay 黄
    static let bellYellow = ClayPalette.yellow

    // MARK: - Green tones

    /// 草地浅绿 → Park Green
    static let grassLight = ClayPalette.parkGreen

    /// 深松绿 → Park Green 暗面
    static let pine = ClayPalette.parkGreenRim

    /// 清新叶绿 → Park Green
    static let leafGreen = ClayPalette.parkGreen

    // MARK: - Neutral

    /// 深墨黑 → Clay charcoal
    static let ink = ClayPalette.charcoal

    /// 次要墨色
    static let mutedInk = ClayPalette.textMuted

    /// 波形时间轴非选中竖条
    static let waveIdle = ClayPalette.charcoal.opacity(0.18)

    /// 可恢复错误
    static let errorCoral = ClayPalette.error

    /// 分割线 / 细描边
    static let line = ClayPalette.warmWhiteRim

    // MARK: - Scene temporal variants

    /// 过去天空顶 — 暖纸感
    static let skyPastTop = ClayPalette.warmWhite

    /// 过去天空底
    static let skyPastBottom = ClayPalette.warmWhiteRim

    /// 未来天空顶 — Time Blue 色调
    static let skyFutureTop = ClayPalette.timeBlue

    /// 未来天空底
    static let skyFutureBottom = ClayPalette.timeBlueRim

    // MARK: - Compatibility aliases

    static let timeBlue = sky
    static let deepTimeBlue = skyDeep
    static let parkGreen = pine
    static let growthGreen = pine

    // MARK: - New Clay tokens (for gradual migration)

    /// Clay lime — 成功 / 激活
    static let lime = ClayPalette.lime

    /// Clay yellow — 进度 / 警告
    static let yellow = ClayPalette.yellow

    /// Clay orange — 强调色 / 玩具红系
    static let orange = ClayPalette.orange

    /// Clay warmWhite — 文字在深色上
    static let warmWhite = ClayPalette.warmWhite

    /// Clay charcoal — 文字在浅色上
    static let charcoal = ClayPalette.charcoal
}

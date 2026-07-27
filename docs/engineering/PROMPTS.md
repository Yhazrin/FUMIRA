# FUMIRA — 提示词（Prompt）整理

> **权威源在 server。** iOS App 不再拼装主出图 / VLM / 故事业务 Prompt（仅保留短 mock fallback 与离线兜底故事）。
>
> 本文档汇总真正落到 AI 模型的提示词所在位置与调用链。
>
> 原则：
> - 出图 / 理解 / 故事 Prompt 均由 `server/` 生成；App 只传结构化参数（timePosition、Scene Bible、beat 等）。
> - 应用内没有任何自由文本 prompt 输入框。
> - 三类模型调用：① 出图（I2I） ② 图像理解（VLM / Scene Bible） ③ 7 拍故事（M3 Chat）。

---

## 1. 总览：AI 调用链路（故事驱动）

```
┌──────────────┐
│ 用户选时间点 │
└──────┬───────┘
       │ TimePosition + 源照片
       ▼
┌──────────────────────────────────────────────────┐
│ ① VLM 理解源照片 → Scene Bible（server）           │
│   liveIntelligenceAdapter.analyzeImage             │
└──────┬───────────────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────┐
│ ② 7 拍连续时间故事（server）                        │
│   liveIntelligenceAdapter.writeStory               │
└──────┬───────────────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────┐
│ ③ 出图 Prompt（server 权威）                       │
│   temporalImagePrompt.make / compileStoryDriven    │
│   + continuityFooter；整体 ≤ promptMaxChars(2400)  │
│   App 客户端 prompt 字符串会被忽略（__FORCE_*__ 除外）│
└──────┬───────────────────────────────────────────┘
       ▼
┌──────────────────────┐
│ 目标时间照片（生成） │
└──────────────────────┘

可选骨架：validation.ts（源图↔结果校验 + 低分重绘 TODO）
```

多时间点原则：每个时间点都从**同一源图 + 共享 Scene Bible + 不同目标 beat** 生成，禁止链式漂移。

---

## 2. 提示词清单

| # | 角色 | 语言 | 状态 | 文件 |
|---|---|---|---|---|
| 1 | 主出图 Prompt V2 | 中 | ✅ 权威 | `server/src/temporalImagePrompt.ts` |
| 2 | 故事驱动出图编译 | 中 | ✅ 权威 | `compileStoryDrivenPrompt` 同文件 |
| 3 | continuityFooter | 英 | ✅ 必拼 | `server/src/prompt.ts` |
| 4 | VLM Scene Bible | 英 | ✅ | `server/src/minimax/liveIntelligenceAdapter.ts` |
| 5 | 故事 system / user | 英 | ✅ | 同上 |
| 6 | 校验 Prompt 骨架 | 英 | 骨架 | `server/src/validation.ts` |
| 7 | App mock fallback | 中 | 仅 mock | `FUMIRA/Domain/AIPipeline.swift` `TemporalImagePrompt` |
| 8 | 离线兜底 7 拍 | 中 | 离线 | `TemporalStory.fallback` |
| 9 | Mock `__FORCE_*__` | – | 测试 | `server/src/minimax/mockAdapter.ts` |
| 10 | Admin `PROMPT_TEMPLATE` | 中性 | 外壳 | `server/src/config.ts` |

---

## 3. 主出图 Prompt V2（server）

- **入口：** `createGenerationJob` → `compileStoryDrivenPrompt` / `makeTemporalImagePrompt` → `buildPrompt`
- **核心逻辑：** 空间锚点锁定 → 全景分层 → 时间因果推演 → 年代一致性检查
- **跨度分级：** &lt;1天 / &lt;1年 / 1–10 / 10–50 / 50+
- **禁止项：** 不添加无关、抢镜或缺乏时间因果依据的人物/车辆/建筑/设施（非冻结世界）
- **字符上限：** `config.promptMaxChars = 2400`

---

## 4. continuityFooter（升级）

保留相机/构图/空间锚点；要求前中后景与六类环境系统检查；禁止单人/单物作为中长跨度唯一时间证据；年代一致；禁止无关主体与科幻。

---

## 5. Scene Bible / StoryBeat 扩展

`SceneUnderstanding` 可选字段：`cameraLock`、`spatialAnchors`、`temporalLayers`、`storySeeds`、`hardConstraints`（旧字段兼容）。

`StoryBeat` 可选字段：`transitionCause`、`unchangedAnchors`、`foregroundDelta` / `midgroundDelta` / `backgroundDelta` / `subjectDelta` / `environmentDelta`。

App DTO 与 server normalize 均向后兼容解析。

---

## 6. API 兼容说明

`POST /v1/generations`：

- `timePosition` **必需**（server 据此生成 Prompt）
- `prompt` / `story`：**可省略**；若传入普通字符串则**忽略**；仅 `__FORCE_*__` 测试标记透传
- 新增可选：`understanding`、`temporalStory`、`storyBeat`（故事驱动编译）

`POST /v1/understand`：仍分析上传资源；语义改为**源照片 Scene Bible**（非目标结果图）。

---

## 7. App 残留

| 残留 | 用途 |
|---|---|
| `TemporalImagePrompt.make` | 短 mock fallback，标注权威在 server |
| `TemporalStory.fallback` | 离线/预览 7 拍 |
| `GeneratedFrame.prompt` | 记录 mock 字符串或远端回显；live 路径不依赖客户端拼装 |

已删除：`TemporalStory.generationPrompt` 死代码。

---

## 8. 修改 Prompt 检查清单

- [ ] 改出图 Prompt → 只改 `server/src/temporalImagePrompt.ts`，跑 `server/test/temporal-prompt.test.ts`
- [ ] 改 Footer / 上限 → `prompt.ts` + `config.promptMaxChars`
- [ ] 改 VLM / 故事 → `liveIntelligenceAdapter.ts` + parser 测试
- [ ] 改 copyConstraints → 同步 App `*CopyPolicy` 与 server bounds
- [ ] **不要**在 App Feature / View 层新增长业务 Prompt 字符串

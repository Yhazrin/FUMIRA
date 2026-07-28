# FUMIRA — 提示词（Prompt）整理

> **权威源在 server。** iOS App 不再拼装主出图 / VLM / 故事业务 Prompt（仅保留短 mock fallback 与离线兜底故事）。
>
> 本文档汇总真正落到 AI 模型的提示词所在位置与调用链。
>
> 原则：
> - 出图 / 理解 / 故事 Prompt 均由 `server/` 生成；App 只传结构化参数（timePosition、Scene Bible、beat 等）。
> - 应用内没有任何自由文本 prompt 输入框。
> - 四类模型调用：① 图像理解（SceneGraph）② 7 拍故事 ③ 精确目标规划 ④ 出图（I2I）。

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
│ ③ 精确目标世界规划（server）                         │
│   writeExactTargetPlan → TemporalRenderPlan         │
└──────┬───────────────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────┐
│ ④ PromptCompiler V3（server 权威）                  │
│   必需段落先压缩保留，整体 ≤ promptMaxChars(1500)    │
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
| 1 | 主出图 Prompt V3 | 英 | ✅ 权威 | `server/src/promptCompiler.ts` |
| 2 | Legacy 故事驱动编译 | 中 | 兼容 | `server/src/temporalImagePrompt.ts` |
| 3 | continuityFooter | 英 | ✅ 必拼 | `server/src/prompt.ts` |
| 4 | VLM Scene Bible | 英 | ✅ | `server/src/minimax/liveIntelligenceAdapter.ts` |
| 5 | 故事 system / user | 英 | ✅ | 同上 |
| 6 | 校验 Prompt 骨架 | 英 | 骨架 | `server/src/validation.ts` |
| 7 | App mock fallback | 中 | 仅 mock | `FUMIRA/Domain/AIPipeline.swift` `TemporalImagePrompt` |
| 8 | 离线兜底 7 拍 | 中 | 离线 | `TemporalStory.fallback` |
| 9 | Mock `__FORCE_*__` | – | 测试 | `server/src/minimax/mockAdapter.ts` |
| 10 | Admin `PROMPT_TEMPLATE` | 中性 | 外壳 | `server/src/config.ts` |

---

## 3. 主出图 Prompt V3（server）

- **入口：** `createGenerationJob` → `compilePrompt`
- **核心逻辑：** SceneGraph → TemporalRenderPlan → 相机锁定 / 锚点策略 /
  全场景变化 / 跨层一致性 / 禁止漂移
- **跨度分级：** &lt;1天 / &lt;1年 / 1–10 / 10–50 / 50+
- **禁止项：** 不添加无关、抢镜或缺乏时间因果依据的人物/车辆/建筑/设施（非冻结世界）
- **字符上限：** `config.promptMaxChars = 1500`
- **预算：** 必需段落先放紧凑版，再按优先级扩展；精确时间变化永不整段删除

---

## 4. continuityFooter（升级）

保留相机/构图/空间锚点；要求前中后景与六类环境系统检查；禁止单人/单物作为中长跨度唯一时间证据；年代一致；禁止无关主体与科幻。

---

## 5. Scene Bible / StoryBeat 扩展

`SceneUnderstanding` 新增机器层 `sceneGraph`：分景深区域、材质、状态、
时间策略、相机锁和不确定项；旧 Scene Bible 字段继续兼容。

`StoryBeat` 保留短 UI 文案，并为精确 `targetBeat` 增加
`renderPlan`。RenderPlan 不套用 UI 字符预算。

App DTO 与 server normalize 均向后兼容解析。

---

## 6. API 兼容说明

`POST /v1/generations`：

- `timePosition` **必需**（server 据此生成 Prompt）
- `prompt` / `story`：**可省略**；若传入普通字符串则**忽略**；仅 `__FORCE_*__` 测试标记透传
- 当前客户端发送 `generation.v3` + `generation-context.v3`
- Legacy 可选：`understanding`、`temporalStory`、`storyBeat`

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

- [ ] 改主出图 Prompt → `server/src/promptCompiler.ts` + `promptCompiler.test.ts`
- [ ] 改 Legacy / 上限 → `temporalImagePrompt.ts` / `config.promptMaxChars`
- [ ] 改 VLM / 故事 → `liveIntelligenceAdapter.ts` + parser 测试
- [ ] 改 copyConstraints → 同步 App `*CopyPolicy` 与 server bounds
- [ ] **不要**在 App Feature / View 层新增长业务 Prompt 字符串

import { createHash } from "node:crypto";
import { config } from "./config.js";
import type {
  ExactTarget,
  GenerationContext,
  GenerationContextV3,
  QualityPolicy,
  RegionTemporalAction,
  RegionTemporalChange,
  SceneCategory,
  SceneDepth,
  SceneGraph,
  SceneRegion,
  ScreenZone,
  SubjectContinuityMode,
  TemporalPolicy,
  TemporalRenderPlan,
  TimeHorizonBand,
  TimePositionPayload,
  VisualCriticResult,
} from "./types.js";

const BUILT = new Set<SceneCategory>([
  "architecture", "infrastructure", "surface", "signage", "furniture",
]);
const NATURAL = new Set<SceneCategory>([
  "vegetation", "landscape", "animal", "atmosphere",
]);
const TECHNOLOGY = new Set<SceneCategory>([
  "vehicle", "infrastructure", "signage",
]);

export function defaultQualityPolicy(
  override?: GenerationContextV3["qualityPolicy"]
): QualityPolicy {
  const thresholds = override?.thresholds;
  return {
    visualCriticEnabled: override?.visualCriticEnabled ?? config.visualCriticEnabled,
    maxRegenerations: override?.maxRegenerations === 0
      ? 0
      : config.visualCriticMaxRegenerations,
    thresholds: {
      cameraConsistency: threshold(
        thresholds?.cameraConsistency,
        config.visualCriticThresholds.cameraConsistency
      ),
      requiredChangeCompletion: threshold(
        thresholds?.requiredChangeCompletion,
        config.visualCriticThresholds.requiredChangeCompletion
      ),
      environmentEvolution: threshold(
        thresholds?.environmentEvolution,
        config.visualCriticThresholds.environmentEvolution
      ),
      eraCoherence: threshold(
        thresholds?.eraCoherence,
        config.visualCriticThresholds.eraCoherence
      ),
    },
  };
}

export function horizonBandFromOffsetDays(offsetDays: number): TimeHorizonBand {
  const years = Math.abs(offsetDays) / 365.25;
  if (years < 0.08) return "hours_days";
  if (years < 1) return "months";
  if (years < 8) return "years";
  if (years < 100) return "decades";
  if (years < 1_000) return "centuries";
  if (years < 100_000) return "millennia";
  return "deep_time";
}

export function deriveSceneGraphFromV2(
  understanding: GenerationContext["understanding"]
): SceneGraph {
  const regions: SceneRegion[] = understanding.subjects.slice(0, 16).map((subject, index) => {
    const text = `${subject.name} ${subject.identityRule}`;
    const category = inferCategory(text);
    const persistence = inferPersistence(category, subject.identityRule);
    return {
      id: `R${index + 1}`,
      screenZone: inferScreenZone(text, index),
      depth: inferDepth(text, index),
      category,
      sourceState: {
        description: subject.name || `区域 ${index + 1}`,
        materials: inferMaterials(text),
        condition: understanding.visualMood || "源图可见状态",
        identityFeatures: subject.identityRule ? [subject.identityRule] : [],
      },
      persistence,
      temporalPolicy: inferTemporalPolicy(category, persistence, subject.identityRule),
      confidence: clamp01(subject.confidence),
      salience: clamp01(1 - index * 0.06),
    };
  });

  if (!regions.length) {
    regions.push({
      id: "R1",
      screenZone: "center",
      depth: "midground",
      category: "landscape",
      sourceState: {
        description: understanding.summary || "画面主体与环境",
        materials: [],
        condition: understanding.visualMood || "源图状态",
        identityFeatures: [],
      },
      persistence: "persistent_geometry",
      temporalPolicy: "free_evolution",
      confidence: 0.55,
      salience: 1,
    });
  }

  const changeableIds = regions
    .filter((region) => region.temporalPolicy !== "lock")
    .map((region) => region.id);

  return {
    schemaVersion: "scene-graph.v1",
    baseline: {
      locationType: understanding.locationType || "未知场所",
      ...(understanding.timeClues.length
        ? { probableEra: understanding.timeClues.join("；") }
        : {}),
      ...(understanding.summary
        ? { culturalContext: understanding.summary }
        : {}),
    },
    camera: {
      viewpoint: "保持源图相机位置",
      framing: "保持源图画幅、主体占比和边缘裁切",
      horizon: "保持源图地平线高度",
      perspective: "保持源图镜头透视、尺度和消失点",
      vanishingPoints: ["保持源图主要消失点"],
      depthLayout: "保持前景、中景、背景的拓扑、遮挡和相对位置",
    },
    regions,
    globalDrivers: understanding.changeDrivers.slice(0, 8).map((process, index) => ({
      id: `D${index + 1}`,
      process,
      affectedRegionIds: changeableIds,
      confidence: 0.72,
    })),
    uncertainties: [
      "由 V2 简略字段推导；精确边界、材质和屏幕坐标应由 V3 图像分析补充",
    ],
  };
}

export function deriveRenderPlanFromV2(input: {
  sceneGraph: SceneGraph;
  story: GenerationContext["story"];
  exactTarget: ExactTarget;
}): TemporalRenderPlan {
  const { sceneGraph, story, exactTarget } = input;
  const horizonBand = horizonBandFromOffsetDays(exactTarget.offsetDays);
  const years = Math.abs(exactTarget.offsetDays) / 365.25;
  const continuity = inferContinuityMode(
    sceneGraph,
    story.targetBeat.visualPrompt,
    horizonBand
  );
  const regionChanges: RegionTemporalChange[] = [];
  const unchangedRegionIds: string[] = [];

  for (const region of sceneGraph.regions) {
    const action = chooseAction(region, horizonBand, continuity);
    if (action === "preserve") {
      unchangedRegionIds.push(region.id);
      continue;
    }
    regionChanges.push(changeFor(
      region,
      action,
      horizonBand,
      years,
      story.targetBeat.visualPrompt
    ));
  }

  ensureEnvironmentalChange(
    sceneGraph,
    regionChanges,
    unchangedRegionIds,
    horizonBand,
    years,
    story.targetBeat.visualPrompt
  );

  const changedIds = regionChanges.map((change) => change.regionId);
  const changedDomains = unique(regionChanges
    .map((change) => sceneGraph.regions.find((region) => region.id === change.regionId)?.category)
    .filter((category): category is SceneCategory => Boolean(category)));

  const withoutId: Omit<TemporalRenderPlan, "planId"> = {
    schemaVersion: "temporal-render-plan.v1",
    exactTarget,
    horizonBand,
    globalWorldState: {
      eraSummary: `${exactTarget.compactLabel}的同一地点；所有时代线索属于同一连续世界`,
      environmentalState: environmentState(horizonBand),
      technologyState: technologyState(horizonBand, exactTarget.offsetDays),
      humanActivityState: humanActivityState(horizonBand, continuity),
    },
    regionChanges,
    additions: defaultAdditions(sceneGraph, horizonBand, exactTarget),
    removals: regionChanges
      .filter((change) => change.action === "remove")
      .map((change) => ({
        regionId: change.regionId,
        causalReason: change.causalReason,
      })),
    crossRegionCouplings: buildCouplings(sceneGraph, changedIds),
    unchangedRegionIds,
    subjectContinuityMode: continuity,
    prohibitedDrift: [
      "不得改变相机位置、画幅、地平线、透视、尺度和消失点",
      "不得只修改人物年龄、服装或单个显眼物体而冻结环境",
      "不得添加与地点、目标时代和因果计划无关的随机元素",
      "不得用统一复古滤镜、霓虹赛博朋克或泛化未来感代替真实变化",
    ],
    coverage: {
      evaluatedRegionIds: sceneGraph.regions.map((region) => region.id),
      changedRegionIds: changedIds,
      unchangedRegionIds,
      changedDomains,
      foreground: coversDepth(sceneGraph, changedIds, "foreground"),
      midground: coversDepth(sceneGraph, changedIds, "midground"),
      background: coversDepth(sceneGraph, changedIds, "background"),
      principalSubject: regionChanges.some((change) =>
        (sceneGraph.regions.find((region) => region.id === change.regionId)?.salience ?? 0) >= 0.75
      ),
      builtEnvironment: changedDomains.some((category) => BUILT.has(category)),
      naturalEnvironment: changedDomains.some((category) => NATURAL.has(category)),
      technologyInfrastructure: changedDomains.some((category) => TECHNOLOGY.has(category)),
    },
  };

  return { ...withoutId, planId: renderPlanId(withoutId) };
}

export function buildV3ContextFromV2(input: {
  context: GenerationContext;
  timePosition: TimePositionPayload;
  exactTarget: ExactTarget;
}): GenerationContextV3 {
  const sceneGraph = deriveSceneGraphFromV2(input.context.understanding);
  return {
    schemaVersion: "generation-context.v3",
    sceneGraph,
    targetPlan: deriveRenderPlanFromV2({
      sceneGraph,
      story: input.context.story,
      exactTarget: input.exactTarget,
    }),
    temporalStory: input.context.story,
    generationMode: input.context.generationMode,
    qualityPolicy: defaultQualityPolicy(),
  };
}

export function normalizeRenderPlanTarget(
  plan: TemporalRenderPlan,
  exactTarget: ExactTarget
): TemporalRenderPlan {
  const normalized: Omit<TemporalRenderPlan, "planId"> = {
    ...plan,
    exactTarget,
    horizonBand: horizonBandFromOffsetDays(exactTarget.offsetDays),
  };
  const { planId: _ignored, ...withoutId } = normalized as TemporalRenderPlan;
  return { ...withoutId, planId: renderPlanId(withoutId) };
}

export function validateSceneGraph(sceneGraph: SceneGraph): string[] {
  const issues: string[] = [];
  if (sceneGraph.schemaVersion !== "scene-graph.v1") issues.push("unsupported_scene_graph_schema");
  if (!sceneGraph.baseline || !sceneGraph.camera) issues.push("missing_scene_graph_baseline_or_camera");
  if (!Array.isArray(sceneGraph.regions) || sceneGraph.regions.length === 0) issues.push("missing_scene_regions");
  if ((sceneGraph.regions?.length ?? 0) > 16) issues.push("too_many_scene_regions");
  const ids = new Set<string>();
  for (const region of sceneGraph.regions ?? []) {
    if (!region.id || ids.has(region.id)) issues.push("duplicate_or_missing_region_id");
    ids.add(region.id);
    if (!region.sourceState?.description) issues.push(`missing_region_description:${region.id}`);
    if (region.boundingBox && !validBox(region.boundingBox)) issues.push(`invalid_region_box:${region.id}`);
    if (!Number.isFinite(region.confidence) || !Number.isFinite(region.salience)) {
      issues.push(`invalid_region_score:${region.id}`);
    }
  }
  return unique(issues);
}

export function validateTemporalRenderPlan(
  sceneGraph: SceneGraph,
  plan: TemporalRenderPlan
): string[] {
  const issues: string[] = [];
  const regionIds = new Set(sceneGraph.regions.map((region) => region.id));
  const changed = new Set<string>();
  if (plan.schemaVersion !== "temporal-render-plan.v1") issues.push("unsupported_render_plan_schema");
  if (!plan.exactTarget || !Number.isFinite(plan.exactTarget.offsetDays)) issues.push("missing_exact_target");
  if (!Array.isArray(plan.regionChanges)) issues.push("missing_region_changes");

  for (const change of plan.regionChanges ?? []) {
    if (!regionIds.has(change.regionId)) issues.push(`unknown_changed_region:${change.regionId}`);
    if (changed.has(change.regionId)) issues.push(`duplicate_region_change:${change.regionId}`);
    changed.add(change.regionId);
    if (!change.targetState || !change.causalReason) issues.push(`incomplete_region_change:${change.regionId}`);
  }

  for (const regionId of plan.unchangedRegionIds ?? []) {
    if (!regionIds.has(regionId)) issues.push(`unknown_unchanged_region:${regionId}`);
    if (changed.has(regionId)) issues.push(`contradictory_region_policy:${regionId}`);
  }

  const evaluated = new Set(plan.coverage?.evaluatedRegionIds ?? []);
  for (const regionId of regionIds) {
    if (!evaluated.has(regionId)) issues.push(`unevaluated_region:${regionId}`);
    if (!changed.has(regionId) && !(plan.unchangedRegionIds ?? []).includes(regionId)) {
      issues.push(`region_without_policy:${regionId}`);
    }
  }

  const horizon = horizonBandFromOffsetDays(plan.exactTarget?.offsetDays ?? 0);
  const environmentExists = sceneGraph.regions.some((region) => region.category !== "person");
  const environmentChanged = plan.regionChanges.some((change) =>
    sceneGraph.regions.find((region) => region.id === change.regionId)?.category !== "person"
  );
  if (environmentExists && horizon !== "hours_days" && !environmentChanged) {
    issues.push("missing_environmental_change");
  }

  const actualDomains = unique(plan.regionChanges
    .map((change) => sceneGraph.regions.find((region) => region.id === change.regionId)?.category)
    .filter((category): category is SceneCategory => Boolean(category)));
  if (actualDomains.length < minimumDomainCount(horizon, sceneGraph)) {
    issues.push("insufficient_change_domains");
  }
  if (plan.coverage && !sameSet(actualDomains, plan.coverage.changedDomains)) {
    issues.push("coverage_domain_mismatch");
  }

  return unique(issues);
}

export function criticNeedsRegeneration(
  critic: VisualCriticResult,
  policy: QualityPolicy
): boolean {
  if (!policy.visualCriticEnabled || policy.maxRegenerations === 0) return false;
  return !critic.passed
    || critic.cameraConsistency < policy.thresholds.cameraConsistency
    || critic.requiredChangeCompletion < policy.thresholds.requiredChangeCompletion
    || critic.environmentEvolution < policy.thresholds.environmentEvolution
    || critic.eraCoherence < policy.thresholds.eraCoherence;
}

export function renderPlanId(value: unknown): string {
  return createHash("sha256")
    .update(JSON.stringify(value))
    .digest("hex")
    .slice(0, 16);
}

function changeFor(
  region: SceneRegion,
  action: RegionTemporalAction,
  horizon: TimeHorizonBand,
  years: number,
  globalPrompt: string
): RegionTemporalChange {
  return {
    regionId: region.id,
    action,
    magnitude: magnitudeFor(horizon),
    targetState: targetState(region, action, globalPrompt),
    causalReason: `${years.toFixed(1)} 年跨度下的${cause(action)}；区域策略 ${region.temporalPolicy}`,
    visibleEvidence: [
      `${region.screenZone} 的轮廓、材质、尺度、密度或状态呈现 ${action} 的明确证据`,
      ...(region.sourceState.materials.length
        ? [`材料响应：${region.sourceState.materials.join("、")}`]
        : []),
    ],
  };
}

function ensureEnvironmentalChange(
  graph: SceneGraph,
  changes: RegionTemporalChange[],
  unchanged: string[],
  horizon: TimeHorizonBand,
  years: number,
  prompt: string
): void {
  if (horizon === "hours_days") return;
  const hasEnvironment = changes.some((change) =>
    graph.regions.find((region) => region.id === change.regionId)?.category !== "person"
  );
  if (hasEnvironment) return;
  const candidate = graph.regions.find((region) =>
    region.category !== "person" && region.temporalPolicy !== "lock"
  );
  if (!candidate) return;
  const unchangedIndex = unchanged.indexOf(candidate.id);
  if (unchangedIndex >= 0) unchanged.splice(unchangedIndex, 1);
  const action: RegionTemporalAction = candidate.category === "vegetation" ? "grow" : "age";
  changes.push(changeFor(candidate, action, horizon, years, prompt));
}

function chooseAction(
  region: SceneRegion,
  horizon: TimeHorizonBand,
  continuity: SubjectContinuityMode
): RegionTemporalAction {
  if (region.temporalPolicy === "lock") return "preserve";
  if (continuity === "time_traveler" && region.salience >= 0.75) return "preserve";
  if (region.category === "person") {
    if (continuity === "site_only") return "remove";
    if (continuity === "lineage_or_successor") return "replace";
    return horizon === "hours_days" ? "preserve" : "age";
  }
  if (region.temporalPolicy === "grow") return horizon === "hours_days" ? "preserve" : "grow";
  if (region.temporalPolicy === "replace_by_era") {
    return horizon === "hours_days" || horizon === "months" ? "preserve" : "replace";
  }
  if (region.temporalPolicy === "may_disappear") {
    return horizon === "hours_days" || horizon === "months" ? "preserve" : "remove";
  }
  if (region.temporalPolicy === "renovate") {
    if (horizon === "hours_days" || horizon === "months") return "preserve";
    if (horizon === "millennia" || horizon === "deep_time") return "replace";
    return "renovate";
  }
  if ((horizon === "millennia" || horizon === "deep_time")
    && region.persistence !== "persistent_geometry") return "remove";
  if (region.category === "atmosphere") return "replace";
  return horizon === "hours_days" ? "preserve" : "age";
}

function inferContinuityMode(
  graph: SceneGraph,
  visualPrompt: string,
  horizon: TimeHorizonBand
): SubjectContinuityMode {
  if (/时间旅行|穿越|跨越.*年|保持原样.*环境|time traveler/i.test(visualPrompt)) {
    return "time_traveler";
  }
  const principal = [...graph.regions].sort((a, b) => b.salience - a.salience)[0];
  if (!principal) return "site_only";
  if (principal.category === "person") {
    if (horizon === "centuries") return "lineage_or_successor";
    if (horizon === "millennia" || horizon === "deep_time") return "site_only";
    return "age_progression";
  }
  if (principal.category === "vehicle" || principal.category === "architecture") {
    return horizon === "millennia" || horizon === "deep_time"
      ? "object_remains"
      : "identity_persists";
  }
  return horizon === "millennia" || horizon === "deep_time"
    ? "site_only"
    : "identity_persists";
}

function defaultAdditions(
  graph: SceneGraph,
  horizon: TimeHorizonBand,
  target: ExactTarget
): TemporalRenderPlan["additions"] {
  if (horizon === "hours_days" || horizon === "months" || horizon === "years") return [];
  const background = graph.regions.find((region) => region.depth === "background");
  if (!background) return [];
  return [{
    id: "A1",
    screenZone: background.screenZone,
    depth: "background",
    category: /自然|山|河|海/.test(graph.baseline.locationType)
      ? "vegetation"
      : "infrastructure",
    description: `${target.compactLabel}与地点功能一致的背景时代证据；克制、不遮挡原有锚点`,
    causalReason: "长时间跨度应在背景密度、基础设施或生态层留下可见且有因果依据的变化",
  }];
}

function buildCouplings(
  graph: SceneGraph,
  changedIds: string[]
): TemporalRenderPlan["crossRegionCouplings"] {
  const result: TemporalRenderPlan["crossRegionCouplings"] = [];
  const builtIds = graph.regions
    .filter((region) => changedIds.includes(region.id) && BUILT.has(region.category))
    .map((region) => region.id);
  if (builtIds.length > 1) {
    result.push({
      regionIds: builtIds,
      rule: "建筑、地面、道路、标牌和基础设施使用同一时代材料、维护水平和技术语言",
    });
  }
  const naturalIds = graph.regions
    .filter((region) => changedIds.includes(region.id) && NATURAL.has(region.category))
    .map((region) => region.id);
  if (naturalIds.length) {
    result.push({
      regionIds: naturalIds,
      rule: "植被、天气、地表和生态服从同一季节、气候与时间跨度",
    });
  }
  if (changedIds.length) {
    result.push({
      regionIds: changedIds,
      rule: "所有变化共享光照方向、遮挡、尺度、透视和目标时代；禁止混合年代线索",
    });
  }
  return result;
}

function inferCategory(text: string): SceneCategory {
  const value = text.toLowerCase();
  if (/人|女孩|男孩|男性|女性|人物|行人|旅客|乘客|脸|person|woman|man/.test(value)) return "person";
  if (/车|汽车|列车|火车|公交|自行车|su7|vehicle|train/.test(value)) return "vehicle";
  if (/树|草|花|植被|植物|灌木|vegetation/.test(value)) return "vegetation";
  if (/建筑|楼|房|车站|商店|门面|候车厅|architecture|building/.test(value)) return "architecture";
  if (/道路|轨道|站台|桥|护栏|电线|路灯|基础设施|infrastructure/.test(value)) return "infrastructure";
  if (/地面|路面|墙面|桌面|铺装|surface|floor/.test(value)) return "surface";
  if (/招牌|标牌|文字|广告|sign/.test(value)) return "signage";
  if (/椅|桌|家具|座位|furniture/.test(value)) return "furniture";
  if (/天空|云|光线|雾|天气|atmosphere|sky/.test(value)) return "atmosphere";
  if (/山|河|海|地形|景观|landscape/.test(value)) return "landscape";
  if (/动物|猫|狗|鸟|animal/.test(value)) return "animal";
  return "other";
}

function inferDepth(text: string, index: number): SceneDepth {
  if (/天空|云|sky/.test(text)) return "sky";
  if (/前景|近处|foreground/.test(text)) return "foreground";
  if (/背景|远处|天际线|background/.test(text)) return "background";
  if (/中景|midground/.test(text)) return "midground";
  if (index === 0) return "midground";
  return index % 3 === 1 ? "foreground" : index % 3 === 2 ? "background" : "midground";
}

function inferScreenZone(text: string, index: number): ScreenZone {
  const horizontal = /左/.test(text) ? "left" : /右/.test(text) ? "right" : "center";
  const vertical = /上|天空/.test(text) ? "top" : /下|地面|路面/.test(text) ? "bottom" : "middle";
  if (vertical === "middle" && horizontal === "center") return "center";
  const candidate = `${vertical}_${horizontal}`;
  const valid: ScreenZone[] = [
    "top_left", "top_center", "top_right", "middle_left", "middle_right",
    "bottom_left", "bottom_center", "bottom_right",
  ];
  if (valid.includes(candidate as ScreenZone)) return candidate as ScreenZone;
  const fallback: ScreenZone[] = [
    "center", "bottom_center", "middle_left", "middle_right", "top_center",
  ];
  return fallback[index % fallback.length];
}

function inferPersistence(
  category: SceneCategory,
  rule: string
): SceneRegion["persistence"] {
  if (/临时|路过|可消失|transient/.test(rule)) return "transient";
  if (/可替换|翻修|更新|replace/.test(rule)) return "replaceable";
  if (category === "person" || category === "animal") return "persistent_identity";
  if (BUILT.has(category) || category === "landscape") return "persistent_geometry";
  if (category === "vehicle") return "replaceable";
  return "unknown";
}

function inferTemporalPolicy(
  category: SceneCategory,
  persistence: SceneRegion["persistence"],
  rule: string
): TemporalPolicy {
  if (/必须不变|锁定|lock/.test(rule)) return "lock";
  if (/生长|grow/.test(rule) || category === "vegetation") return "grow";
  if (/翻修|改建|renovate/.test(rule)
    || category === "architecture"
    || category === "infrastructure"
    || category === "surface") return "renovate";
  if (/替换|更新|replace/.test(rule)
    || category === "vehicle"
    || category === "signage"
    || category === "furniture") return "replace_by_era";
  if (/消失|移除|may disappear/.test(rule) || persistence === "transient") return "may_disappear";
  if (category === "person" || category === "animal") return "age_in_place";
  return "free_evolution";
}

function inferMaterials(text: string): string[] {
  const materials: string[] = [];
  if (/玻璃/.test(text)) materials.push("glass");
  if (/金属|钢|铁/.test(text)) materials.push("metal");
  if (/木/.test(text)) materials.push("wood");
  if (/混凝土|水泥/.test(text)) materials.push("concrete");
  if (/砖/.test(text)) materials.push("brick");
  if (/塑料/.test(text)) materials.push("plastic");
  if (/沥青/.test(text)) materials.push("asphalt");
  return materials;
}

function targetState(
  region: SceneRegion,
  action: RegionTemporalAction,
  globalPrompt: string
): string {
  const instruction: Record<RegionTemporalAction, string> = {
    preserve: "保持身份、几何和屏幕位置",
    age: "按材料或生命阶段自然老化，并保留可识别锚点",
    grow: "按时间跨度产生可信的体量、密度和形态生长",
    renovate: "保持位置和主要体量，同时体现维护、翻修和时代升级",
    replace: "在相同空间功能和透视位置替换为目标时代对应形态",
    remove: "合理消失，让其空间被目标环境自然接续",
    add_related: "加入与地点功能和目标时代直接相关的可见变化",
  };
  return `${region.screenZone} ${region.depth} ${region.sourceState.description}：${instruction[action]}。全局目标：${globalPrompt}`;
}

function cause(action: RegionTemporalAction): string {
  const values: Record<RegionTemporalAction, string> = {
    preserve: "稳定锚点保持",
    age: "风化、磨损、维护周期或生命阶段变化",
    grow: "生物生长、季节循环与生态演替",
    renovate: "维护翻修、功能升级和基础设施更新",
    replace: "技术迭代、商业更新、重建或文化时代更替",
    remove: "临时实体离场、功能废弃、自然消亡或长期空间重组",
    add_related: "目标时代功能需求和环境演化产生相关元素",
  };
  return values[action];
}

function magnitudeFor(horizon: TimeHorizonBand): RegionTemporalChange["magnitude"] {
  if (horizon === "hours_days" || horizon === "months") return "subtle";
  if (horizon === "years") return "moderate";
  if (horizon === "decades" || horizon === "centuries") return "major";
  return "transformative";
}

function environmentState(horizon: TimeHorizonBand): string {
  const values: Record<TimeHorizonBand, string> = {
    hours_days: "光线、天气、交通与临时活动变化；固定环境基本保持",
    months: "季节、植被状态、装饰与临时工程变化",
    years: "磨损、维护、店铺标牌、车辆与渐进生长变化",
    decades: "成熟植被、建筑翻修、基础设施更新与城市密度变化",
    centuries: "重建、遗迹、生态演替与文化功能更替",
    millennia: "气候、地貌、考古层和文明连续性发生重大变化",
    deep_time: "地质和生态过程主导；短寿命现代元素默认不持续",
  };
  return values[horizon];
}

function technologyState(horizon: TimeHorizonBand, offsetDays: number): string {
  if (horizon === "hours_days" || horizon === "months") return "技术状态基本不变";
  return offsetDays < 0
    ? "回到目标历史时期可信的技术和材料状态"
    : "采用目标时期可信且非泛科幻化的技术和材料状态";
}

function humanActivityState(
  horizon: TimeHorizonBand,
  continuity: SubjectContinuityMode
): string {
  if (horizon === "millennia" || horizon === "deep_time") {
    return continuity === "time_traveler"
      ? "异常锚点保留；其他人类活动按环境时代重新推演"
      : "不强行保留当代人物和活动";
  }
  if (horizon === "centuries") return "人物以继承者、后代或新的使用者体现功能连续性";
  return "人物活动与地点功能、时间跨度和目标时代一致";
}

function coversDepth(
  graph: SceneGraph,
  changedIds: string[],
  depth: SceneDepth
): boolean {
  const regions = graph.regions.filter((region) => region.depth === depth);
  return regions.length === 0 || regions.some((region) => changedIds.includes(region.id));
}

function minimumDomainCount(
  horizon: TimeHorizonBand,
  graph: SceneGraph
): number {
  const available = new Set(graph.regions.map((region) => region.category)).size;
  const desired = horizon === "hours_days" ? 1
    : horizon === "months" ? 2
      : horizon === "years" ? 2
        : horizon === "decades" ? 3
          : horizon === "centuries" ? 3
            : 4;
  return Math.min(desired, available);
}

function validBox(box: { x: number; y: number; width: number; height: number }): boolean {
  return [box.x, box.y, box.width, box.height].every(Number.isFinite)
    && box.x >= 0
    && box.y >= 0
    && box.width > 0
    && box.height > 0
    && box.x + box.width <= 1.01
    && box.y + box.height <= 1.01;
}

function sameSet<T>(left: T[], right: T[]): boolean {
  const a = new Set(left);
  const b = new Set(right);
  return a.size === b.size && [...a].every((value) => b.has(value));
}

function threshold(value: number | undefined, fallback: number): number {
  return Math.max(0.5, Math.min(0.98, Number.isFinite(value) ? value as number : fallback));
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, Number.isFinite(value) ? value : 0));
}

function unique<T>(values: T[]): T[] {
  return [...new Set(values)];
}

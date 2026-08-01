export interface Palette {
  charcoal: string;
  warmWhite: string;
  warmWhiteR: string;
  orange: string;
  orangeRim: string;
  lime: string;
  limeRim: string;
  yellow: string;
  yellowRim: string;
  ground: string;
  road: string;
  sidewalk: string;
  grass: string;
  trunk: string;
  foliage1: string;
  foliage2: string;
  skin: string;
  cloth1: string;
  cloth2: string;
}

export interface ClayMatDefaults {
  roughness: number;
  metalness: number;
  flatShading: boolean;
}

export interface FogSpec {
  color: string;
  density: number;
}

export interface StyleSpec {
  clayMat: ClayMatDefaults;
  fog: FogSpec;
  clearColor: string;
}

export interface EntitySpec {
  id: string;
  category: string;
  type: string;
  position: [number, number, number];
  rotation?: number;
  scale?: number;
  size?: number[];
  [key: string]: unknown;
}

export interface TemporalEntityState {
  weathering?: number;
  structuralVariant?: string;
  newWindows?: boolean;
  greenRoof?: boolean;
  growth?: number;
  crownVolume?: number;
  bodyStage?: string;
  height?: number;
  presence?: number;
  positionOffset?: [number, number, number];
}

export interface TemporalAnchorState {
  year: number;
  entities: Record<string, TemporalEntityState>;
}

export interface TimelineInterval {
  startYear: number;
  endYear: number;
  mode: string;
  narrative: string;
}

export interface TemporalSpec {
  anchorYears: TemporalAnchorState[];
  timelineIntervals: TimelineInterval[];
}

export interface SceneFixture {
  id: string;
  name: string;
  version: string;
  palette: Palette;
  style: StyleSpec;
  entities: EntitySpec[];
  temporalSpec: TemporalSpec;
}

export interface InterpolatedEntityState extends TemporalEntityState {
  presence: number;
  growth: number;
  crownVolume: number;
  weathering: number;
  height: number;
  structuralVariant: string;
  newWindows: boolean;
  bodyStage: string;
  positionOffset: [number, number, number];
}

export interface InterpolatedState {
  states: Record<string, InterpolatedEntityState>;
  lowerYear: number;
  upperYear: number;
}

export * from "./reconstruction-job";
export * from "./assets";

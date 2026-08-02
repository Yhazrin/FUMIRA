import { useEffect, useMemo, useState } from 'react'
import type { FumiraTemporalScene } from '../../types/world'
import {
  CALIBRATION_STAGES,
  buildLayoutPatch,
  computeImageRect,
  evaluateScene,
  stageOfNode,
  type CalibrationStage,
} from './projection'

const STAGE_COLOR = '#ff672a'
const DECLARED_COLOR = '#b7d83d'
const INACTIVE_COLOR = 'rgba(242,238,229,0.28)'

function useViewportSize() {
  const [size, setSize] = useState({ width: window.innerWidth, height: window.innerHeight })
  useEffect(() => {
    const onResize = () => setSize({ width: window.innerWidth, height: window.innerHeight })
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])
  return size
}

export function CalibrationOverlay({
  scene,
  year,
  sourceImageUrl,
  imageAspect,
  onImageAspect,
}: {
  scene: FumiraTemporalScene
  year: number
  sourceImageUrl?: string
  imageAspect: number
  onImageAspect: (aspect: number) => void
}) {
  const viewport = useViewportSize()
  const [opacity, setOpacity] = useState(0.55)
  const [stage, setStage] = useState<CalibrationStage>(0)
  const [copied, setCopied] = useState(false)

  const rect = computeImageRect(viewport.width, viewport.height, imageAspect)
  const evaluation = useMemo(() => evaluateScene(scene, year, imageAspect), [scene, year, imageAspect])
  const patch = useMemo(() => buildLayoutPatch(scene, year, imageAspect, stage), [scene, year, imageAspect, stage])
  const patchJson = patch ? JSON.stringify(patch, null, 2) : null
  const stageIssueCount = (target: CalibrationStage) =>
    evaluation.issues.filter((issue) => issue.stage === target).length

  const copyPatch = async () => {
    if (!patchJson) return
    try {
      await navigator.clipboard.writeText(patchJson)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1600)
    } catch {
      // clipboard unavailable; the JSON stays selectable in the panel
    }
  }

  return (
    <div className="pointer-events-none fixed inset-0 z-20">
      {sourceImageUrl && (
        <img
          src={sourceImageUrl}
          alt="Source reference"
          style={{
            position: 'absolute',
            left: rect.x,
            top: rect.y,
            width: rect.width,
            height: rect.height,
            opacity,
          }}
          draggable={false}
          onLoad={(event) => {
            const image = event.currentTarget
            if (image.naturalWidth && image.naturalHeight) {
              onImageAspect(image.naturalWidth / image.naturalHeight)
            }
          }}
        />
      )}

      <svg
        style={{ position: 'absolute', left: rect.x, top: rect.y }}
        width={rect.width}
        height={rect.height}
        viewBox={`0 0 ${rect.width} ${rect.height}`}
      >
        {evaluation.projections.map((projected) => {
          if (!projected.visible) return null
          const active = stageOfNode(projected.node) === stage
          const [px, py, pw, ph] = projected.box
          const declared = projected.node.imageBox
          return (
            <g key={projected.node.id}>
              <rect
                x={px * rect.width}
                y={py * rect.height}
                width={pw * rect.width}
                height={ph * rect.height}
                fill="none"
                stroke={active ? STAGE_COLOR : INACTIVE_COLOR}
                strokeWidth={active ? 2 : 1}
              />
              {active && declared && (
                <rect
                  x={declared[0] * rect.width}
                  y={declared[1] * rect.height}
                  width={declared[2] * rect.width}
                  height={declared[3] * rect.height}
                  fill="none"
                  stroke={DECLARED_COLOR}
                  strokeWidth={1.5}
                  strokeDasharray="6 4"
                />
              )}
              {active && (
                <text
                  x={px * rect.width + 3}
                  y={py * rect.height - 4}
                  fill={STAGE_COLOR}
                  fontSize={10}
                  fontWeight={700}
                  style={{ paintOrder: 'stroke', stroke: '#202425', strokeWidth: 2.5 }}
                >
                  {projected.node.id} · d={projected.distance.toFixed(1)}m
                </text>
              )}
            </g>
          )
        })}
      </svg>

      {sourceImageUrl && (
        <div className="pointer-events-auto absolute bottom-24 left-4 w-40 overflow-hidden rounded-xl border border-white/25 shadow-lg">
          <img src={sourceImageUrl} alt="Original" className="block w-full" draggable={false} />
          <div className="bg-[#202425] px-2 py-1 text-[9px] font-bold tracking-[0.14em] text-[#b7d83d]">原图</div>
        </div>
      )}

      <aside className="pointer-events-auto absolute right-4 top-4 flex max-h-[calc(100vh-8rem)] w-80 flex-col gap-3 overflow-y-auto rounded-2xl border border-white/15 bg-[#202425]/95 p-4 text-[#f2eee5] shadow-2xl backdrop-blur">
        <header className="flex items-center justify-between">
          <h2 className="text-[11px] font-black tracking-[0.18em] text-[#ff672a]">对照校正模式</h2>
          <span className="rounded bg-white/10 px-2 py-0.5 text-[10px] font-bold">{Math.round(year)}</span>
        </header>

        <label className="flex items-center gap-2 text-[10px] font-bold tracking-wide text-white/60">
          原图叠加
          <input
            className="flex-1 accent-[#ff672a]"
            type="range"
            min={0}
            max={1}
            step={0.05}
            value={opacity}
            onChange={(event) => setOpacity(Number(event.target.value))}
            aria-label="Overlay opacity"
          />
          {(opacity * 100).toFixed(0)}%
        </label>

        <div>
          <p className="mb-1.5 text-[9px] font-bold tracking-[0.14em] text-white/40">一次只修正一个层级</p>
          <div className="grid grid-cols-2 gap-1.5">
            {CALIBRATION_STAGES.map(({ stage: value, label }) => {
              const count = stageIssueCount(value)
              const selected = value === stage
              return (
                <button
                  key={value}
                  onClick={() => setStage(value)}
                  className={`rounded-lg px-2 py-1.5 text-left text-[10px] font-bold transition ${
                    selected ? 'bg-[#ff672a] text-[#202425]' : 'bg-white/10 text-white/75 hover:bg-white/20'
                  }`}
                >
                  {value + 1}. {label}
                  {count > 0 && (
                    <span className={`ml-1 rounded px-1 ${selected ? 'bg-[#202425] text-[#ffc52a]' : 'bg-[#ff672a]/80 text-[#202425]'}`}>
                      {count}
                    </span>
                  )}
                </button>
              )
            })}
          </div>
        </div>

        <div>
          <p className="mb-1 text-[9px] font-bold tracking-[0.14em] text-white/40">
            关系与构图错误（{evaluation.issues.length}）
          </p>
          <ul className="flex flex-col gap-1">
            {evaluation.issues.length === 0 && (
              <li className="rounded-lg bg-[#b7d83d]/15 px-2 py-1.5 text-[10px] font-bold text-[#b7d83d]">
                固定机位检查全部通过
              </li>
            )}
            {evaluation.issues.map((issue, index) => (
              <li
                key={`${issue.kind}-${issue.nodeIds.join('-')}-${index}`}
                className={`rounded-lg px-2 py-1.5 text-[10px] leading-snug ${
                  issue.stage === stage ? 'bg-[#ff672a]/15 text-[#ffb28f]' : 'bg-white/5 text-white/45'
                }`}
              >
                <span className="mr-1 rounded bg-white/10 px-1 text-[8px] font-black uppercase tracking-wider">
                  {issue.kind}
                </span>
                {issue.message}
              </li>
            ))}
          </ul>
        </div>

        <div>
          <div className="mb-1 flex items-center justify-between">
            <p className="text-[9px] font-bold tracking-[0.14em] text-white/40">SCENE LAYOUT PATCH</p>
            {patchJson && (
              <button
                onClick={copyPatch}
                className="rounded bg-[#b7d83d] px-2 py-0.5 text-[9px] font-black text-[#202425] hover:bg-[#c9e35a]"
              >
                {copied ? '已复制' : '复制 JSON'}
              </button>
            )}
          </div>
          {patchJson ? (
            <pre className="max-h-52 select-text overflow-auto rounded-lg bg-black/45 p-2 text-[9px] leading-relaxed text-[#b7d83d]">
              {patchJson}
            </pre>
          ) : (
            <p className="rounded-lg bg-white/5 px-2 py-1.5 text-[10px] text-white/45">当前层级无需修正</p>
          )}
        </div>
      </aside>
    </div>
  )
}

import type { FumiraTemporalScene } from '../../types/world'
import { timelineRange } from './interpolate'

export function TemporalTimeline({ scene, year, onYearChange, calibration = false, onCalibrationToggle }: { scene: FumiraTemporalScene; year: number; onYearChange: (year: number) => void; calibration?: boolean; onCalibrationToggle?: () => void }) {
  const [min, max] = timelineRange(scene)
  return <section className="fixed inset-x-4 bottom-5 z-30 mx-auto max-w-xl rounded-3xl border border-white/20 bg-[#f2eee5]/95 px-5 py-4 text-[#202425] shadow-[0_10px_0_#cec7b8,0_24px_40px_rgba(0,0,0,0.35)] backdrop-blur">
    <div className="mb-2 flex items-center justify-between text-[10px] font-black tracking-[0.16em]">
      <span className="text-[#c9441d]">FUMIRA TEMPORAL SCENE</span>
      <span className="flex items-center gap-2">
        {onCalibrationToggle && (
          <button
            onClick={onCalibrationToggle}
            className={`rounded-lg px-2 py-1 text-[10px] font-black tracking-[0.08em] transition ${calibration ? 'bg-[#ff672a] text-[#202425]' : 'bg-[#202425]/10 text-[#202425] hover:bg-[#202425]/20'}`}
          >
            {calibration ? '退出校正' : '对照校正'}
          </button>
        )}
        <span className="rounded-lg bg-[#202425] px-2 py-1 text-base tracking-normal text-[#b7d83d]">{Math.round(year)}</span>
      </span>
    </div>
    <input className="w-full accent-[#ff672a]" type="range" min={min} max={max} value={year} step="0.1" onChange={(event) => onYearChange(Number(event.target.value))} aria-label="Temporal year" />
    <div className="mt-2 flex justify-between text-[9px] font-bold tracking-[0.12em] text-[#5b5750]"><span>{min}</span><span>CANONICAL ENTITY PATCHES</span><span>{max}</span></div>
  </section>
}

import { OrbitControls } from '@react-three/drei'
import { useThree } from '@react-three/fiber'
import { useEffect } from 'react'
import * as THREE from 'three'
import type { FumiraTemporalScene, TemporalSceneNode } from '../../types/world'
import { computeImageRect } from '../calibration/projection'
import { interpolateTemporalNode } from './interpolate'

const PALETTE = {
  charcoal: '#202425',
  warmWhite: '#f2eee5',
  warmWhiteRim: '#cec7b8',
  orange: '#ff672a',
  red: '#b51f2a',
  lime: '#b7d83d',
  trunk: '#5c4033',
  foliage: '#7e9a27',
  sidewalk: '#c8c0b2',
  road: '#9e9688',
  skin: '#f2d5b5',
  cloth: '#263a5c',
}

function clay(color: string, roughness = 0.72) {
  return new THREE.MeshStandardMaterial({ color, roughness, metalness: 0 })
}

function NodeProxy({ node }: { node: TemporalSceneNode & { rotation: [number, number, number]; scale: [number, number, number]; opacity: number } }) {
  const groupProps = {
    position: node.position,
    rotation: node.rotation,
    scale: node.scale,
    visible: node.opacity > 0.01,
  } as const
  const transparentMaterial = (color: string, roughness = 0.72) => {
    const result = clay(color, roughness)
    result.transparent = node.opacity < 1
    result.opacity = node.opacity
    return result
  }

  if (node.kind === 'tree') {
    return <group {...groupProps}>
      <mesh position={[0, node.height / 2, 0]} castShadow receiveShadow material={transparentMaterial(PALETTE.trunk)}>
        <cylinderGeometry args={[0.14, 0.22, node.height, 10]} />
      </mesh>
      {[[-0.25, 0.78], [0.24, 0.78], [0, 1.02], [0.06, 0.56]].map(([x, y], index) => (
        <mesh key={index} position={[x, node.height * y, index % 2 ? 0.12 : -0.12]} castShadow material={transparentMaterial(PALETTE.foliage, 0.88)}>
          <sphereGeometry args={[Math.max(node.footprint[0] * 0.45, 0.4), 14, 10]} />
        </mesh>
      ))}
    </group>
  }

  if (node.kind === 'moped') {
    return <group {...groupProps}>
      {[-0.42, 0.42].map((x) => <mesh key={x} position={[x, 0.22, 0]} rotation={[0, Math.PI / 2, 0]} castShadow material={transparentMaterial(PALETTE.charcoal, 0.9)}><torusGeometry args={[0.21, 0.055, 10, 18]} /></mesh>)}
      <mesh position={[0, 0.45, 0]} castShadow material={transparentMaterial(node.color ?? PALETTE.red, 0.56)}><boxGeometry args={[0.88, 0.34, 0.38, 3, 2, 3]} /></mesh>
      <mesh position={[-0.1, 0.72, 0]} castShadow material={transparentMaterial(PALETTE.charcoal, 0.75)}><boxGeometry args={[0.52, 0.12, 0.34, 3, 2, 3]} /></mesh>
      <mesh position={[0.42, 0.84, 0]} rotation={[0, 0, -0.25]} material={transparentMaterial(node.color ?? PALETTE.red)}><cylinderGeometry args={[0.04, 0.05, 0.48, 8]} /></mesh>
      <mesh position={[0.53, 1.08, 0]} rotation={[Math.PI / 2, 0, 0]} material={transparentMaterial(PALETTE.charcoal)}><cylinderGeometry args={[0.028, 0.028, 0.38, 8]} /></mesh>
    </group>
  }

  if (node.kind === 'person') {
    return <group {...groupProps}>
      <mesh position={[0, node.height * 0.48, 0]} castShadow material={transparentMaterial(PALETTE.cloth)}><capsuleGeometry args={[0.18, node.height * 0.52, 6, 10]} /></mesh>
      <mesh position={[0, node.height * 0.88, 0]} castShadow material={transparentMaterial(PALETTE.skin)}><sphereGeometry args={[0.18, 12, 10]} /></mesh>
      <mesh position={[0, node.height * 0.98, 0]} material={transparentMaterial(PALETTE.charcoal)}><sphereGeometry args={[0.19, 12, 6, 0, Math.PI * 2, 0, Math.PI * 0.58]} /></mesh>
    </group>
  }

  if (node.kind === 'utility-box') {
    return <group {...groupProps}>
      <mesh position={[0, node.height * 0.6, 0]} castShadow receiveShadow material={transparentMaterial(PALETTE.warmWhite, 0.68)}><boxGeometry args={[node.footprint[0], node.height * 0.72, node.footprint[1], 3, 3, 2]} /></mesh>
      <mesh position={[0, node.height, 0]} material={transparentMaterial(PALETTE.warmWhiteRim)}><boxGeometry args={[node.footprint[0] + 0.1, 0.11, node.footprint[1] + 0.1]} /></mesh>
      {[-0.35, 0.35].map((x) => <mesh key={x} position={[x, node.height * 0.18, 0]} material={transparentMaterial(PALETTE.warmWhiteRim)}><boxGeometry args={[0.08, node.height * 0.35, 0.08]} /></mesh>)}
    </group>
  }

  const color = node.kind === 'road' ? PALETTE.road : node.kind === 'hedge' ? PALETTE.foliage : node.color ?? PALETTE.warmWhite
  return <group {...groupProps}>
    <mesh position={[0, node.height / 2, 0]} castShadow receiveShadow material={transparentMaterial(color, node.kind === 'road' ? 0.94 : 0.76)}>
      <boxGeometry args={[node.footprint[0], node.height, node.footprint[1], 3, 2, 3]} />
    </mesh>
  </group>
}

function SceneCamera({ scene }: { scene: FumiraTemporalScene }) {
  const { camera } = useThree()
  useEffect(() => {
    camera.position.set(...scene.camera.position)
    if (camera instanceof THREE.PerspectiveCamera) camera.fov = scene.camera.fov
    camera.lookAt(...scene.camera.target)
    camera.updateProjectionMatrix()
  }, [camera, scene])
  return <OrbitControls enableDamping target={scene.camera.target} maxPolarAngle={Math.PI * 0.49} minDistance={4} maxDistance={22} />
}

/** Locks the render camera to the photo camera and pixel-aligns it with the letterboxed source image. */
function CalibrationCamera({ scene, imageAspect }: { scene: FumiraTemporalScene; imageAspect: number }) {
  const camera = useThree((state) => state.camera)
  const size = useThree((state) => state.size)
  useEffect(() => {
    if (!(camera instanceof THREE.PerspectiveCamera)) return
    const managed = camera as THREE.PerspectiveCamera & { manual?: boolean }
    const rect = computeImageRect(size.width, size.height, imageAspect)
    managed.manual = true
    camera.fov = scene.camera.fov
    camera.aspect = rect.width / rect.height
    camera.position.set(...scene.camera.position)
    camera.setViewOffset(rect.width, rect.height, -rect.x, -rect.y, size.width, size.height)
    camera.lookAt(...scene.camera.target)
    camera.updateProjectionMatrix()
    return () => {
      camera.clearViewOffset()
      managed.manual = false
      camera.aspect = size.width / size.height
      camera.updateProjectionMatrix()
    }
  }, [camera, size, scene, imageAspect])
  return null
}

export function TemporalSandbox({ scene, year, calibration = false, imageAspect = 4 / 3 }: { scene: FumiraTemporalScene; year: number; calibration?: boolean; imageAspect?: number }) {
  const nodes = scene.nodes.map((node) => interpolateTemporalNode(scene, node, year))
  return <>
    <color attach="background" args={[PALETTE.charcoal]} />
    <fog attach="fog" args={[PALETTE.charcoal, 10, 32]} />
    <ambientLight color={PALETTE.warmWhite} intensity={0.58} />
    <directionalLight castShadow color="#fff0df" intensity={1.35} position={[5, 9, 4]} shadow-mapSize={[2048, 2048]} />
    <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, scene.bounds.groundY - 0.03, 0]} receiveShadow material={clay(PALETTE.charcoal, 1)}>
      <planeGeometry args={[scene.bounds.width + 8, scene.bounds.depth + 8]} />
    </mesh>
    {nodes.map((node) => <NodeProxy key={node.id} node={node} />)}
    {calibration ? <CalibrationCamera scene={scene} imageAspect={imageAspect} /> : <SceneCamera scene={scene} />}
  </>
}

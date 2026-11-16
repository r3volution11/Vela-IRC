// Pixel sizes of the images in public/screenshots, measured by
// scripts/generate.mjs, so <img> tags can reserve their space.
import sizes from '../../_generated/image-sizes.json'

export function imageSize(src: string): { width: number; height: number } | undefined {
  return (sizes as Record<string, { width: number; height: number }>)[src.replace(/^\//, '')]
}

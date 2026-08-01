#!/usr/bin/env python3
"""Build deterministic frame, preview, and app-resource outputs from sprite grids.

The visual source remains generator-owned. This script only removes empty canvas,
normalizes fixed grid cells with one shared transform, validates alpha/edges, and
packages portable frame sequences.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


@dataclass(frozen=True)
class Grid:
    columns: int
    rows: int


@dataclass(frozen=True)
class FrameReport:
    file: str
    width: int
    height: int
    visible_pixels: int
    edge_pixels: int
    coverage: float
    anchor_x: int
    anchor_y: int


def parse_size(value: str) -> tuple[int, int]:
    pieces = value.lower().split("x", maxsplit=1)
    if len(pieces) != 2:
        raise argparse.ArgumentTypeError("size must use WIDTHxHEIGHT")
    width, height = (int(piece) for piece in pieces)
    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("size must be positive")
    return width, height


def frame_bounds(
    sheet_size: tuple[int, int],
    grid: Grid,
    index: int,
) -> tuple[int, int, int, int]:
    column = index % grid.columns
    row = index // grid.columns
    width, height = sheet_size
    left = round(column * width / grid.columns)
    right = round((column + 1) * width / grid.columns)
    top = round(row * height / grid.rows)
    bottom = round((row + 1) * height / grid.rows)
    return left, top, right, bottom


def weighted_quantile(histogram: list[int], quantile: float) -> int:
    total = sum(histogram)
    if total <= 0:
        return 0
    target = total * min(max(quantile, 0), 1)
    accumulated = 0
    for index, value in enumerate(histogram):
        accumulated += value
        if accumulated >= target:
            return index
    return len(histogram) - 1


def alpha_anchor(image: Image.Image) -> tuple[int, int]:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        return image.width // 2, image.height // 2

    _, top, _, bottom = bounds
    lower_start = top + round((bottom - top) * 0.58)
    x_histogram = [0] * image.width
    y_histogram = [0] * image.height
    pixels = alpha.load()
    for y in range(top, bottom):
        for x in range(image.width):
            value = pixels[x, y]
            if value < 16:
                continue
            y_histogram[y] += value
            if y >= lower_start:
                x_histogram[x] += value

    center_x = weighted_quantile(x_histogram, 0.5)
    baseline_y = weighted_quantile(y_histogram, 0.995)
    return center_x, baseline_y


def remove_isolated_artifacts(image: Image.Image) -> Image.Image:
    cleaned = image.copy()
    alpha = cleaned.getchannel("A")
    width, height = cleaned.size
    alpha_bytes = alpha.tobytes()
    visited = bytearray(width * height)
    components: list[tuple[list[int], tuple[int, int, int, int]]] = []

    for start in range(width * height):
        if visited[start] or alpha_bytes[start] < 16:
            continue
        stack = [start]
        visited[start] = 1
        pixels: list[int] = []
        min_x = width
        min_y = height
        max_x = 0
        max_y = 0
        while stack:
            index = stack.pop()
            pixels.append(index)
            x = index % width
            y = index // width
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
            for neighbor in (
                index - width - 1,
                index - width,
                index - width + 1,
                index - 1,
                index + 1,
                index + width - 1,
                index + width,
                index + width + 1,
            ):
                if neighbor < 0 or neighbor >= width * height:
                    continue
                neighbor_x = neighbor % width
                if abs(neighbor_x - x) > 1:
                    continue
                if not visited[neighbor] and alpha_bytes[neighbor] >= 16:
                    visited[neighbor] = 1
                    stack.append(neighbor)
        components.append((pixels, (min_x, min_y, max_x + 1, max_y + 1)))

    if not components:
        return cleaned
    _, largest_bounds = max(components, key=lambda component: len(component[0]))
    expanded_largest = (
        max(0, largest_bounds[0] - 12),
        max(0, largest_bounds[1] - 12),
        min(width, largest_bounds[2] + 12),
        min(height, largest_bounds[3] + 12),
    )
    minimum_area = max(96, width * height // 2_500)
    rgba = cleaned.load()
    for pixels, bounds in components:
        overlaps_main = not (
            bounds[2] < expanded_largest[0]
            or bounds[0] > expanded_largest[2]
            or bounds[3] < expanded_largest[1]
            or bounds[1] > expanded_largest[3]
        )
        if len(pixels) >= minimum_area or overlaps_main:
            continue
        for index in pixels:
            rgba[index % width, index // width] = (0, 0, 0, 0)
    return cleaned


def fit_cells(
    cells: list[Image.Image],
    output_size: tuple[int, int],
    padding: int,
    registration_scale: tuple[float, float] | None = None,
) -> list[Image.Image]:
    output_width, output_height = output_size
    available_width = max(output_width - 2 * padding, 1)
    available_height = max(output_height - 2 * padding, 1)
    target_x = output_width // 2
    target_y = output_height - max(padding * 4, round(output_height * 0.125))

    source_anchors = [alpha_anchor(cell) for cell in cells]
    source_bounds = [cell.getchannel("A").getbbox() for cell in cells]
    horizontal_scale_limits = [available_width / cells[0].width]
    vertical_scale_limits = [available_height / cells[0].height]
    for bounds, anchor in zip(source_bounds, source_anchors, strict=True):
        if bounds is None:
            continue
        left, top, right, bottom = bounds
        horizontal_limits = (
            (target_x - padding, anchor[0] - left),
            (output_width - padding - target_x, right - anchor[0]),
        )
        vertical_limits = (
            (target_y - padding, anchor[1] - top),
            (output_height - padding - target_y, bottom - anchor[1]),
        )
        for available, extent in horizontal_limits:
            if extent > 0:
                horizontal_scale_limits.append(available / extent)
        for available, extent in vertical_limits:
            if extent > 0:
                vertical_scale_limits.append(available / extent)
    maximum_safe_scale_x = min(horizontal_scale_limits)
    maximum_safe_scale_y = min(vertical_scale_limits)
    if registration_scale is not None:
        scale_x, scale_y = registration_scale
        if scale_x <= 0 or scale_y <= 0:
            raise ValueError("registrationScale must be positive")
        if scale_x > maximum_safe_scale_x or scale_y > maximum_safe_scale_y:
            raise ValueError(
                "registrationScale would crop a registered frame: "
                f"({scale_x:.4f}, {scale_y:.4f}) > "
                f"({maximum_safe_scale_x:.4f}, {maximum_safe_scale_y:.4f})"
            )
    else:
        shared_scale = min(maximum_safe_scale_x, maximum_safe_scale_y)
        scale_x = shared_scale
        scale_y = shared_scale

    resized_cells: list[Image.Image] = []
    anchors: list[tuple[int, int]] = []
    for cell in cells:
        resized_size = (
            max(1, round(cell.width * scale_x)),
            max(1, round(cell.height * scale_y)),
        )
        resized = cell.resize(resized_size, Image.Resampling.NEAREST)
        resized_cells.append(resized)
        anchors.append(alpha_anchor(resized))

    # Every clip uses the same output-space anchor. This is what prevents a
    # generator's per-row placement drift from becoming visible motion at clip
    # boundaries or when random actions return to the base loop.
    frames: list[Image.Image] = []
    for resized, anchor in zip(resized_cells, anchors, strict=True):
        canvas = Image.new("RGBA", output_size, (0, 0, 0, 0))
        origin = (
            target_x - anchor[0],
            target_y - anchor[1],
        )
        canvas.alpha_composite(resized, origin)
        frames.append(canvas)
    return frames


def alpha_report(image: Image.Image, file_name: str) -> FrameReport:
    alpha = image.getchannel("A")
    histogram = alpha.histogram()
    visible_pixels = sum(histogram[1:])
    total_pixels = image.width * image.height
    pixels = alpha.load()
    edge_pixels = 0
    for x in range(image.width):
        edge_pixels += int(pixels[x, 0] > 0)
        edge_pixels += int(pixels[x, image.height - 1] > 0)
    for y in range(1, image.height - 1):
        edge_pixels += int(pixels[0, y] > 0)
        edge_pixels += int(pixels[image.width - 1, y] > 0)
    anchor_x, anchor_y = alpha_anchor(image)
    return FrameReport(
        file=file_name,
        width=image.width,
        height=image.height,
        visible_pixels=visible_pixels,
        edge_pixels=edge_pixels,
        coverage=round(visible_pixels / total_pixels, 6),
        anchor_x=anchor_x,
        anchor_y=anchor_y,
    )


def checkerboard(size: tuple[int, int], block: int = 16) -> Image.Image:
    image = Image.new("RGB", size, (246, 241, 229))
    draw = ImageDraw.Draw(image)
    alternate = (224, 218, 205)
    for y in range(0, size[1], block):
        for x in range(0, size[0], block):
            if (x // block + y // block) % 2:
                draw.rectangle(
                    (x, y, min(x + block - 1, size[0] - 1), min(y + block - 1, size[1] - 1)),
                    fill=alternate,
                )
    return image


def make_contact_sheet(
    frames: list[Image.Image],
    sequence_name: str,
    output: Path,
) -> None:
    columns = 3
    rows = math.ceil(len(frames) / columns)
    label_height = 34
    margin = 12
    frame_width, frame_height = frames[0].size
    width = margin + columns * (frame_width + margin)
    height = 54 + rows * (frame_height + label_height + margin)
    sheet = Image.new("RGB", (width, height), (29, 29, 31))
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 16), sequence_name, fill=(247, 244, 234))
    for index, frame in enumerate(frames):
        column = index % columns
        row = index // columns
        x = margin + column * (frame_width + margin)
        y = 54 + row * (frame_height + label_height + margin)
        background = checkerboard(frame.size)
        background.paste(frame, mask=frame.getchannel("A"))
        sheet.paste(background, (x, y))
        draw.text((x, y + frame_height + 8), f"FRAME {index:02d}", fill=(179, 228, 43))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def make_gif(
    frames: list[Image.Image],
    output: Path,
    duration_ms: int | list[int],
    loop: bool,
) -> None:
    prepared: list[Image.Image] = []
    for frame in frames:
        alpha = frame.getchannel("A")
        paletted = frame.convert("RGB").convert(
            "P",
            palette=Image.Palette.ADAPTIVE,
            colors=255,
        )
        transparent_mask = alpha.point(lambda value: 255 if value <= 16 else 0)
        paletted.paste(255, mask=transparent_mask)
        paletted.info["transparency"] = 255
        prepared.append(paletted)
    output.parent.mkdir(parents=True, exist_ok=True)
    prepared[0].save(
        output,
        save_all=True,
        append_images=prepared[1:],
        duration=duration_ms,
        loop=0 if loop else 1,
        disposal=2,
        transparency=255,
        optimize=False,
    )


def make_animated_webp(
    frames: list[Image.Image],
    output: Path,
    duration_ms: int | list[int],
    loop: bool,
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=duration_ms,
        loop=0 if loop else 1,
        lossless=True,
        method=6,
    )


def make_mp4(
    frame_files: list[Path],
    output: Path,
    duration_ms: int | list[int],
    ffmpeg: str | None,
) -> str:
    if not ffmpeg:
        return "skipped: ffmpeg unavailable"
    output.parent.mkdir(parents=True, exist_ok=True)
    durations = (
        [duration_ms] * len(frame_files)
        if isinstance(duration_ms, int)
        else duration_ms
    )
    if len(frame_files) != len(durations):
        raise ValueError("MP4 frame and duration counts must match")

    with tempfile.TemporaryDirectory(
        prefix=".fumira-mp4-",
        dir=output.parent,
    ) as temporary_directory:
        temporary_path = Path(temporary_directory)
        opaque_frames: list[Path] = []
        for index, frame_file in enumerate(frame_files):
            foreground = Image.open(frame_file).convert("RGBA")
            background = Image.new("RGBA", foreground.size, (246, 243, 232, 255))
            background.alpha_composite(foreground)
            opaque_frame = temporary_path / f"frame-{index:04d}.png"
            background.convert("RGB").save(opaque_frame, optimize=True)
            opaque_frames.append(opaque_frame)

        concat_lines = ["ffconcat version 1.0"]
        for frame_file, frame_duration in zip(
            opaque_frames,
            durations,
            strict=True,
        ):
            escaped_path = str(frame_file).replace("'", "'\\''")
            concat_lines.append(f"file '{escaped_path}'")
            concat_lines.append(f"duration {frame_duration / 1_000:.6f}")
        escaped_last_path = str(opaque_frames[-1]).replace("'", "'\\''")
        concat_lines.append(f"file '{escaped_last_path}'")
        concat_file = temporary_path / "frames.ffconcat"
        concat_file.write_text("\n".join(concat_lines) + "\n", encoding="utf-8")

        command = [
            ffmpeg,
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_file),
            "-t",
            f"{sum(durations) / 1_000:.6f}",
            "-fps_mode",
            "vfr",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-c:v",
            "libx264",
            str(output),
        ]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return f"failed: ffmpeg exited {result.returncode}: {result.stderr[-400:]}"
    return "created"


def relative_to_manifest(manifest_path: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return manifest_path.parent / path


def load_clip_cells(
    manifest_path: Path,
    clip: dict[str, Any],
    grid: Grid,
) -> list[Image.Image]:
    source_key = "transparentSource" if clip.get("transparentSource") else "source"
    source = relative_to_manifest(manifest_path, clip[source_key])
    sheet = Image.open(source).convert("RGBA")
    return [
        remove_isolated_artifacts(
            sheet.crop(frame_bounds(sheet.size, grid, index))
        )
        for index in range(int(clip["frameCount"]))
    ]


def boundary_size(cells: list[Image.Image]) -> tuple[float, float]:
    boundary_cells = cells if len(cells) == 1 else [cells[0], cells[-1]]
    widths: list[int] = []
    heights: list[int] = []
    for cell in boundary_cells:
        bounds = cell.getchannel("A").getbbox()
        if bounds is None:
            continue
        widths.append(bounds[2] - bounds[0])
        heights.append(bounds[3] - bounds[1])
    if not widths or not heights:
        raise ValueError("cannot register an empty clip boundary")
    return sum(widths) / len(widths), sum(heights) / len(heights)


def build_clip(
    manifest_path: Path,
    sequence: dict[str, Any],
    clip: dict[str, Any],
    grid: Grid,
    output_dir: Path,
    resource_dir: Path,
    output_size: tuple[int, int],
    padding: int,
    ffmpeg: str | None,
    registration_scale: tuple[float, float] | None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    source_key = "transparentSource" if clip.get("transparentSource") else "source"
    source = relative_to_manifest(manifest_path, clip[source_key])
    if not source.exists():
        raise FileNotFoundError(
            f"missing source for {sequence['id']}/{clip['id']}: {source}"
        )

    sheet = Image.open(source).convert("RGBA")
    frame_count = int(clip["frameCount"])
    if frame_count > grid.columns * grid.rows:
        raise ValueError(
            f"{sequence['id']}/{clip['id']} has more frames than grid slots"
        )

    clip_output = output_dir / sequence["id"] / "clips" / clip["id"]
    frames_dir = clip_output / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    resource_dir.mkdir(parents=True, exist_ok=True)

    source_cells = load_clip_cells(manifest_path, clip, grid)
    frame_images = fit_cells(
        source_cells,
        output_size,
        padding,
        registration_scale,
    )
    frame_files: list[Path] = []
    resource_names: list[str] = []
    frame_reports: list[FrameReport] = []
    safe_sequence_id = sequence["id"].replace("-", "_")
    safe_clip_id = clip["id"].replace("-", "_")
    for index, frame in enumerate(frame_images):
        frame_name = f"frame-{index:02d}.png"
        frame_path = frames_dir / frame_name
        frame.save(frame_path, optimize=True)

        resource_name = (
            f"doraemon_{safe_sequence_id}_{safe_clip_id}_{index:02d}.png"
        )
        shutil.copy2(frame_path, resource_dir / resource_name)
        frame_files.append(frame_path)
        resource_names.append(resource_name)
        frame_reports.append(alpha_report(frame, frame_name))

    empty_frames = [report.file for report in frame_reports if report.visible_pixels == 0]
    clipped_frames = [report.file for report in frame_reports if report.edge_pixels > 0]
    if empty_frames:
        raise ValueError(
            f"{sequence['id']}/{clip['id']} contains empty frames: {empty_frames}"
        )
    if clipped_frames:
        raise ValueError(
            f"{sequence['id']}/{clip['id']} touches output edges: {clipped_frames}"
        )

    duration_ms = int(clip["frameDurationMilliseconds"])
    loop = bool(clip.get("loop", True))
    contact_sheet = clip_output / "contact-sheet.png"
    gif = clip_output / f"{clip['id']}.gif"
    webp = clip_output / f"{clip['id']}.webp"
    mp4 = clip_output / f"{clip['id']}.mp4"
    make_contact_sheet(
        frame_images,
        f"{sequence['id']} / {clip['id']}",
        contact_sheet,
    )
    make_gif(frame_images, gif, duration_ms, loop)
    make_animated_webp(frame_images, webp, duration_ms, loop)
    mp4_status = make_mp4(frame_files, mp4, duration_ms, ffmpeg)
    gif_preview = Image.open(gif)
    gif_has_transparency = gif_preview.info.get("transparency") is not None
    webp_preview = Image.open(webp)
    webp_has_alpha = "A" in webp_preview.getbands()
    if not gif_has_transparency or not webp_has_alpha:
        raise ValueError(
            f"{sequence['id']}/{clip['id']} animation preview lost transparency"
        )

    runtime_clip = {
        "id": clip["id"],
        "kind": clip["kind"],
        "frameDurationMilliseconds": duration_ms,
        "weight": float(clip.get("weight", 1)),
        "frames": resource_names,
    }
    report = {
        "id": clip["id"],
        "kind": clip["kind"],
        "source": str(source),
        "sourceSize": {"width": sheet.width, "height": sheet.height},
        "outputFrameSize": {"width": output_size[0], "height": output_size[1]},
        "effectiveRegistrationScale": (
            {"x": registration_scale[0], "y": registration_scale[1]}
            if registration_scale is not None
            else None
        ),
        "frames": [report.__dict__ for report in frame_reports],
        "contactSheet": str(contact_sheet),
        "gif": str(gif),
        "gifHasTransparency": gif_has_transparency,
        "animatedWebP": str(webp),
        "animatedWebPHasAlpha": webp_has_alpha,
        "mp4": str(mp4) if mp4_status == "created" else None,
        "mp4Status": mp4_status,
        "ok": True,
    }
    report["_frameImages"] = frame_images
    report["_frameFiles"] = frame_files
    report["_durationMilliseconds"] = duration_ms
    return runtime_clip, report


def build_sequence(
    manifest_path: Path,
    sequence: dict[str, Any],
    grid: Grid,
    output_dir: Path,
    resource_dir: Path,
    output_size: tuple[int, int],
    padding: int,
    ffmpeg: str | None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    runtime_clips: list[dict[str, Any]] = []
    clip_reports: list[dict[str, Any]] = []
    clip_images: dict[str, list[Image.Image]] = {}
    clip_durations: dict[str, int] = {}
    base_registration_scale = (
        float(sequence["registrationScale"])
        if sequence.get("registrationScale") is not None
        else None
    )
    clip_registration_scales: dict[str, tuple[float, float] | None] = {
        clip["id"]: (
            (base_registration_scale, base_registration_scale)
            if base_registration_scale is not None
            else None
        )
        for clip in sequence["clips"]
    }
    if (
        sequence["playbackMode"] == "randomLoop"
        and base_registration_scale is not None
    ):
        base_clip = next(
            clip
            for clip in sequence["clips"]
            if clip["id"] == sequence["baseClipID"]
        )
        base_width, base_height = boundary_size(
            load_clip_cells(manifest_path, base_clip, grid)
        )
        for clip in sequence["clips"]:
            clip_width, clip_height = boundary_size(
                load_clip_cells(manifest_path, clip, grid)
            )
            clip_registration_scales[clip["id"]] = (
                base_registration_scale * base_width / clip_width,
                base_registration_scale * base_height / clip_height,
            )

    for clip in sequence["clips"]:
        runtime_clip, report = build_clip(
            manifest_path=manifest_path,
            sequence=sequence,
            clip=clip,
            grid=grid,
            output_dir=output_dir,
            resource_dir=resource_dir,
            output_size=output_size,
            padding=padding,
            ffmpeg=ffmpeg,
            registration_scale=clip_registration_scales[clip["id"]],
        )
        runtime_clips.append(runtime_clip)
        clip_images[clip["id"]] = report.pop("_frameImages")
        report.pop("_frameFiles")
        clip_durations[clip["id"]] = report.pop("_durationMilliseconds")
        clip_reports.append(report)

    anchor_x_values = [
        frame["anchor_x"]
        for report in clip_reports
        for frame in report["frames"]
    ]
    anchor_y_values = [
        frame["anchor_y"]
        for report in clip_reports
        for frame in report["frames"]
    ]
    if max(anchor_x_values) - min(anchor_x_values) > 1:
        raise ValueError(f"{sequence['id']} has horizontal registration drift")
    if max(anchor_y_values) - min(anchor_y_values) > 1:
        raise ValueError(f"{sequence['id']} has vertical registration drift")

    sequence_output = output_dir / sequence["id"]
    if sequence["playbackMode"] == "oneShot":
        preview_clip_ids = [clip["id"] for clip in sequence["clips"]]
        preview_loops = False
    else:
        base_clip_id = sequence["baseClipID"]
        action_clip_ids = [
            clip["id"] for clip in sequence["clips"] if clip["kind"] == "action"
        ]
        preview_clip_ids = [base_clip_id]
        for action_clip_id in action_clip_ids:
            preview_clip_ids.extend([action_clip_id, base_clip_id])
        preview_loops = True

    preview_frames: list[Image.Image] = []
    preview_durations: list[int] = []
    for clip_id in preview_clip_ids:
        images = clip_images[clip_id]
        preview_frames.extend(images)
        preview_durations.extend([clip_durations[clip_id]] * len(images))

    contact_sheet = sequence_output / "contact-sheet.png"
    gif = sequence_output / f"{sequence['id']}.gif"
    webp = sequence_output / f"{sequence['id']}.webp"
    mp4 = sequence_output / f"{sequence['id']}.mp4"
    make_contact_sheet(preview_frames, sequence["id"], contact_sheet)
    make_gif(preview_frames, gif, preview_durations, preview_loops)
    make_animated_webp(preview_frames, webp, preview_durations, preview_loops)

    preview_frames_dir = sequence_output / "preview-frames"
    preview_frames_dir.mkdir(parents=True, exist_ok=True)
    preview_frame_files: list[Path] = []
    for index, frame in enumerate(preview_frames):
        path = preview_frames_dir / f"frame-{index:02d}.png"
        frame.save(path, optimize=True)
        preview_frame_files.append(path)
    mp4_status = make_mp4(
        preview_frame_files,
        mp4,
        preview_durations,
        ffmpeg,
    )

    runtime_sequence = {
        "id": sequence["id"],
        "displayName": sequence["displayName"],
        "playbackMode": sequence["playbackMode"],
        "baseClipID": sequence.get("baseClipID"),
        "actionProbability": float(sequence.get("actionProbability", 0)),
        "minimumBaseLoops": int(sequence.get("minimumBaseLoops", 0)),
        "reduceMotionClipID": sequence["reduceMotionClipID"],
        "reduceMotionFrameIndex": int(sequence["reduceMotionFrameIndex"]),
        "clips": runtime_clips,
    }
    sequence_report = {
        "id": sequence["id"],
        "playbackMode": sequence["playbackMode"],
        "registrationScale": sequence.get("registrationScale"),
        "registrationAnchorRange": {
            "x": {"min": min(anchor_x_values), "max": max(anchor_x_values)},
            "y": {"min": min(anchor_y_values), "max": max(anchor_y_values)},
        },
        "totalSourceFrames": sum(
            int(clip["frameCount"]) for clip in sequence["clips"]
        ),
        "previewFrameCount": len(preview_frames),
        "contactSheet": str(contact_sheet),
        "gif": str(gif),
        "animatedWebP": str(webp),
        "mp4": str(mp4) if mp4_status == "created" else None,
        "mp4Status": mp4_status,
        "clips": clip_reports,
        "ok": all(report["ok"] for report in clip_reports),
    }
    return runtime_sequence, sequence_report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--resource-dir", type=Path, required=True)
    parser.add_argument("--frame-size", type=parse_size, default=(384, 384))
    parser.add_argument("--padding", type=int, default=12)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument(
        "--sequence",
        action="append",
        help="Build only the named sequence; repeat to select more than one.",
    )
    args = parser.parse_args()

    manifest_path = args.manifest.resolve()
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    grid = Grid(
        columns=int(payload["grid"]["columns"]),
        rows=int(payload["grid"]["rows"]),
    )
    output_dir = args.output_dir.resolve()
    resource_dir = args.resource_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    resource_dir.mkdir(parents=True, exist_ok=True)

    runtime_sequences: list[dict[str, Any]] = []
    reports: list[dict[str, Any]] = []
    requested_sequences = set(args.sequence or [])
    selected_sequences = [
        sequence
        for sequence in payload["sequences"]
        if not requested_sequences or sequence["id"] in requested_sequences
    ]
    missing_sequences = requested_sequences.difference(
        sequence["id"] for sequence in selected_sequences
    )
    if missing_sequences:
        raise ValueError(f"unknown sequence ids: {sorted(missing_sequences)}")

    for sequence in selected_sequences:
        runtime_sequence, report = build_sequence(
            manifest_path=manifest_path,
            sequence=sequence,
            grid=grid,
            output_dir=output_dir,
            resource_dir=resource_dir,
            output_size=args.frame_size,
            padding=max(args.padding, 0),
            ffmpeg=args.ffmpeg,
        )
        runtime_sequences.append(runtime_sequence)
        reports.append(report)

    runtime_manifest = {
        "version": int(payload["version"]),
        "frameSize": {
            "width": args.frame_size[0],
            "height": args.frame_size[1],
        },
        "sequences": runtime_sequences,
    }
    runtime_manifest_path = resource_dir / "fumira_doraemon_sequences.json"
    runtime_manifest_path.write_text(
        json.dumps(runtime_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    report_path = output_dir / "build-report.json"
    report_path.write_text(
        json.dumps(
            {
                "ok": all(report["ok"] for report in reports),
                "manifest": str(runtime_manifest_path),
                "sequences": reports,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"ok": True, "report": str(report_path)}, ensure_ascii=False))


if __name__ == "__main__":
    main()

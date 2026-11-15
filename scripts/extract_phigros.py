#!/usr/bin/env python3
"""Extract Phigros songs, covers, charts, and hit sounds into an Aetheria package.

Reads a Phigros Android APK + OBB files (either local paths or pulled via ADB)
and writes:
  <out>/se/{tap,drag,flick}.wav
  <out>/audio/<safe_id>[_DIFF].flac
  <out>/covers/<safe_id>[_DIFF].jpg
  <out>/charts/<safe_id>_<DIFF>.json
  <out>/phigros_manifest.json
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
import threading
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

import UnityPy

CHAPTER_ORDER = [
    "Tutorial",
    "MainStoryLegacy",
    "MainStory5",
    "MainStory6",
    "MainStory7",
    "MainStory8",
    "MainStory9",
    "SideStory1",
    "SideStory2",
    "SideStory3",
    "SideStory4",
    "Single",
]

CHAPTER_LABELS = {
    "Tutorial": "序章 · 新手教程",
    "MainStoryLegacy": "过去的章节 (Legacy)",
    "MainStory5": "第五章 · 霓虹灯牌",
    "MainStory6": "第六章 · 方舟蜃景",
    "MainStory7": "第七章 · 时钟链接",
    "MainStory8": "第八章 · 凌日潮汐",
    "MainStory9": "第九章 · 第九章",
    "SideStory1": "支线一 · 忘忧宫",
    "SideStory2": "支线二 · 弥留",
    "SideStory3": "支线三 · 盗乐行",
    "SideStory4": "支线四 · 无相乡",
    "Single": "单曲精选集",
    "Cytus2": "Cytus II 联动",
    "Liminality": "Liminality 联动",
    "Maimai": "maimai DX 联动",
    "Ongeki": "オンゲキ 联动",
    "ImmaculeeSekai": "Immaculée Sekai 联动",
    "EGTS": "EGTS 精选",
    "RhythmMaster": "节奏大师 联动",
    "TAKUMI3": "TAKUMI³ 联动",
    "SHINOBISLASH": "SHINOBI SLASH 联动",
    "ParadigmReboot": "Paradigm: Reboot 联动",
    "CHUNITHM": "CHUNITHM 联动",
    "Rotaeno": "Rotaeno 联动",
    "Camellia": "かめりあ 精选",
    "OverRapid": "OverRapid 联动",
    "TEA12": "茶鸣拾贰律 精选",
    "JMT": "姜米條 精选",
    "Lanota": "Lanota 联动",
    "KALPA": "KALPA 联动",
    "MUSEDASH": "Muse Dash 联动",
    "WAVEAT": "WAVEAT 联动",
    "Good": "GOOD 精选",
    "HyuN": "HyuN 精选",
    "RST": "Rising Sun Traxx 精选",
}

DIFF_RANK = {
    "EZ": 0,
    "HD": 1,
    "IN": 2,
    "AT": 3,
    "SP": 4,
    "Legacy": 5,
    "EZ_Error": 6,
    "HD_Error": 7,
    "IN_Error": 8,
}

# Verified against SEPlayer & HitSong spectral profiles from Phigros APK:
# HitSong0 (98ms percussive snap) -> Tap / Hold head
# HitSong2 (390ms crystal bell)   -> Drag
# HitSong1 (445ms >6kHz swipe)    -> Flick
SE_MAPPING = {
    "tap": "TrackFile/SE/HitSong0",
    "drag": "TrackFile/SE/HitSong2",
    "flick": "TrackFile/SE/HitSong1",
}


def safe_id(raw: str) -> str:
    cleaned = "".join(c if (c.isascii() and (c.isalnum() or c in "_-.")) else "_" for c in raw)
    if cleaned == raw:
        return cleaned
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:8]
    return f"{cleaned}_{digest}"


def read_key(buf: bytes, offset: int) -> str | int | None:
    kind = buf[offset]
    offset += 1
    if kind == 0:
        length = struct.unpack_from("<I", buf, offset)[0]
        offset += 4
        return buf[offset : offset + length].decode("ascii", errors="replace")
    if kind == 1:
        length = struct.unpack_from("<I", buf, offset)[0]
        offset += 4
        return buf[offset : offset + length].decode("utf-16le", errors="replace")
    if kind == 4:
        return struct.unpack_from("<i", buf, offset)[0]
    return None


def parse_addressables_catalog(apk_zip: zipfile.ZipFile) -> dict[str, str]:
    cat = json.loads(apk_zip.read("assets/aa/catalog.json"))
    key_data = base64.b64decode(cat["m_KeyDataString"])
    bucket_data = base64.b64decode(cat["m_BucketDataString"])
    entry_data = base64.b64decode(cat["m_EntryDataString"])
    internal_ids = cat["m_InternalIds"]

    entry_count = struct.unpack_from("<I", entry_data, 0)[0]
    entries = [struct.unpack_from("<7i", entry_data, 4 + i * 28) for i in range(entry_count)]

    pos = 4
    bucket_count = struct.unpack_from("<I", bucket_data, 0)[0]
    key_to_bundle: dict[str, str] = {}
    for _ in range(bucket_count):
        k_off, n_entries = struct.unpack_from("<II", bucket_data, pos)
        pos += 8
        e_indices = struct.unpack_from(f"<{n_entries}i", bucket_data, pos)
        pos += 4 * n_entries
        key = read_key(key_data, k_off)
        if isinstance(key, str):
            for ei in e_indices:
                if 0 <= ei < entry_count:
                    dep_idx = entries[ei][2]
                    if 0 <= dep_idx < entry_count:
                        bid = entries[dep_idx][0]
                        if 0 <= bid < len(internal_ids) and internal_ids[bid].endswith(".bundle"):
                            key_to_bundle[key] = internal_ids[bid].split("/")[-1]
    return key_to_bundle


def rstr(buf: bytes, off: int) -> tuple[str, int]:
    n = struct.unpack_from("<i", buf, off)[0]
    if n < 0 or n > 4096 or off + 4 + n > len(buf):
        raise ValueError(f"Invalid Unity string len {n} at {off}")
    return buf[off + 4 : off + 4 + n].decode("utf-8"), off + 4 + ((n + 3) // 4) * 4


def try_parse_song_item(buf: bytes, off: int) -> dict[str, Any]:
    sid, p = rstr(buf, off)
    sname, p = rstr(buf, p)
    _skey, p = rstr(buf, p)
    n0 = struct.unpack_from("<i", buf, p)[0]
    p += 4
    if not (0 <= n0 <= 6):
        raise ValueError("bad n0")
    p += 4 * n0
    nd = struct.unpack_from("<i", buf, p)[0]
    p += 4
    if not (1 <= nd <= 6):
        raise ValueError("bad nd")
    diffs = [round(float(x), 1) for x in struct.unpack_from(f"<{nd}f", buf, p)]
    p += 4 * nd
    illus, p = rstr(buf, p)
    nc = struct.unpack_from("<i", buf, p)[0]
    p += 4
    if not (0 <= nc <= 6):
        raise ValueError("bad nc")
    charters = []
    for _ in range(nc):
        c, p = rstr(buf, p)
        charters.append(c)
    comp, p = rstr(buf, p)
    nl = struct.unpack_from("<i", buf, p)[0]
    p += 4
    if not (1 <= nl <= 6):
        raise ValueError("bad nl")
    levels = []
    for _ in range(nl):
        lv, p = rstr(buf, p)
        levels.append(lv)
    return {
        "id": sid,
        "name": sname,
        "difficulties": diffs,
        "illustrator": illus,
        "charters": charters,
        "composer": comp,
        "levels": levels,
    }


def parse_game_information(apk_zip: zipfile.ZipFile, tmp_dir: Path, track_ids: set[str]) -> tuple[dict[str, dict[str, Any]], dict[str, str], list[str]]:
    bin_dir = tmp_dir / "bin_data"
    bin_dir.mkdir(parents=True, exist_ok=True)
    for name in apk_zip.namelist():
        if name.startswith("assets/bin/Data/"):
            rel = name[len("assets/bin/Data/") :]
            if "/" not in rel and rel:
                (bin_dir / rel).write_bytes(apk_zip.read(name))

    env = UnityPy.load(str(bin_dir))
    raw: bytes | None = None
    for obj in env.objects:
        if getattr(obj.assets_file, "name", "") == "level0" and obj.path_id == 50:
            raw = obj.get_raw_data()
            break
    if raw is None:
        raise RuntimeError("Could not locate GameInformation in level0")

    song_chapter: dict[str, str] = {}
    ordered_song_ids: list[str] = []
    for m in re.finditer(rb"(?:\\)?Chapter[A-Za-z0-9_]+Title", raw):
        tpos = m.start() - 4
        cid = None
        for back in range(8, 80, 4):
            cand = tpos - back
            if cand >= 0:
                try:
                    s, nxt = rstr(raw, cand)
                    if nxt == tpos and re.match(r"^[A-Za-z0-9_]+$", s):
                        cid = s
                        break
                except Exception:
                    pass
        if not cid:
            continue
        pos = tpos
        for _ in range(3):
            _, pos = rstr(raw, pos)
        ns = struct.unpack_from("<i", raw, pos)[0]
        pos += 4
        for _ in range(ns):
            sid, pos = rstr(raw, pos)
            _f = struct.unpack_from("<i", raw, pos)[0]
            pos += 4
            nk = struct.unpack_from("<i", raw, pos)[0]
            pos += 4
            for _ in range(nk):
                _, pos = rstr(raw, pos)
            pos += 8
            song_chapter.setdefault(sid, cid)
            if sid not in ordered_song_ids:
                ordered_song_ids.append(sid)

    song_meta: dict[str, dict[str, Any]] = {}
    for tid in sorted(track_ids):
        needle = struct.pack("<i", len(tid.encode("utf-8"))) + tid.encode("utf-8")
        idx = 0
        while True:
            pos = raw.find(needle, idx)
            if pos == -1:
                break
            try:
                item = try_parse_song_item(raw, pos)
                if item["levels"] and all(
                    x in ("EZ", "HD", "IN", "AT", "SP", "Legacy") for x in item["levels"]
                ):
                    song_meta[tid] = item
                    break
            except Exception:
                pass
            idx = pos + 4

    return song_meta, song_chapter, ordered_song_ids


def parse_chart_to_timeline(raw_bytes: bytes) -> dict[str, Any]:
    data = json.loads(raw_bytes)
    offset = float(data.get("offset", 0.0))
    lines = data.get("judgeLineList", [])
    bpms = [float(l.get("bpm", 0.0)) for l in lines if float(l.get("bpm", 0.0)) > 0]
    bpm_min = min(bpms) if bpms else 120.0
    bpm_max = max(bpms) if bpms else 120.0

    notes: list[list[Any]] = []
    counts = {1: 0, 2: 0, 3: 0, 4: 0}
    for line in lines:
        bpm = float(line.get("bpm", 0.0))
        if bpm <= 0:
            continue
        unit_secs = 1.875 / bpm
        for note in line.get("notesAbove", []) + line.get("notesBelow", []):
            ntype = int(note.get("type", 0))
            if ntype not in counts:
                continue
            t = max(0.0, float(note.get("time", 0.0)) * unit_secs + offset)
            counts[ntype] += 1
            notes.append([round(t, 6), ntype])

    notes.sort(key=lambda pair: (pair[0], pair[1]))
    return {
        "notes": notes,
        "bpm_min": round(bpm_min, 3),
        "bpm_max": round(bpm_max, 3),
        "chart_offset_ms": int(round(offset * 1000.0)),
        "note_count": len(notes),
        "tap_count": counts[1],
        "drag_count": counts[2],
        "hold_count": counts[3],
        "flick_count": counts[4],
    }


def wav_bytes_to_flac(wav_bytes: bytes, dest_flac: Path) -> None:
    dest_flac.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-f",
            "wav",
            "-i",
            "pipe:0",
            "-c:a",
            "flac",
            "-compression_level",
            "5",
            str(dest_flac),
        ],
        input=wav_bytes,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg failed for {dest_flac.name}: {proc.stderr.decode(errors='replace')}")


def pull_from_adb(adb_path: str, dest_dir: Path) -> tuple[Path, Path | None, Path | None]:
    dest_dir.mkdir(parents=True, exist_ok=True)
    apk_out = dest_dir / "base.apk"
    pm = subprocess.run(
        [adb_path, "shell", "pm", "path", "com.PigeonGames.Phigros"],
        capture_output=True,
        text=True,
        check=True,
    )
    apk_remote = None
    for line in pm.stdout.splitlines():
        if line.startswith("package:") and line.strip().endswith("base.apk"):
            apk_remote = line.split(":", 1)[1].strip()
            break
    if not apk_remote:
        raise RuntimeError("Phigros is not installed on connected ADB device")
    subprocess.run([adb_path, "pull", apk_remote, str(apk_out)], check=True)

    obb_ls = subprocess.run(
        [adb_path, "shell", "ls", "/sdcard/Android/obb/com.PigeonGames.Phigros"],
        capture_output=True,
        text=True,
        check=False,
    )
    main_out: Path | None = None
    patch_out: Path | None = None
    for fname in obb_ls.stdout.split():
        fname = fname.strip()
        if fname.startswith("main.") and fname.endswith(".obb"):
            main_out = dest_dir / "main.obb"
            subprocess.run(
                [adb_path, "pull", f"/sdcard/Android/obb/com.PigeonGames.Phigros/{fname}", str(main_out)],
                check=True,
            )
        elif fname.startswith("patch.") and fname.endswith(".obb"):
            patch_out = dest_dir / "patch.obb"
            subprocess.run(
                [adb_path, "pull", f"/sdcard/Android/obb/com.PigeonGames.Phigros/{fname}", str(patch_out)],
                check=True,
            )
    return apk_out, main_out, patch_out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--main-obb", type=Path)
    parser.add_argument("--patch-obb", type=Path)
    parser.add_argument("--from-adb", action="store_true")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=max(4, min(8, os.cpu_count() or 4)))
    args = parser.parse_args()

    out_dir: Path = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="phigros_extract_") as tmp:
        tmp_dir = Path(tmp)
        if args.from_adb:
            apk_path, main_obb, patch_obb = pull_from_adb(args.adb, tmp_dir / "pulled")
        else:
            if not args.apk:
                parser.error("Provide --apk (and optional --main-obb/--patch-obb) or --from-adb")
            apk_path, main_obb, patch_obb = args.apk, args.main_obb, args.patch_obb

        archive_paths = [p for p in [patch_obb, main_obb, apk_path] if p and p.is_file()]
        opened_zips = [zipfile.ZipFile(p, "r") for p in archive_paths]
        try:
            bundle_loc: dict[str, tuple[zipfile.ZipFile, str]] = {}
            for z in opened_zips:
                for n in z.namelist():
                    if n.endswith(".bundle"):
                        bn = n.rsplit("/", 1)[-1]
                        if bn not in bundle_loc:
                            bundle_loc[bn] = (z, n)

            apk_zip = opened_zips[-1]
            key_to_bundle = parse_addressables_catalog(apk_zip)
            zip_lock = threading.Lock()

            def load_bundle_bytes(asset_key: str) -> bytes | None:
                bn = key_to_bundle.get(asset_key)
                if not bn or bn not in bundle_loc:
                    return None
                z, internal_path = bundle_loc[bn]
                with zip_lock:
                    return z.read(internal_path)

            # 1. Extract official hit sounds
            se_dir = out_dir / "se"
            se_dir.mkdir(parents=True, exist_ok=True)
            se_rel_map: dict[str, str] = {}
            for kind, key in SE_MAPPING.items():
                raw_bundle = load_bundle_bytes(key)
                if not raw_bundle:
                    continue
                env = UnityPy.load(raw_bundle)
                for obj in env.objects:
                    if obj.type.name == "AudioClip":
                        clip = obj.read()
                        wav_data = next(iter(clip.samples.values()))
                        target = se_dir / f"{kind}.wav"
                        target.write_bytes(wav_data)
                        se_rel_map[kind] = f"se/{kind}.wav"
                        break

            # 2. Index track folders & parse GameInformation metadata
            track_keys: dict[str, dict[str, str]] = {}
            for k in key_to_bundle:
                if k.startswith("Assets/Tracks/"):
                    parts = k.split("/")
                    if len(parts) == 4:
                        tid, fn = parts[2], parts[3]
                        track_keys.setdefault(tid, {})[fn] = k

            playable_tracks = {tid for tid, files in track_keys.items() if "music.wav" in files}
            song_meta, song_chapter, ordered_song_ids = parse_game_information(
                apk_zip, tmp_dir, playable_tracks
            )

            # Order tracks: known chapter songs first, then tutorial & extra branches.
            ordered_tids: list[str] = [tid for tid in ordered_song_ids if tid in playable_tracks]
            for tid in sorted(playable_tracks):
                if tid not in ordered_tids:
                    ordered_tids.append(tid)

            def process_track(tid: str) -> dict[str, Any] | None:
                files = track_keys[tid]
                base_tid = "Random.SobremSilentroom.0" if tid.startswith("Random.SobremSilentroom.") else tid
                meta = song_meta.get(tid) or song_meta.get(base_tid) or {}
                cid = song_chapter.get(tid) or song_chapter.get(base_tid) or (
                    "Tutorial" if tid == "Introduction" else "Single"
                )
                chapter_label = CHAPTER_LABELS.get(cid, cid)

                title = meta.get("name") or tid.split(".")[0]
                if tid != base_tid and tid.startswith("Random.SobremSilentroom."):
                    suffix = tid.rsplit(".", 1)[-1]
                    title = f"{title} (分支 {suffix})"
                composer = meta.get("composer") or "Pigeon Games"
                illustrator = meta.get("illustrator") or ""

                sid_safe = safe_id(tid)
                audio_rel = f"audio/{sid_safe}.flac"
                audio_out = out_dir / audio_rel

                duration_sec = 0.0
                sample_rate = 44100
                raw_music_bundle = load_bundle_bytes(files["music.wav"])
                if not raw_music_bundle:
                    return None
                env = UnityPy.load(raw_music_bundle)
                wrote_audio = False
                for obj in env.objects:
                    if obj.type.name == "AudioClip":
                        clip = obj.read()
                        duration_sec = float(getattr(clip, "m_Length", 0.0) or 0.0)
                        sample_rate = int(getattr(clip, "m_Frequency", 44100) or 44100)
                        if not audio_out.is_file():
                            wav_data = next(iter(clip.samples.values()))
                            wav_bytes_to_flac(wav_data, audio_out)
                        wrote_audio = True
                        break
                if not wrote_audio:
                    return None

                # Main cover illustration (fallback to Random.0 cover for Random branches).
                cover_rel: str | None = None
                illus_key = files.get("Illustration.jpg") or track_keys.get(base_tid, {}).get("Illustration.jpg")
                if illus_key:
                    raw_img_bundle = load_bundle_bytes(illus_key)
                    if raw_img_bundle:
                        env_img = UnityPy.load(raw_img_bundle)
                        for obj in env_img.objects:
                            if obj.type.name == "Texture2D":
                                tex = obj.read()
                                img = tex.image
                                if img.mode not in ("RGB", "L"):
                                    img = img.convert("RGB")
                                cover_rel = f"covers/{sid_safe}.jpg"
                                cover_out = out_dir / cover_rel
                                cover_out.parent.mkdir(parents=True, exist_ok=True)
                                if not cover_out.is_file():
                                    img.save(cover_out, format="JPEG", quality=92)
                                break

                levels_meta = meta.get("levels", [])
                diffs_meta = meta.get("difficulties", [])
                charters_meta = meta.get("charters", [])

                charts: list[dict[str, Any]] = []
                for fn, asset_key in sorted(files.items()):
                    if not (fn.startswith("Chart_") and fn.endswith(".json")):
                        continue
                    diff = fn[len("Chart_") : -len(".json")]
                    raw_chart_bundle = load_bundle_bytes(asset_key)
                    if not raw_chart_bundle:
                        continue
                    timeline = None
                    env_chart = UnityPy.load(raw_chart_bundle)
                    for obj in env_chart.objects:
                        if obj.type.name == "TextAsset":
                            ta = obj.read()
                            script_bytes = (
                                ta.m_Script.encode("utf-8", "surrogateescape")
                                if isinstance(ta.m_Script, str)
                                else ta.m_Script
                            )
                            timeline = parse_chart_to_timeline(script_bytes)
                            break
                    if not timeline:
                        continue

                    chart_rel = f"charts/{sid_safe}_{safe_id(diff)}.json"
                    chart_out = out_dir / chart_rel
                    chart_out.parent.mkdir(parents=True, exist_ok=True)
                    chart_out.write_text(
                        json.dumps({"notes": timeline["notes"]}, separators=(",", ":")),
                        encoding="utf-8",
                    )

                    rating = 0.0
                    charter = ""
                    base_diff = diff.replace("_Error", "")
                    if base_diff in levels_meta:
                        lidx = levels_meta.index(base_diff)
                        if lidx < len(diffs_meta):
                            rating = float(diffs_meta[lidx])
                        if lidx < len(charters_meta):
                            charter = str(charters_meta[lidx])

                    # Optional difficulty-specific audio (`music_IN.wav`) or illustration (`Illustration_IN.jpg`).
                    diff_audio_rel = None
                    diff_music_key = files.get(f"music_{diff}.wav")
                    if diff_music_key:
                        raw_dm = load_bundle_bytes(diff_music_key)
                        if raw_dm:
                            env_dm = UnityPy.load(raw_dm)
                            for obj in env_dm.objects:
                                if obj.type.name == "AudioClip":
                                    clip = obj.read()
                                    diff_audio_rel = f"audio/{sid_safe}_{safe_id(diff)}.flac"
                                    d_out = out_dir / diff_audio_rel
                                    if not d_out.is_file():
                                        wav_bytes_to_flac(next(iter(clip.samples.values())), d_out)
                                    break

                    diff_cover_rel = None
                    diff_img_key = files.get(f"Illustration_{diff}.jpg")
                    if diff_img_key:
                        raw_di = load_bundle_bytes(diff_img_key)
                        if raw_di:
                            env_di = UnityPy.load(raw_di)
                            for obj in env_di.objects:
                                if obj.type.name == "Texture2D":
                                    img = obj.read().image
                                    if img.mode not in ("RGB", "L"):
                                        img = img.convert("RGB")
                                    diff_cover_rel = f"covers/{sid_safe}_{safe_id(diff)}.jpg"
                                    d_img_out = out_dir / diff_cover_rel
                                    d_img_out.parent.mkdir(parents=True, exist_ok=True)
                                    if not d_img_out.is_file():
                                        img.save(d_img_out, format="JPEG", quality=92)
                                    break

                    charts.append(
                        {
                            "difficulty": diff,
                            "sort_rank": DIFF_RANK.get(diff, 99),
                            "rating": rating,
                            "charter": charter,
                            "bpm_min": timeline["bpm_min"],
                            "bpm_max": timeline["bpm_max"],
                            "chart_offset_ms": timeline["chart_offset_ms"],
                            "note_count": timeline["note_count"],
                            "tap_count": timeline["tap_count"],
                            "drag_count": timeline["drag_count"],
                            "hold_count": timeline["hold_count"],
                            "flick_count": timeline["flick_count"],
                            "chart_file": chart_rel,
                            "audio_file": diff_audio_rel,
                            "cover_file": diff_cover_rel,
                        }
                    )

                if not charts:
                    return None
                charts.sort(key=lambda c: (c["sort_rank"], c["difficulty"]))
                default_diff = next(
                    (d for d in ("IN", "AT", "HD", "EZ", "SP", "Legacy") if any(c["difficulty"] == d for c in charts)),
                    charts[0]["difficulty"],
                )
                return {
                    "phigros_id": tid,
                    "title": title,
                    "composer": composer,
                    "illustrator": illustrator,
                    "chapter": chapter_label,
                    "audio_file": audio_rel,
                    "cover_file": cover_rel,
                    "default_difficulty": default_diff,
                    "duration": round(duration_sec, 3),
                    "sample_rate": sample_rate,
                    "charts": charts,
                }

            results_by_tid: dict[str, dict[str, Any]] = {}
            with ThreadPoolExecutor(max_workers=args.workers) as pool:
                futs = {pool.submit(process_track, tid): tid for tid in ordered_tids}
                done = 0
                for fut in as_completed(futs):
                    tid = futs[fut]
                    done += 1
                    item = fut.result()
                    if item is not None:
                        results_by_tid[tid] = item
                    if done % 40 == 0 or done == len(ordered_tids):
                        print(f"Processed {done}/{len(ordered_tids)} tracks...", flush=True)

            manifest_songs = [results_by_tid[tid] for tid in ordered_tids if tid in results_by_tid]
            manifest = {"se": se_rel_map, "songs": manifest_songs}
            (out_dir / "phigros_manifest.json").write_text(
                json.dumps(manifest, ensure_ascii=False), encoding="utf-8"
            )
            print(
                f"Done: {len(manifest_songs)} songs, "
                f"{sum(len(s['charts']) for s in manifest_songs)} charts -> {out_dir}"
            )
        finally:
            for z in opened_zips:
                z.close()


if __name__ == "__main__":
    main()

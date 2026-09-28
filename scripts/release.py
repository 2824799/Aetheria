#!/usr/bin/env python3
"""Pin the release source and publish only a complete, verified asset set."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def run(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True).strip()


def api(endpoint: str, *arguments: str):
    return json.loads(run("gh", "api", endpoint, *arguments))


def normalize_version(raw: str) -> str:
    version = raw.strip().removeprefix("v")
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("Use a release version such as 0.0.1 or v0.0.1.")
    if any(len(part) > 5 or int(part) > 65535 for part in version.split(".")):
        raise ValueError("Windows version components must be between 0 and 65535.")
    return version


def release_state(repository: str, tag: str, source_sha: str):
    pages = api(f"repos/{repository}/releases", "--paginate", "--slurp")
    releases = [release for page in pages for release in page]
    existing = next((release for release in releases if release["tag_name"] == tag), None)
    if existing:
        if not existing["draft"]:
            raise ValueError(f"{tag} is already published; use a new version number.")
        if existing["target_commitish"] != source_sha:
            raise ValueError(f"The existing {tag} draft belongs to another source commit.")

    refs = run("git", "ls-remote", "--tags", "origin", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}")
    targets = dict((ref, sha) for sha, ref in (line.split() for line in refs.splitlines()))
    target = targets.get(f"refs/tags/{tag}^{{}}", targets.get(f"refs/tags/{tag}"))
    if target and target != source_sha:
        raise ValueError(f"The existing {tag} tag points to another source commit.")
    return existing


def prepare(raw_version: str) -> None:
    version = normalize_version(raw_version)
    build_number = int(os.environ["GITHUB_RUN_NUMBER"])
    if not 1 <= build_number <= 65535:
        raise ValueError("The automatic build number must fit the Windows version field (1–65535).")
    missing = [
        name for name in (
            "ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD",
            "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD",
        ) if not os.environ.get(name)
    ]
    if missing:
        raise ValueError("Missing Android signing secrets: " + ", ".join(missing))

    repository = os.environ["GITHUB_REPOSITORY"]
    source_sha = run("git", "rev-parse", "HEAD")
    tag = f"v{version}"
    release_state(repository, tag, source_sha)
    metadata = {
        "version": version,
        "tag": tag,
        "build_number": build_number,
        "source_sha": source_sha,
        "repository": repository,
        "flutter_version": os.environ["FLUTTER_VERSION"],
        "workflow_run": f"https://github.com/{repository}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    Path("dist").mkdir(exist_ok=True)
    Path("dist/BUILD-INFO.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key in ("version", "tag", "build_number", "source_sha"):
            output.write(f"{key}={metadata[key]}\n")
    print(f"Prepared {tag}: source={source_sha}, build={build_number}")


def checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def publish(directory: Path) -> None:
    metadata = json.loads((directory / "BUILD-INFO.json").read_text())
    version = normalize_version(metadata["version"])
    tag = f"v{version}"
    repository = os.environ["GITHUB_REPOSITORY"]
    source_sha = run("git", "rev-parse", "HEAD")
    if metadata["source_sha"] != source_sha or metadata["repository"] != repository or metadata["tag"] != tag:
        raise ValueError("The downloaded release metadata does not match the pinned checkout.")

    names = {
        f"Aetheria-{tag}-linux-x64.tar.gz",
        f"Aetheria-{tag}-windows-x64.zip",
        f"Aetheria-{tag}-android-arm64.apk",
        f"Aetheria-{tag}-android.aab",
        "BUILD-INFO.json",
    }
    actual = {path.name for path in directory.iterdir() if path.name != "SHA256SUMS"}
    if actual != names:
        raise ValueError(f"Incomplete release assets: missing={sorted(names - actual)}, unexpected={sorted(actual - names)}")
    paths = [directory / name for name in sorted(names)]
    if any(not path.is_file() or path.stat().st_size == 0 for path in paths):
        raise ValueError("Every release asset must be a non-empty file.")
    sums = directory / "SHA256SUMS"
    sums.write_text("".join(f"{checksum(path)}  {path.name}\n" for path in paths))
    paths.append(sums)

    existing = release_state(repository, tag, source_sha)
    custom_notes = Path("docs/releases") / f"{tag}.md"
    if custom_notes.is_file():
        notes = custom_notes.read_text()
    else:
        notes = api(
            f"repos/{repository}/releases/generate-notes", "--method", "POST",
            "-f", f"tag_name={tag}", "-f", f"target_commitish={source_sha}",
        )["body"]
    notes += f"""

### 下载与安装

| 平台 | 文件 | 使用方式 |
| --- | --- | --- |
| Linux x64 | `Aetheria-{tag}-linux-x64.tar.gz` | 解压后运行 `./install.sh` 或 `./aetheria` |
| Windows x64 | `Aetheria-{tag}-windows-x64.zip` | 完整解压后运行 `aetheria.exe` |
| Android arm64 | `Aetheria-{tag}-android-arm64.apk` | 安装已正式签名的 APK；需要 Android 8.0 或更高版本 |
| Android 商店包 | `Aetheria-{tag}-android.aab` | 包含 ARM32、ARM64、x86_64，供商店分发 |

Linux 需要 glibc 2.35 或更高版本、GTK 3 与 ALSA。安装脚本默认使用 `~/.local/opt/aetheria`，并注册桌面启动器和图标。

完整性校验：下载 `SHA256SUMS` 后，在产物所在目录运行 `sha256sum -c SHA256SUMS`。

构建提交：[`{source_sha}`](https://github.com/{repository}/commit/{source_sha})
版本：`{version}+{metadata['build_number']}` · Flutter：`{metadata['flutter_version']}`
[构建记录]({metadata['workflow_run']}) · `BUILD-INFO.json` 提供来源和版本信息。
"""
    notes_path = Path("release-notes.md")
    notes_path.write_text(notes, encoding="utf-8")
    if existing:
        run("gh", "release", "edit", tag, "--repo", repository, "--title", f"Aetheria {tag}", "--notes-file", str(notes_path))
    else:
        run(
            "gh", "release", "create", tag, "--repo", repository,
            "--target", source_sha, "--draft", "--title", f"Aetheria {tag}",
            "--notes-file", str(notes_path),
        )
    run("gh", "release", "upload", tag, "--repo", repository, "--clobber", *(str(path) for path in paths))
    release = api(f"repos/{repository}/releases/tags/{tag}")
    assets = {asset["name"]: asset for asset in release["assets"]}
    if set(assets) != {path.name for path in paths}:
        raise ValueError("The draft release's uploaded assets do not match the complete asset set.")
    for path in paths:
        asset = assets[path.name]
        if asset["state"] != "uploaded" or asset["size"] != path.stat().st_size:
            raise ValueError(f"Upload verification failed: {path.name}")
        digest = asset.get("digest")
        if digest and digest != f"sha256:{checksum(path)}":
            raise ValueError(f"Uploaded SHA-256 mismatch: {path.name}")
    run("gh", "release", "edit", tag, "--repo", repository, "--draft=false", "--prerelease=false", "--latest")
    release = api(f"repos/{repository}/releases/tags/{tag}")
    if release["draft"] or release["prerelease"]:
        raise ValueError("GitHub did not publish the release as a final release.")
    release_state_after = run("git", "ls-remote", "--tags", "origin", f"refs/tags/{tag}")
    if not release_state_after or release_state_after.split()[0] != source_sha:
        raise ValueError("The published release tag does not match the pinned source commit.")
    print(f"Published {release['html_url']}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write(f"## [Aetheria {tag}]({release['html_url']})\n\nSource: `{source_sha}`\n\n")
            for path in paths:
                output.write(f"- `{path.name}` ({path.stat().st_size:,} bytes)\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_command = commands.add_parser("prepare")
    prepare_command.add_argument("version")
    publish_command = commands.add_parser("publish")
    publish_command.add_argument("--dist", type=Path, default=Path("dist"))
    arguments = parser.parse_args()
    try:
        if arguments.command == "prepare":
            prepare(arguments.version)
        else:
            publish(arguments.dist)
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()

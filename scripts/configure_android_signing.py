#!/usr/bin/env python3
"""Restore CI signing credentials without printing or committing secrets."""

import base64
import os
from pathlib import Path


def property_value(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
        .replace("=", "\\=")
        .replace(":", "\\:")
        .replace(" ", "\\ ")
    )


def main() -> None:
    names = (
        "ANDROID_KEYSTORE_BASE64",
        "ANDROID_KEYSTORE_PASSWORD",
        "ANDROID_KEY_ALIAS",
        "ANDROID_KEY_PASSWORD",
    )
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise SystemExit("Missing Android signing secrets: " + ", ".join(missing))

    os.umask(0o077)
    android = Path("android")
    keystore = android / "release.keystore"
    keystore.write_bytes(base64.b64decode(os.environ[names[0]], validate=True))
    keystore.chmod(0o600)
    properties = {
        "storeFile": "release.keystore",
        "storePassword": os.environ[names[1]],
        "keyAlias": os.environ[names[2]],
        "keyPassword": os.environ[names[3]],
    }
    properties_file = android / "key.properties"
    properties_file.write_text(
        "".join(f"{key}={property_value(value)}\n" for key, value in properties.items()),
        encoding="ascii",
    )
    properties_file.chmod(0o600)
    print("Android release signing credentials restored.")


if __name__ == "__main__":
    main()

"""Extract an App Pack and inventory its contents; does not decompile ArkTS."""

import argparse
from collections import Counter
import hashlib
from io import BytesIO
import json
from pathlib import Path, PurePosixPath
import re
import stat
from zipfile import BadZipFile, ZipFile


MAX_BYTES = 64 * 1024 * 1024


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_archive(data):
    """Validate all members before returning any files to the caller."""
    files = {}
    names = set()
    with ZipFile(BytesIO(data)) as archive:
        entries = archive.infolist()
        if sum(entry.file_size for entry in entries) > MAX_BYTES:
            raise ValueError("Archive exceeds the 64 MiB extraction limit")
        for entry in entries:
            name = entry.filename
            path = PurePosixPath(name)
            if (not name or path.is_absolute() or ".." in path.parts
                    or "\\" in name or ":" in name
                    or stat.S_ISLNK(entry.external_attr >> 16)):
                raise ValueError(f"Unsafe archive path: {name}")
            key = str(path).casefold()
            if key in names:
                raise ValueError(f"Duplicate archive path: {name}")
            names.add(key)
            if not entry.is_dir():
                files[str(path)] = archive.read(entry)  # Also verifies ZIP CRC.
    return files


def collect(input_path):
    data = input_path.read_bytes()
    app = read_archive(data)
    hap_names = sorted(name for name in app if name.endswith(".hap"))
    if hap_names != ["entry-default.hap"]:
        raise ValueError("Expected exactly one HAP named entry-default.hap")
    entry = read_archive(app[hap_names[0]])
    module = json.loads(entry["module.json"])
    pack = json.loads(app["pack.info"])
    routes = json.loads(entry["resources/base/profile/main_pages.json"])["src"]
    abc = entry["ets/modules.abc"]
    symbols = sorted({value.decode("ascii") for value in re.findall(
        rb"entry/src/main/ets/[A-Za-z0-9_/]+", abc)})
    tables = sorted({value.decode("ascii") for value in re.findall(
        rb"CREATE TABLE IF NOT EXISTS (ll_[a-z_]+)", abc)})
    indicators = [term for term in (
        "@ohos:data.relationalStore", "@ohos:data.preferences",
        "@ohos:security.cryptoFramework", "pinHash", "pin_salt",
        "SHA256", "generateRandom", "schemaVersion", "CSV_BOM",
    ) if term.encode("ascii") in abc]
    files = {f"app/{name}": value for name, value in app.items()
             if not name.endswith(".hap")}
    files.update({f"entry/{name}": value for name, value in entry.items()})
    inventory = {
        "format_version": 1,
        "scope": "package extraction and byte-string indicators; not source recovery",
        "input": {"name": input_path.name, "size": len(data), "sha256": digest(data)},
        "hap": {"name": hap_names[0], "size": len(app[hap_names[0]]),
                "sha256": digest(app[hap_names[0]])},
        "application": {
            "bundle_name": module["app"]["bundleName"],
            "version": module["app"]["versionName"],
            "build_mode": module["app"]["buildMode"],
            "compile_sdk_version": module["app"]["compileSdkVersion"],
            "api_version": pack["summary"]["modules"][0]["apiVersion"],
            "device_types": module["module"]["deviceTypes"],
            "requested_permissions": module["module"].get("requestPermissions", []),
        },
        "routes": routes,
        "bytecode_indicators": {
            "module_paths": symbols,
            "module_counts_by_directory": dict(sorted(Counter(
                path.split("/")[4] for path in symbols).items())),
            "table_names": tables,
            "strings_present": indicators,
            "warning": "Names and strings do not prove runtime behavior or correctness.",
        },
        "files": [{"path": name, "size": len(value), "sha256": digest(value)}
                  for name, value in sorted(files.items())],
    }
    files["inventory.json"] = (json.dumps(
        inventory, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return files, inventory


def write_or_check(output, files, check=False):
    root = output.resolve()
    targets = []
    for name, data in files.items():
        target = root / name
        if not target.resolve().is_relative_to(root):
            raise ValueError(f"Output path escapes destination: {name}")
        if target.exists():
            if not target.is_file() or target.read_bytes() != data:
                raise ValueError(f"Existing file differs; refusing to overwrite: {name}")
        elif check:
            raise ValueError(f"Missing extracted file: {name}")
        targets.append((target, data))
    # Preflight every target before creating files. Never replace edited evidence.
    if not check:
        for target, data in targets:
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open("xb") as stream:
                    stream.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("harmony-release-signed.app"))
    parser.add_argument("--output", type=Path, default=Path("recovered"))
    parser.add_argument("--check", action="store_true", help="Verify without writing files")
    args = parser.parse_args()
    try:
        files, inventory = collect(args.input)
        write_or_check(args.output, files, args.check)
    except (OSError, ValueError, KeyError, BadZipFile, RuntimeError) as error:
        parser.exit(1, f"Error: {error}\n")
    print(f"{'Verified' if args.check else 'Extracted'} {len(files)} files; "
          f"{len(inventory['routes'])} routes; "
          f"{len(inventory['bytecode_indicators']['module_paths'])} module indicators")


if __name__ == "__main__":
    main()

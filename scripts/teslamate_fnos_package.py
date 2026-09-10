#!/usr/bin/env python3
"""Build and verify the secret-free TeslaMate fnOS FPK test package."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import gzip
import hashlib
import io
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
from typing import Mapping, NoReturn


EXPECTED_APPNAME = "App.Native.TeslaMate"
EXPECTED_SERVICES = ("teslamate", "database", "grafana", "mosquitto", "teslamateapi")
TOKEN_BY_SERVICE = {
    "teslamate": "@@TESLAMATE_IMAGE@@",
    "database": "@@DATABASE_IMAGE@@",
    "grafana": "@@GRAFANA_IMAGE@@",
    "mosquitto": "@@MOSQUITTO_IMAGE@@",
    "teslamateapi": "@@TESLAMATEAPI_IMAGE@@",
}
SOURCE_TAGS = {
    "teslamate": ("teslamate/teslamate", "teslamate/teslamate:4.0.1"),
    "database": ("postgres", "postgres:18-trixie"),
    "grafana": ("teslamate/grafana", "teslamate/grafana:latest"),
    "mosquitto": ("eclipse-mosquitto", "eclipse-mosquitto:2"),
    "teslamateapi": ("mytesla/teslamateapi", "mytesla/teslamateapi:2.6"),
}
DIGEST_PATTERN = re.compile(r"sha256:[0-9a-f]{64}")
REPOSITORY_PATTERN = re.compile(r"[a-z0-9]+(?:[._/-][a-z0-9]+)*")
EMAIL_PATTERN = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
IPV4_PATTERN = re.compile(r"(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])")
RFC1918_NETWORKS = tuple(
    ipaddress.ip_network(cidr) for cidr in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)
OUTER_PATHS = (
    "manifest",
    "config/privilege",
    "config/resource",
    "wizard/install",
    "wizard/config",
    "cmd/main",
    "cmd/install_init",
    "cmd/install_callback",
    "cmd/config_init",
    "cmd/config_callback",
    "cmd/upgrade_init",
    "cmd/upgrade_callback",
    "cmd/uninstall_init",
    "cmd/uninstall_callback",
    "ICON.PNG",
    "ICON_256.PNG",
)
EXPECTED_INNER_BASE = {
    "docker/config.template",
    "docker/docker-compose.yaml",
    "ui/config",
    "ui/images/icon_64.png",
    "ui/images/icon_256.png",
}


class PackageError(ValueError):
    """Raised when an image lock or FPK violates the package contract."""


def fail(message: str) -> NoReturn:
    raise PackageError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@dataclass(frozen=True)
class ImageLockEntry:
    service: str
    source_tag: str
    repository: str
    pull_repository: str
    digest: str
    platform: str

    @property
    def immutable_reference(self) -> str:
        return f"{self.pull_repository}@{self.digest}"


@dataclass(frozen=True)
class ImageLock:
    entries: Mapping[str, ImageLockEntry]

    @classmethod
    def load(cls, path: Path) -> "ImageLock":
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            fail(f"image lock is not valid JSON: {error}")
        if not isinstance(payload, dict) or payload.get("schemaVersion") != 1:
            fail("image lock schemaVersion must be 1")
        raw_entries = payload.get("images")
        if not isinstance(raw_entries, list):
            fail("image lock images must be an array")
        entries: dict[str, ImageLockEntry] = {}
        for raw in raw_entries:
            if not isinstance(raw, dict):
                fail("image lock entries must be objects")
            service = raw.get("service")
            source_tag = raw.get("sourceTag")
            repository = raw.get("repository")
            pull_repository = raw.get("pullRepository", repository)
            digest = raw.get("digest")
            platform = raw.get("platform")
            if service not in EXPECTED_SERVICES:
                fail(f"unexpected image service: {service!r}")
            if service in entries:
                fail(f"duplicate image service: {service}")
            if not isinstance(source_tag, str) or not source_tag:
                fail(f"{service} sourceTag must be non-empty")
            if not isinstance(repository, str) or not REPOSITORY_PATTERN.fullmatch(repository):
                fail(f"{service} repository is invalid")
            if not source_tag.startswith(f"{repository}:") or source_tag == f"{repository}:":
                fail(f"{service} sourceTag must be a tag from {repository}")
            if not isinstance(pull_repository, str) or not REPOSITORY_PATTERN.fullmatch(pull_repository):
                fail(f"{service} pullRepository is invalid")
            if not isinstance(digest, str) or not DIGEST_PATTERN.fullmatch(digest):
                fail(f"{service} digest must be sha256 followed by 64 lowercase hex characters")
            if platform != "linux/amd64":
                fail(f"{service} platform must be linux/amd64")
            entries[service] = ImageLockEntry(
                service=service,
                source_tag=source_tag,
                repository=repository,
                pull_repository=pull_repository,
                digest=digest,
                platform=platform,
            )
        if set(entries) != set(EXPECTED_SERVICES):
            missing = sorted(set(EXPECTED_SERVICES) - set(entries))
            fail(f"image lock is missing services: {', '.join(missing)}")
        return cls(entries=entries)


@dataclass(frozen=True)
class VerificationResult:
    appname: str
    version: str
    sha256: str
    outer_members: int
    inner_members: int


def create_image_lock(docker: str, output: Path) -> ImageLock:
    entries: list[dict[str, str]] = []
    for service in EXPECTED_SERVICES:
        repository, source_tag = SOURCE_TAGS[service]
        pulled = subprocess.run(
            (docker, "pull", "--platform", "linux/amd64", source_tag),
            check=False,
            capture_output=True,
            text=True,
        )
        if pulled.returncode != 0:
            fail(f"Docker could not pull {source_tag} for linux/amd64")
        inspected = subprocess.run(
            (docker, "image", "inspect", source_tag),
            check=False,
            capture_output=True,
            text=True,
        )
        if inspected.returncode != 0:
            fail(f"Docker could not inspect {source_tag}")
        try:
            payload = json.loads(inspected.stdout)
        except json.JSONDecodeError:
            fail(f"Docker inspect returned invalid JSON for {source_tag}")
        if not isinstance(payload, list) or len(payload) != 1 or not isinstance(payload[0], dict):
            fail(f"Docker inspect returned an unexpected record for {source_tag}")
        image = payload[0]
        if image.get("Os") != "linux" or image.get("Architecture") != "amd64":
            fail(f"Docker pulled a non-linux/amd64 image for {source_tag}")
        repo_digests = image.get("RepoDigests")
        prefix = f"{repository}@"
        matching = [value for value in repo_digests or [] if isinstance(value, str) and value.startswith(prefix)]
        if len(matching) != 1:
            fail(f"Docker inspect did not return one digest for {source_tag}")
        digest = matching[0][len(prefix) :]
        entries.append(
            {
                "service": service,
                "sourceTag": source_tag,
                "repository": repository,
                "digest": digest,
                "platform": "linux/amd64",
            }
        )
    payload = {"schemaVersion": 1, "images": entries}
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.tmp")
    temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    temporary.replace(output)
    return ImageLock.load(output)


def render_compose(template: str, lock: ImageLock) -> str:
    rendered = template
    for service in EXPECTED_SERVICES:
        token = TOKEN_BY_SERVICE[service]
        if rendered.count(token) != 1:
            fail(f"Compose template must contain {token} exactly once")
        rendered = rendered.replace(token, lock.entries[service].immutable_reference)
    if "@@" in rendered:
        fail("Compose template contains an unresolved token")
    return rendered


def _safe_name(name: str) -> str:
    clean = PurePosixPath(name)
    if clean.is_absolute() or ".." in clean.parts or str(clean) in ("", "."):
        fail(f"unsafe archive member: {name}")
    return str(clean)


def _mode_for(name: str) -> int:
    return 0o755 if name.startswith("cmd/") else 0o644


def _make_tar(files: Mapping[str, bytes], epoch: int, *, compressed: bool) -> bytes:
    output = io.BytesIO()
    if compressed:
        with gzip.GzipFile(fileobj=output, mode="wb", filename="", mtime=epoch, compresslevel=9) as zipped:
            with tarfile.open(fileobj=zipped, mode="w", format=tarfile.USTAR_FORMAT) as archive:
                _add_members(archive, files, epoch)
    else:
        with tarfile.open(fileobj=output, mode="w", format=tarfile.USTAR_FORMAT) as archive:
            _add_members(archive, files, epoch)
    return output.getvalue()


def _add_members(archive: tarfile.TarFile, files: Mapping[str, bytes], epoch: int) -> None:
    for raw_name in sorted(files):
        name = _safe_name(raw_name)
        data = files[raw_name]
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = _mode_for(name)
        info.uid = 0
        info.gid = 0
        info.uname = "root"
        info.gname = "root"
        info.mtime = epoch
        archive.addfile(info, io.BytesIO(data))


def _read_required(source: Path, relative: str) -> bytes:
    path = source / relative
    if not path.is_file():
        fail(f"missing package source: {relative}")
    return path.read_bytes()


def _inner_files(source: Path, lock: ImageLock) -> dict[str, bytes]:
    app_root = source / "app"
    if not app_root.is_dir():
        fail("missing package source: app")
    files: dict[str, bytes] = {}
    for path in sorted(app_root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(app_root).as_posix()
        if relative == "docker/docker-compose.yaml.in":
            template = path.read_text(encoding="utf-8")
            files["docker/docker-compose.yaml"] = render_compose(template, lock).encode("utf-8")
        else:
            files[relative] = path.read_bytes()
    if "docker/docker-compose.yaml" not in files:
        fail("missing package source: app/docker/docker-compose.yaml.in")
    return files


def build_fpk(source: Path, output: Path, lock: ImageLock, epoch: int) -> Path:
    if epoch < 0:
        fail("epoch must be non-negative")
    inner = _inner_files(source, lock)
    app_tgz = _make_tar(inner, epoch, compressed=True)
    outer = {relative: _read_required(source, relative) for relative in OUTER_PATHS}
    outer["app.tgz"] = app_tgz
    checksums = "".join(f"{sha256(outer[name])}  {name}\n" for name in sorted(outer))
    outer["SHA256SUMS"] = checksums.encode("ascii")
    package = _make_tar(outer, epoch, compressed=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.tmp")
    temporary.write_bytes(package)
    temporary.replace(output)
    return output


def stage_fnpack_source(source: Path, output: Path, lock: ImageLock) -> Path:
    if output.exists():
        fail(f"fnpack staging output already exists: {output}")
    for relative in OUTER_PATHS:
        data = _read_required(source, relative)
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        destination.chmod(_mode_for(relative))
    for relative, data in _inner_files(source, lock).items():
        destination = output / "app" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        destination.chmod(0o644)
    return output


def _read_tar(
    path_or_bytes: Path | bytes,
    *,
    label: str,
    allow_directories: bool = False,
) -> dict[str, bytes]:
    if isinstance(path_or_bytes, Path):
        archive_context = tarfile.open(path_or_bytes, mode="r:gz")
    else:
        archive_context = tarfile.open(fileobj=io.BytesIO(path_or_bytes), mode="r:gz")
    files: dict[str, bytes] = {}
    with archive_context as archive:
        for info in archive.getmembers():
            name = _safe_name(info.name)
            if info.isdir() and allow_directories:
                continue
            if not info.isfile():
                fail(f"{label} contains a non-file member: {name}")
            if name in files:
                fail(f"{label} contains a duplicate member: {name}")
            extracted = archive.extractfile(info)
            if extracted is None:
                fail(f"cannot read {label} member: {name}")
            files[name] = extracted.read()
    return files


def _parse_manifest(data: bytes) -> tuple[str, str]:
    values: dict[str, str] = {}
    for raw_line in data.decode("utf-8").splitlines():
        if "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        values[key.strip()] = value.strip()
    appname = values.get("appname", "")
    version = values.get("version", "")
    if appname != EXPECTED_APPNAME:
        fail(f"manifest appname must be {EXPECTED_APPNAME}")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){2}", version):
        fail("manifest version must use three numeric components")
    return appname, version


def _parse_checksums(data: bytes) -> dict[str, str]:
    entries: dict[str, str] = {}
    for line in data.decode("ascii").splitlines():
        digest, separator, name = line.partition("  ")
        if not separator or not re.fullmatch(r"[0-9a-f]{64}", digest) or not name:
            fail("SHA256SUMS contains an invalid entry")
        entries[name] = digest
    return entries


def _scan_text_members(files: Mapping[str, bytes], *, label: str) -> None:
    binary_suffixes = (".png", ".ico", ".tgz", ".gz")
    for name, data in files.items():
        if name.lower().endswith(binary_suffixes):
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if EMAIL_PATTERN.search(text):
            fail(f"{label} contains an email address: {name}")
        if "BEGIN PRIVATE KEY" in text or "BEGIN OPENSSH PRIVATE KEY" in text:
            fail(f"{label} contains private key material: {name}")
        if re.search(r"authorization\s*:\s*bearer\s+\S+", text, re.IGNORECASE):
            fail(f"{label} contains a bearer credential: {name}")
        for match in IPV4_PATTERN.finditer(text):
            address = match.group(0)
            octets = address.split(".")
            if any(int(octet) > 255 for octet in octets):
                continue
            if address not in {"0.0.0.0", "127.0.0.1"}:
                suffix = text[match.end() :]
                prefix = re.match(r"/(?:[0-9]|[12][0-9]|3[0-2])(?=$|[^0-9])", suffix)
                if prefix is not None:
                    try:
                        network = ipaddress.ip_network(address + prefix.group(0), strict=True)
                    except ValueError:
                        network = None
                    if network is not None and any(network.subnet_of(parent) for parent in RFC1918_NETWORKS):
                        continue
                fail(f"{label} contains a non-local IPv4 address: {name}")


def verify_fpk(path: Path, *, official: bool = False) -> VerificationResult:
    if not path.is_file():
        fail(f"FPK does not exist: {path}")
    outer = _read_tar(path, label="FPK", allow_directories=official)
    required = set(OUTER_PATHS) | {"app.tgz"}
    if not official:
        required.add("SHA256SUMS")
    if set(outer) != required:
        fail(f"FPK outer members differ: {sorted(set(outer) ^ required)}")
    if not official:
        checksums = _parse_checksums(outer["SHA256SUMS"])
        expected_checksum_names = set(outer) - {"SHA256SUMS"}
        if set(checksums) != expected_checksum_names:
            fail("SHA256SUMS must cover every non-checksum outer member exactly once")
        for name in expected_checksum_names:
            if sha256(outer[name]) != checksums[name]:
                fail(f"SHA256SUMS mismatch: {name}")
    appname, version = _parse_manifest(outer["manifest"])
    inner = _read_tar(outer["app.tgz"], label="app.tgz", allow_directories=official)
    expected_inner = set(EXPECTED_INNER_BASE)
    if official:
        expected_inner.update({"config/privilege", "config/resource"})
    if set(inner) != expected_inner:
        fail(f"app.tgz members differ: {sorted(set(inner) ^ expected_inner)}")
    _scan_text_members(outer, label="FPK")
    _scan_text_members(inner, label="app.tgz")
    compose = inner.get("docker/docker-compose.yaml", b"").decode("utf-8")
    if not compose:
        fail("app.tgz is missing docker/docker-compose.yaml")
    if "@@" in compose:
        fail("rendered Compose contains an unresolved token")
    image_lines = [line.strip() for line in compose.splitlines() if line.strip().startswith("image:")]
    if len(image_lines) != 5 or any("@sha256:" not in line for line in image_lines):
        fail("rendered Compose must contain exactly five immutable image references")
    return VerificationResult(
        appname=appname,
        version=version,
        sha256=sha256(path.read_bytes()),
        outer_members=len(outer),
        inner_members=len(inner),
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    lock = commands.add_parser("lock", help="pull and lock the five linux/amd64 images")
    lock.add_argument("--docker", default="docker")
    lock.add_argument("--output", type=Path, required=True)
    build = commands.add_parser("build", help="build a deterministic unsigned FPK")
    build.add_argument("--source", type=Path, required=True)
    build.add_argument("--lock", type=Path, required=True)
    build.add_argument("--output", type=Path, required=True)
    stage = commands.add_parser("stage", help="render an official fnpack source directory")
    stage.add_argument("--source", type=Path, required=True)
    stage.add_argument("--lock", type=Path, required=True)
    stage.add_argument("--output", type=Path, required=True)
    verify = commands.add_parser("verify", help="verify an unsigned FPK")
    verify.add_argument("path", type=Path)
    verify_official = commands.add_parser("verify-official", help="verify an official fnpack FPK")
    verify_official.add_argument("path", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "lock":
            lock = create_image_lock(args.docker, args.output)
            print(f"locked {len(lock.entries)} linux/amd64 images to {args.output}")
            return 0
        if args.command == "build":
            try:
                epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))
            except ValueError:
                fail("SOURCE_DATE_EPOCH must be a non-negative integer")
            lock = ImageLock.load(args.lock)
            built = build_fpk(args.source, args.output, lock, epoch)
            result = verify_fpk(built)
            print(f"built {built} ({built.stat().st_size} bytes, {result.appname} {result.version})")
            print(f"sha256 {result.sha256}")
            return 0
        if args.command == "stage":
            lock = ImageLock.load(args.lock)
            staged = stage_fnpack_source(args.source, args.output, lock)
            print(f"staged official fnpack source at {staged}")
            return 0
        result = verify_fpk(args.path, official=args.command == "verify-official")
        print(
            f"verified {args.path} ({result.outer_members} outer, "
            f"{result.inner_members} inner, {result.appname} {result.version})"
        )
        print(f"sha256 {result.sha256}")
        return 0
    except PackageError as error:
        print(f"TeslaMate fnOS package error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
import argparse
import os
import re
import struct
import sys
import zlib
from pathlib import Path


TEXT_SUFFIXES = {
    ".bash",
    ".c",
    ".cc",
    ".cpp",
    ".css",
    ".feature",
    ".graphql",
    ".h",
    ".hpp",
    ".html",
    ".js",
    ".jsx",
    ".json",
    ".md",
    ".mm",
    ".m",
    ".plist",
    ".py",
    ".rb",
    ".sh",
    ".sql",
    ".strings",
    ".swift",
    ".toml",
    ".ts",
    ".tsx",
    ".txt",
    ".xcprivacy",
    ".xcstrings",
    ".xml",
    ".yaml",
    ".yml",
}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
EXCLUDED_DIRECTORY_NAMES = {
    ".build",
    ".git",
    ".superpowers",
    "build",
    "derived",
    "deriveddata",
    "dist",
    "out",
    "output",
    "xcuserdata",
}

PRIVATE_VIN = re.compile(r"(?<![A-Za-z0-9])5YJ[A-HJ-NPR-Z0-9]{14}(?![A-Za-z0-9])", re.IGNORECASE)
URL_WITH_CREDENTIALS = re.compile(r"\bhttps?://[^\s/@:]+:[^\s/@]+@[^\s]+", re.IGNORECASE)
GPS_COORDINATE_PAIR = re.compile(
    r"\b(?:gps|coordinates?)\b[\"']?\s*(?:[:=]\s*)?[\[(]?\s*"
    r"(?<![0-9.])-?(?:1[0-7]\d|180|[0-9]?\d)\.\d+\s*[,;/]\s*"
    r"-?(?:1[0-7]\d|180|[0-9]?\d)\.\d+(?![0-9.])",
    re.IGNORECASE,
)
LATITUDE_FIELD = re.compile(
    r"\b(?:latitude|lat)\b[\"']?\s*(?::|=|\s)\s*[\"']?"
    r"-?(?:[0-8]?\d|90)(?:\.\d+)?",
    re.IGNORECASE,
)
LONGITUDE_FIELD = re.compile(
    r"\b(?:longitude|lon)\b[\"']?\s*(?::|=|\s)\s*[\"']?"
    r"-?(?:1[0-7]\d|180|[0-9]?\d)(?:\.\d+)?",
    re.IGNORECASE,
)
SWIFT_LATITUDE_FIELD = re.compile(
    r"\b(?:latitude|lat)\b\s*(?:=|:)\s*[\"']?"
    r"-?(?:[0-8]?\d|90)(?:\.\d+)?",
    re.IGNORECASE,
)
SWIFT_LONGITUDE_FIELD = re.compile(
    r"\b(?:longitude|lon)\b\s*(?:=|:)\s*[\"']?"
    r"-?(?:1[0-7]\d|180|[0-9]?\d)(?:\.\d+)?",
    re.IGNORECASE,
)
MAX_COORDINATE_FIELD_DISTANCE = 8


def is_excluded_directory(name: str) -> bool:
    return name.lower() in EXCLUDED_DIRECTORY_NAMES


def is_private_environment_file(name: str) -> bool:
    lowered = name.lower()
    return lowered == ".env" or lowered.startswith(".env.") or lowered.endswith(".env")


def is_candidate(path: Path) -> bool:
    return path.suffix.lower() == ".png" or path.suffix.lower() in TEXT_SUFFIXES


def contains_credentialed_private_url(text: str) -> bool:
    return bool(URL_WITH_CREDENTIALS.search(text))


def contains_private_vehicle_data(text: str) -> bool:
    return bool(
        PRIVATE_VIN.search(text)
        or contains_credentialed_private_url(text)
        or GPS_COORDINATE_PAIR.search(text)
    )


def first_coordinate_field_line(lines: list[str], *, swift_source: bool) -> int | None:
    latitude_field = SWIFT_LATITUDE_FIELD if swift_source else LATITUDE_FIELD
    longitude_field = SWIFT_LONGITUDE_FIELD if swift_source else LONGITUDE_FIELD
    latitude_line: int | None = None
    longitude_line: int | None = None

    for line_number, line in enumerate(lines, start=1):
        has_latitude = bool(latitude_field.search(line))
        has_longitude = bool(longitude_field.search(line))
        if has_latitude and has_longitude:
            return line_number
        if has_latitude:
            if longitude_line is not None and line_number - longitude_line <= MAX_COORDINATE_FIELD_DISTANCE:
                return min(line_number, longitude_line)
            latitude_line = line_number
        if has_longitude:
            if latitude_line is not None and line_number - latitude_line <= MAX_COORDINATE_FIELD_DISTANCE:
                return min(line_number, latitude_line)
            longitude_line = line_number
        if latitude_line is not None and line_number - latitude_line > MAX_COORDINATE_FIELD_DISTANCE:
            latitude_line = None
        if longitude_line is not None and line_number - longitude_line > MAX_COORDINATE_FIELD_DISTANCE:
            longitude_line = None
    return None


def contains_coordinate_fields_on_line(line: str, *, swift_source: bool) -> bool:
    latitude_field = SWIFT_LATITUDE_FIELD if swift_source else LATITUDE_FIELD
    longitude_field = SWIFT_LONGITUDE_FIELD if swift_source else LONGITUDE_FIELD
    return bool(latitude_field.search(line) and longitude_field.search(line))


def png_metadata_text(path: Path) -> list[str]:
    try:
        data = path.read_bytes()
        if not data.startswith(PNG_SIGNATURE):
            return []

        metadata: list[str] = []
        offset = len(PNG_SIGNATURE)
        while offset + 12 <= len(data):
            length = struct.unpack_from(">I", data, offset)[0]
            chunk_start = offset + 8
            chunk_end = chunk_start + length
            if chunk_end + 4 > len(data):
                return metadata
            chunk_type = data[offset + 4 : offset + 8]
            chunk_data = data[chunk_start:chunk_end]
            offset = chunk_end + 4

            try:
                if chunk_type == b"tEXt":
                    _, separator, value = chunk_data.partition(b"\0")
                    if separator:
                        metadata.append(value.decode("latin-1"))
                elif chunk_type == b"zTXt":
                    _, separator, compressed = chunk_data.partition(b"\0")
                    if separator and compressed[:1] == b"\0":
                        metadata.append(zlib.decompress(compressed[1:]).decode("latin-1"))
                elif chunk_type == b"iTXt":
                    keyword_end = chunk_data.find(b"\0")
                    if keyword_end >= 0 and len(chunk_data) >= keyword_end + 3:
                        compression_flag = chunk_data[keyword_end + 1]
                        remainder = chunk_data[keyword_end + 3 :]
                        language_end = remainder.find(b"\0")
                        if language_end >= 0:
                            remainder = remainder[language_end + 1 :]
                            translated_end = remainder.find(b"\0")
                            if translated_end >= 0:
                                value = remainder[translated_end + 1 :]
                                if compression_flag == 1:
                                    value = zlib.decompress(value)
                                metadata.append(value.decode("utf-8", errors="replace"))
            except (UnicodeDecodeError, zlib.error):
                continue
            if chunk_type == b"IEND":
                break
        return metadata
    except (OSError, struct.error, zlib.error):
        return []


def audit_repository(root: Path) -> list[str]:
    findings: set[str] = set()
    root = root.resolve()
    for directory, directory_names, file_names in os.walk(root):
        directory_names[:] = sorted(
            name for name in directory_names if not is_excluded_directory(name)
        )
        for file_name in sorted(file_names):
            if is_private_environment_file(file_name):
                continue
            path = Path(directory) / file_name
            if not is_candidate(path):
                continue

            relative_path = path.relative_to(root).as_posix()
            if path.suffix.lower() == ".png":
                for metadata in png_metadata_text(path):
                    if contains_private_vehicle_data(metadata):
                        findings.add(f"{relative_path}:1")
                continue

            try:
                lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
            except OSError:
                continue
            coordinate_line = first_coordinate_field_line(
                lines,
                swift_source=path.suffix.lower() == ".swift",
            )
            if coordinate_line is not None:
                findings.add(f"{relative_path}:{coordinate_line}")
            swift_source = path.suffix.lower() == ".swift"
            for line_number, line in enumerate(lines, start=1):
                if contains_private_vehicle_data(line) or contains_coordinate_fields_on_line(
                    line,
                    swift_source=swift_source,
                ):
                    findings.add(f"{relative_path}:{line_number}")

    return sorted(findings)


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit repository vehicle fixtures for private data.")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root to scan",
    )
    args = parser.parse_args()
    if not args.root.is_dir():
        parser.error(f"root is not a directory: {args.root}")

    findings = audit_repository(args.root)
    for finding in findings:
        print(finding)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())

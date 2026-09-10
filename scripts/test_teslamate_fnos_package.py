from __future__ import annotations

import io
import json
import os
from pathlib import Path
import shutil
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import struct
import subprocess
import sys
import tarfile
import tempfile
from threading import Thread
import unittest
import zlib

from scripts.teslamate_fnos_package import ImageLock, PackageError, build_fpk, render_compose, verify_fpk


SERVICES = ("teslamate", "database", "grafana", "mosquitto", "teslamateapi")
ROOT = Path(__file__).resolve().parents[1]
REAL_SOURCE = ROOT / "release/fnos/teslamate"


def png(width: int, height: int) -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + b"\x20\x80\xe0\xff" * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def write(path: Path, content: str | bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content.encode("utf-8") if isinstance(content, str) else content)


def make_source(root: Path) -> Path:
    source = root / "source"
    write(
        source / "manifest",
        "\n".join(
            (
                "appname = App.Native.TeslaMate",
                "version = 0.1.0",
                "display_name = TeslaMate",
                "platform = x86",
                "service_port = 14000",
                "checkport = true",
            )
        )
        + "\n",
    )
    write(source / "config/resource", '{"docker-project":{"projects":[{"name":"teslamate-fnos","path":"docker"}]}}\n')
    write(source / "config/privilege", '{"defaults":{"run-as":"package"},"username":"teslamate","groupname":"teslamate"}\n')
    write(source / "wizard/install", "[]\n")
    write(source / "wizard/config", "[]\n")
    for name in (
        "main",
        "install_init",
        "install_callback",
        "config_init",
        "config_callback",
        "upgrade_init",
        "upgrade_callback",
        "uninstall_init",
        "uninstall_callback",
    ):
        write(source / "cmd" / name, "#!/bin/sh\nexit 0\n")
    write(source / "app/docker/config.template", "TESLAMATE_PORT=14000\n")
    compose = "services:\n"
    for service in SERVICES:
        compose += f"  {service}:\n    image: @@{service.upper()}_IMAGE@@\n"
    write(source / "app/docker/docker-compose.yaml.in", compose)
    write(source / "app/ui/config", '{".url":{}}\n')
    write(source / "app/ui/images/icon_64.png", png(64, 64))
    write(source / "app/ui/images/icon_256.png", png(256, 256))
    write(source / "ICON.PNG", png(64, 64))
    write(source / "ICON_256.PNG", png(256, 256))
    return source


def make_lock(path: Path) -> ImageLock:
    entries = []
    digest_chars = ("a", "b", "c", "d", "e")
    repositories = (
        "teslamate/teslamate",
        "postgres",
        "teslamate/grafana",
        "eclipse-mosquitto",
        "mytesla/teslamateapi",
    )
    tags = ("4.0.1", "18-trixie", "latest", "2", "2.6")
    for service, repository, tag, char in zip(SERVICES, repositories, tags, digest_chars):
        entries.append(
            {
                "service": service,
                "sourceTag": f"{repository}:{tag}",
                "repository": repository,
                "digest": f"sha256:{char * 64}",
                "platform": "linux/amd64",
            }
        )
    write(path, json.dumps({"schemaVersion": 1, "images": entries}, indent=2) + "\n")
    return ImageLock.load(path)


def make_official_shape(unsigned: Path, output: Path) -> Path:
    with tarfile.open(unsigned, mode="r:gz") as archive:
        outer = {
            member.name: archive.extractfile(member).read()
            for member in archive.getmembers()
            if member.isfile() and member.name != "SHA256SUMS"
        }
    with tarfile.open(fileobj=io.BytesIO(outer["app.tgz"]), mode="r:gz") as archive:
        inner = {
            member.name: archive.extractfile(member).read()
            for member in archive.getmembers()
            if member.isfile()
        }
    inner["config/privilege"] = outer["config/privilege"]
    inner["config/resource"] = outer["config/resource"]

    inner_buffer = io.BytesIO()
    with tarfile.open(fileobj=inner_buffer, mode="w:gz") as archive:
        for directory in ("docker", "ui", "ui/images", "config"):
            info = tarfile.TarInfo(directory)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            archive.addfile(info)
        for name, data in sorted(inner.items()):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))
    outer["app.tgz"] = inner_buffer.getvalue()

    with tarfile.open(output, mode="w:gz") as archive:
        for directory in ("cmd", "config", "wizard"):
            info = tarfile.TarInfo(directory)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            archive.addfile(info)
        for name, data in sorted(outer.items()):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o755 if name.startswith("cmd/") else 0o644
            archive.addfile(info, io.BytesIO(data))
    return output


class PackageBuildTests(unittest.TestCase):
    def test_build_renders_locked_images_and_verifies_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = make_source(root)
            lock = make_lock(root / "image-lock.json")
            output = root / "App.Native.TeslaMate_0.1.0_x86.fpk"

            built = build_fpk(source, output, lock, epoch=1_786_377_600)
            result = verify_fpk(built)

            self.assertEqual(result.appname, "App.Native.TeslaMate")
            self.assertEqual(result.version, "0.1.0")
            self.assertEqual(len(result.sha256), 64)
            with tarfile.open(built, mode="r:gz") as outer:
                names = set(outer.getnames())
                self.assertIn("SHA256SUMS", names)
                self.assertIn("app.tgz", names)
                app_tgz = outer.extractfile("app.tgz")
                self.assertIsNotNone(app_tgz)
                with tarfile.open(fileobj=io.BytesIO(app_tgz.read()), mode="r:gz") as inner:
                    compose_file = inner.extractfile("docker/docker-compose.yaml")
                    self.assertIsNotNone(compose_file)
                    compose = compose_file.read().decode("utf-8")

            self.assertNotIn("@@", compose)
            self.assertEqual(compose.count("@sha256:"), 5)
            self.assertIn("teslamate/teslamate@sha256:" + "a" * 64, compose)
            self.assertIn("postgres@sha256:" + "b" * 64, compose)
            self.assertIn("teslamate/grafana@sha256:" + "c" * 64, compose)
            self.assertIn("eclipse-mosquitto@sha256:" + "d" * 64, compose)
            self.assertIn("mytesla/teslamateapi@sha256:" + "e" * 64, compose)

    def test_verify_rejects_sensitive_or_personal_payloads(self) -> None:
        forbidden_samples = (
            "contact=user@example.invalid",
            "-----BEGIN PRIVATE KEY-----",
            "Authorization: Bearer synthetic-token-value",
            "server=203.0.113.10",
            "nas=192.168.3.82",
        )
        for sample in forbidden_samples:
            with self.subTest(sample=sample), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                source = make_source(root)
                write(source / "app/docker/config.template", "TESLAMATE_PORT=14000\n" + sample + "\n")
                lock = make_lock(root / "image-lock.json")
                output = root / "App.Native.TeslaMate_0.1.0_x86.fpk"

                build_fpk(source, output, lock, epoch=1_786_377_600)

                with self.assertRaises(PackageError):
                    verify_fpk(output)

    def test_verify_allows_a_private_network_cidr_without_allowing_private_hosts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = make_source(root)
            write(
                source / "app/docker/config.template",
                "TESLAMATE_PORT=14000\ndocker_subnet=10.253.0.0/24\n",
            )
            lock = make_lock(root / "image-lock.json")
            output = root / "App.Native.TeslaMate_0.1.0_x86.fpk"

            build_fpk(source, output, lock, epoch=1_786_377_600)

            result = verify_fpk(output)
            self.assertEqual(result.appname, "App.Native.TeslaMate")

    def test_verify_official_accepts_fnpack_shape_without_weakening_compose_checks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = make_source(root)
            lock = make_lock(root / "image-lock.json")
            unsigned = build_fpk(source, root / "unsigned.fpk", lock, epoch=1_786_377_600)
            official = make_official_shape(unsigned, root / "official.fpk")

            result = verify_fpk(official, official=True)

            self.assertEqual(result.appname, "App.Native.TeslaMate")
            self.assertEqual(result.version, "0.1.0")
            self.assertEqual(result.outer_members, 17)
            self.assertEqual(result.inner_members, 7)


class QuietHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, format: str, *args: object) -> None:
        return


class SourceContractTests(unittest.TestCase):
    def test_real_api_image_uses_canonical_repository_for_registry_failover(self) -> None:
        lock = ImageLock.load(REAL_SOURCE / "image-lock.json")
        api = lock.entries["teslamateapi"]

        self.assertEqual(api.pull_repository, api.repository)
        compose = render_compose(
            (REAL_SOURCE / "app/docker/docker-compose.yaml.in").read_text(encoding="utf-8"),
            lock,
        )
        self.assertIn(f"image: mytesla/teslamateapi@{api.digest}", compose)
        self.assertNotIn("docker.1ms.run", compose)

    def test_manifest_resource_and_wizards_form_a_generic_fnos_app(self) -> None:
        manifest_path = REAL_SOURCE / "manifest"
        self.assertTrue(manifest_path.is_file(), f"missing {manifest_path}")
        values: dict[str, str] = {}
        for raw_line in manifest_path.read_text(encoding="utf-8").splitlines():
            if "=" in raw_line:
                key, value = raw_line.split("=", 1)
                values[key.strip()] = value.strip()
        self.assertEqual(values["appname"], "App.Native.TeslaMate")
        self.assertEqual(values["version"], "0.1.2")
        self.assertEqual(values["platform"], "x86")
        self.assertEqual(values["service_port"], "14000")
        self.assertEqual(values["checkport"], "true")
        self.assertEqual(values["desktop_applaunchname"], "App.Native.TeslaMate")

        resource = json.loads((REAL_SOURCE / "config/resource").read_text(encoding="utf-8"))
        self.assertEqual(
            resource,
            {"docker-project": {"projects": [{"name": "teslamate-fnos", "path": "docker"}]}},
        )

        install = json.loads((REAL_SOURCE / "wizard/install").read_text(encoding="utf-8"))
        config = json.loads((REAL_SOURCE / "wizard/config").read_text(encoding="utf-8"))
        expected_fields = {
            "TESLAMATE_PORT",
            "GRAFANA_PORT",
            "TESLAMATEAPI_PORT",
            "DOCKER_SUBNET",
            "TZ",
            "DATABASE_PASS",
            "ENCRYPTION_KEY",
            "GRAFANA_PW",
            "API_TOKEN",
        }

        def fields(steps: list[dict[str, object]]) -> dict[str, dict[str, object]]:
            return {
                item["field"]: item
                for step in steps
                for item in step["items"]
                if isinstance(item, dict) and "field" in item
            }

        install_fields = fields(install)
        config_fields = fields(config)
        self.assertEqual(set(install_fields), expected_fields)
        self.assertEqual(set(config_fields), expected_fields)
        self.assertEqual(install_fields["DOCKER_SUBNET"]["initValue"], "10.253.0.0/24")
        self.assertEqual(config_fields["DOCKER_SUBNET"]["initValue"], "10.253.0.0/24")
        for secret in ("DATABASE_PASS", "ENCRYPTION_KEY", "GRAFANA_PW", "API_TOKEN"):
            self.assertEqual(install_fields[secret]["type"], "password")
            self.assertEqual(config_fields[secret]["type"], "password")
            self.assertTrue(
                any(rule.get("min", 0) >= 12 for rule in install_fields[secret]["rules"]),
                f"{secret} must have a minimum length rule",
            )

        ui = json.loads((REAL_SOURCE / "app/ui/config").read_text(encoding="utf-8"))
        entries = ui[".url"]
        self.assertEqual(
            set(entries),
            {
                "App.Native.TeslaMate",
                "App.Native.TeslaMate.Grafana",
                "App.Native.TeslaMate.API",
            },
        )
        self.assertEqual(entries["App.Native.TeslaMate"]["port"], "${TESLAMATE_PORT}")
        self.assertEqual(entries["App.Native.TeslaMate.Grafana"]["port"], "${GRAFANA_PORT}")
        self.assertEqual(entries["App.Native.TeslaMate.API"]["port"], "${TESLAMATEAPI_PORT}")

    def test_rendered_compose_has_five_isolated_services_and_safe_ports(self) -> None:
        template_path = REAL_SOURCE / "app/docker/docker-compose.yaml.in"
        self.assertTrue(template_path.is_file(), f"missing {template_path}")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            lock = make_lock(root / "image-lock.json")
            compose = render_compose(template_path.read_text(encoding="utf-8"), lock)
            compose_path = root / "docker-compose.yaml"
            write(compose_path, compose)
            env_path = root / "config.env"
            write(
                env_path,
                "\n".join(
                    (
                        "TESLAMATE_PORT=14000",
                        "GRAFANA_PORT=14001",
                        "TESLAMATEAPI_PORT=3030",
                        "DOCKER_SUBNET=10.253.42.0/24",
                        "TZ=Asia/Shanghai",
                        "DATABASE_PASS=" + "p" * 32,
                        "ENCRYPTION_KEY=" + "e" * 64,
                        "GRAFANA_PW=" + "g" * 24,
                        "API_TOKEN=" + "a" * 48,
                    )
                )
                + "\n",
            )
            compose_cli = shutil.which("docker-compose")
            self.assertIsNotNone(compose_cli, "docker-compose 5 is required for the real config test")
            completed = subprocess.run(
                (
                    compose_cli,
                    "--project-name",
                    "teslamate-fnos",
                    "--env-file",
                    str(env_path),
                    "-f",
                    str(compose_path),
                    "config",
                    "--format",
                    "json",
                ),
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            rendered = json.loads(completed.stdout)

        services = rendered["services"]
        self.assertEqual(set(services), set(SERVICES))
        self.assertNotIn("ports", services["database"])
        self.assertNotIn("ports", services["mosquitto"])
        self.assertEqual(services["teslamate"]["ports"][0]["published"], "14000")
        self.assertEqual(services["grafana"]["ports"][0]["published"], "14001")
        self.assertEqual(services["teslamateapi"]["ports"][0]["published"], "3030")
        self.assertEqual(services["teslamateapi"]["environment"]["API_TOKEN_DISABLE"], "false")
        network = rendered["networks"]["teslamate-network"]
        self.assertEqual(network["ipam"]["config"][0]["subnet"], "10.253.42.0/24")
        database_mounts = services["database"]["volumes"]
        self.assertEqual(database_mounts[0]["target"], "/var/lib/postgresql")
        image_references = [services[name]["image"] for name in SERVICES]
        self.assertEqual(sum("@sha256:" in reference for reference in image_references), 5)

    def test_database_rotates_a_preserved_password_before_becoming_healthy(self) -> None:
        template = (REAL_SOURCE / "app/docker/docker-compose.yaml.in").read_text(encoding="utf-8")

        self.assertIn("/usr/local/bin/docker-entrypoint.sh postgres &", template)
        self.assertIn("ALTER ROLE teslamate WITH PASSWORD :'new_password';", template)
        self.assertIn("touch /tmp/teslamate-password-synced", template)
        self.assertIn(
            "test -f /tmp/teslamate-password-synced && pg_isready -U teslamate -d teslamate",
            template,
        )
        self.assertNotIn("/var/run/docker.sock", template)

    def test_main_status_checks_all_three_real_http_endpoints(self) -> None:
        main = REAL_SOURCE / "cmd/main"
        self.assertTrue(main.is_file(), f"missing {main}")
        servers: list[ThreadingHTTPServer] = []
        threads: list[Thread] = []
        try:
            for _ in range(3):
                server = ThreadingHTTPServer(("127.0.0.1", 0), QuietHandler)
                thread = Thread(target=server.serve_forever, daemon=True)
                thread.start()
                servers.append(server)
                threads.append(thread)
            environment = {
                **os.environ,
                "TESLAMATE_PORT": str(servers[0].server_port),
                "GRAFANA_PORT": str(servers[1].server_port),
                "TESLAMATEAPI_PORT": str(servers[2].server_port),
            }
            healthy = subprocess.run((str(main), "status"), env=environment, check=False)
            self.assertEqual(healthy.returncode, 0)

            servers[2].shutdown()
            servers[2].server_close()
            unavailable = subprocess.run((str(main), "status"), env=environment, check=False)
            self.assertEqual(unavailable.returncode, 3)
        finally:
            for server in servers[:2]:
                server.shutdown()
                server.server_close()
            for thread in threads:
                thread.join(timeout=2)

    def test_main_start_syncs_preserved_database_password_without_exposing_it(self) -> None:
        main = REAL_SOURCE / "cmd/main"
        self.assertTrue(main.is_file(), f"missing {main}")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            calls = root / "docker-calls"
            stdin = root / "docker-stdin"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            docker = fake_bin / "docker"
            write(
                docker,
                """#!/bin/sh
printf '%s\n' "$*" >> "$CALLS_FILE"
case "$*" in
  *pg_isready*) exit 0 ;;
  *psql*) cat >> "$STDIN_FILE"; exit 0 ;;
esac
exit 99
""",
            )
            docker.chmod(0o755)
            password = "A" * 32
            environment = {
                **os.environ,
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "CALLS_FILE": str(calls),
                "STDIN_FILE": str(stdin),
                "DATABASE_PASS": password,
            }

            completed = subprocess.run(
                (str(main), "start"),
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            recorded_calls = calls.read_text(encoding="utf-8")
            sql = stdin.read_text(encoding="utf-8")
            self.assertIn(
                "exec -u postgres teslamate-fnos-database-1 pg_isready -q -U teslamate -d teslamate",
                recorded_calls,
            )
            self.assertIn(
                "exec -i -u postgres teslamate-fnos-database-1 psql -v ON_ERROR_STOP=1 -U teslamate -d teslamate",
                recorded_calls,
            )
            self.assertNotIn(password, recorded_calls)
            self.assertNotIn(password, completed.stdout)
            self.assertNotIn(password, completed.stderr)
            self.assertIn("ALTER ROLE teslamate WITH PASSWORD :'new_password';", sql)
            self.assertIn(password, sql)

    def test_main_start_rejects_invalid_database_password_before_invoking_docker(self) -> None:
        main = REAL_SOURCE / "cmd/main"
        self.assertTrue(main.is_file(), f"missing {main}")
        invalid_passwords = ("", "short", "A" * 23 + "-")
        for password in invalid_passwords:
            with self.subTest(password_length=len(password)), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                marker = root / "docker-called"
                fake_bin = root / "bin"
                fake_bin.mkdir()
                docker = fake_bin / "docker"
                write(docker, "#!/bin/sh\nprintf called > \"$MARKER\"\nexit 99\n")
                docker.chmod(0o755)
                environment = {
                    **os.environ,
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "MARKER": str(marker),
                    "DATABASE_PASS": password,
                }

                completed = subprocess.run(
                    (str(main), "start"),
                    env=environment,
                    check=False,
                    capture_output=True,
                    text=True,
                )

                self.assertNotEqual(completed.returncode, 0)
                self.assertFalse(marker.exists(), "invalid password reached Docker")
                self.assertNotIn(password or "missing", completed.stdout)

    def test_lifecycle_callbacks_never_invoke_docker_or_delete_data(self) -> None:
        callback_names = (
            "install_init",
            "install_callback",
            "config_init",
            "config_callback",
            "upgrade_init",
            "upgrade_callback",
            "uninstall_init",
            "uninstall_callback",
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            marker = root / "docker-called"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            docker = fake_bin / "docker"
            write(docker, f"#!/bin/sh\nprintf called > {marker}\nexit 99\n")
            docker.chmod(0o755)
            environment = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"}
            for name in callback_names:
                script = REAL_SOURCE / "cmd" / name
                self.assertTrue(script.is_file(), f"missing {script}")
                completed = subprocess.run((str(script),), env=environment, check=False)
                self.assertEqual(completed.returncode, 0, name)
            self.assertFalse(marker.exists(), "a lifecycle callback invoked Docker")


class ImageLockTests(unittest.TestCase):
    def test_uses_a_distinct_digest_verified_pull_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "image-lock.json"
            make_lock(path)
            payload = json.loads(path.read_text(encoding="utf-8"))
            payload["images"][0]["pullRepository"] = "docker.m.daocloud.io/teslamate/teslamate"
            write(path, json.dumps(payload) + "\n")

            lock = ImageLock.load(path)

            self.assertEqual(
                lock.entries["teslamate"].immutable_reference,
                "docker.m.daocloud.io/teslamate/teslamate@sha256:" + "a" * 64,
            )

    def test_rejects_source_tag_without_the_locked_repository(self) -> None:
        invalid_source_tags = ("latest", "different/repository:4.0.1")
        for source_tag in invalid_source_tags:
            with self.subTest(source_tag=source_tag), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "image-lock.json"
                entries = []
                for service, repository, tag, char in zip(
                    SERVICES,
                    (
                        "teslamate/teslamate",
                        "postgres",
                        "teslamate/grafana",
                        "eclipse-mosquitto",
                        "mytesla/teslamateapi",
                    ),
                    ("4.0.1", "18-trixie", "latest", "2", "2.6"),
                    ("a", "b", "c", "d", "e"),
                ):
                    entries.append(
                        {
                            "service": service,
                            "sourceTag": source_tag if service == "teslamate" else f"{repository}:{tag}",
                            "repository": repository,
                            "digest": f"sha256:{char * 64}",
                            "platform": "linux/amd64",
                        }
                    )
                write(path, json.dumps({"schemaVersion": 1, "images": entries}) + "\n")

                with self.assertRaises(PackageError):
                    ImageLock.load(path)

    def test_rejects_wrong_platform_missing_duplicate_and_invalid_digest(self) -> None:
        mutations = ("wrong-platform", "missing", "duplicate", "invalid-digest")
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                lock_path = root / "image-lock.json"
                valid = make_lock(lock_path)
                payload = json.loads(lock_path.read_text(encoding="utf-8"))
                if mutation == "wrong-platform":
                    payload["images"][0]["platform"] = "linux/arm64"
                elif mutation == "missing":
                    payload["images"].pop()
                elif mutation == "duplicate":
                    payload["images"].append(dict(payload["images"][0]))
                else:
                    payload["images"][0]["digest"] = "sha256:not-a-digest"
                write(lock_path, json.dumps(payload) + "\n")

                with self.assertRaises(PackageError):
                    ImageLock.load(lock_path)


class PackageCliTests(unittest.TestCase):
    def test_verify_official_cli_accepts_fnpack_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = make_source(root)
            lock = make_lock(root / "image-lock.json")
            unsigned = build_fpk(source, root / "unsigned.fpk", lock, epoch=1_786_377_600)
            official = make_official_shape(unsigned, root / "official.fpk")

            completed = subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "scripts/teslamate_fnos_package.py"),
                    "verify-official",
                    str(official),
                ),
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("App.Native.TeslaMate 0.1.0", completed.stdout)

    def test_stage_command_creates_an_official_fnpack_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = make_source(root)
            lock_path = root / "image-lock.json"
            make_lock(lock_path)
            output = root / "official-source"

            completed = subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "scripts/teslamate_fnos_package.py"),
                    "stage",
                    "--source",
                    str(source),
                    "--lock",
                    str(lock_path),
                    "--output",
                    str(output),
                ),
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            compose_path = output / "app/docker/docker-compose.yaml"
            self.assertTrue(compose_path.is_file())
            compose = compose_path.read_text(encoding="utf-8")
            self.assertEqual(compose.count("@sha256:"), 5)
            self.assertFalse((output / "app/docker/docker-compose.yaml.in").exists())
            self.assertFalse((output / "image-lock.json").exists())
            self.assertTrue((output / "cmd/main").stat().st_mode & 0o111)

    def test_lock_command_records_only_verified_amd64_repo_digests(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_docker = root / "docker"
            write(
                fake_docker,
                """#!/usr/bin/env python3
import json
import sys

images = {
    "teslamate/teslamate:4.0.1": ("teslamate/teslamate", "a"),
    "postgres:18-trixie": ("postgres", "b"),
    "teslamate/grafana:latest": ("teslamate/grafana", "c"),
    "eclipse-mosquitto:2": ("eclipse-mosquitto", "d"),
    "mytesla/teslamateapi:2.6": ("mytesla/teslamateapi", "e"),
}
if sys.argv[1] == "pull":
    raise SystemExit(0)
if sys.argv[1:3] == ["image", "inspect"]:
    repository, char = images[sys.argv[3]]
    print(json.dumps([{
        "Architecture": "amd64",
        "Os": "linux",
        "RepoDigests": [repository + "@sha256:" + char * 64],
    }]))
    raise SystemExit(0)
raise SystemExit(2)
""",
            )
            fake_docker.chmod(0o755)
            lock_path = root / "image-lock.json"

            completed = subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "scripts/teslamate_fnos_package.py"),
                    "lock",
                    "--docker",
                    str(fake_docker),
                    "--output",
                    str(lock_path),
                ),
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            lock = ImageLock.load(lock_path)
            self.assertEqual(set(lock.entries), set(SERVICES))
            self.assertEqual(lock.entries["teslamate"].immutable_reference, "teslamate/teslamate@sha256:" + "a" * 64)
            self.assertNotIn("latest@", lock_path.read_text(encoding="utf-8"))

    def test_build_and_verify_cli_create_a_reproducible_package(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = make_source(root)
            lock_path = root / "image-lock.json"
            make_lock(lock_path)
            output = root / "App.Native.TeslaMate_0.1.0_x86.fpk"
            script = str(ROOT / "scripts/teslamate_fnos_package.py")

            build = subprocess.run(
                (
                    sys.executable,
                    script,
                    "build",
                    "--source",
                    str(source),
                    "--lock",
                    str(lock_path),
                    "--output",
                    str(output),
                ),
                env={**os.environ, "SOURCE_DATE_EPOCH": "1786377600"},
                check=False,
                capture_output=True,
                text=True,
            )
            verify = subprocess.run(
                (sys.executable, script, "verify", str(output)),
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(build.returncode, 0, build.stderr)
            self.assertTrue(output.is_file())
            self.assertEqual(verify.returncode, 0, verify.stderr)
            self.assertIn("App.Native.TeslaMate 0.1.0", verify.stdout)
            self.assertNotIn("sha256:" + "a" * 64, build.stdout + verify.stdout)


if __name__ == "__main__":
    unittest.main()

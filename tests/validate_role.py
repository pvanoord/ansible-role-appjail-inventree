#!/usr/bin/env python3
"""Offline structural validation for the role and rendered templates."""
from __future__ import annotations

import json
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined

ROOT = Path(__file__).resolve().parents[1]


class EnvLoader(yaml.SafeLoader):
    pass


def env_constructor(loader: yaml.SafeLoader, node: yaml.Node) -> str:
    return loader.construct_scalar(node)


EnvLoader.add_constructor("!ENV", env_constructor)


def render(name: str, context: dict) -> str:
    env = Environment(
        loader=FileSystemLoader(ROOT / "templates"),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
        autoescape=False,
    )
    env.filters["bool"] = bool
    env.filters["to_json"] = json.dumps
    env.filters["quote"] = shlex.quote
    return env.get_template(name).render(**context)


def main() -> int:
    errors: list[str] = []

    for path in sorted(ROOT.rglob("*.yml")):
        if "templates" in path.parts:
            continue
        try:
            list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
        except Exception as exc:  # noqa: BLE001
            errors.append(f"YAML parse failed for {path.relative_to(ROOT)}: {exc}")

    base = {
        "ansible_facts": {"machine": "amd64"},
        "appjail_inventree_effective_external_interface": "vtnet0",
        "appjail_inventree_effective_release": "14.3-RELEASE",
        "appjail_inventree_network_name": "default",
        "appjail_inventree_network_cidr": "10.77.0.0/24",
        "appjail_inventree_shorten_domain_names": True,
        "appjail_inventree_manage_dns": True,
        "appjail_inventree_enable_zfs": False,
        "appjail_inventree_dns_address": "172.16.0.1",
        "appjail_inventree_jail_name": "inventree",
        "appjail_inventree_db_jail_name": "inventree-mariadb",
        "appjail_inventree_cache_jail_name": "inventree-redis",
        "appjail_inventree_proxy_jail_name": "inventree-nginx",
        "appjail_inventree_oci_image": "ghcr.io/pvanoord/inventree-freebsd",
        "appjail_inventree_oci_tag": "15.1",
        "appjail_inventree_mariadb_makejail": "gh+AppJail-makejails/mariadb",
        "appjail_inventree_redis_makejail": "gh+AppJail-makejails/redis",
        "appjail_inventree_nginx_makejail": "gh+AppJail-makejails/nginx",
        "appjail_inventree_db_name": "inventree",
        "appjail_inventree_db_user": "inventree",
        "appjail_inventree_background_workers": 4,
        "appjail_inventree_timezone": "Europe/Amsterdam",
        "appjail_inventree_language": "nl-NL",
        "appjail_inventree_public_url": "http://inventree.example.com:8080",
        "appjail_inventree_extra_environment": [{"name": "INVENTREE_LOG_LEVEL", "value": "WARNING"}],
        "appjail_inventree_platform_ui": True,
        "appjail_inventree_expose": "8080:80",
        "appjail_inventree_tls_expose": "8443:443",
        "appjail_inventree_project_dir": "/usr/local/etc/appjail/projects/inventree",
        "appjail_inventree_volume_root": "/var/appjail-volumes/inventree",
        "appjail_inventree_project": "inventree",
        "appjail_inventree_admin_user": "admin",
        "appjail_inventree_admin_password": "a" * 24,
        "appjail_inventree_admin_email": "admin@example.com",
        "appjail_inventree_secret_key": "s" * 48,
        "appjail_inventree_trusted_origins": "http://inventree.example.com:8080",
        "appjail_inventree_db_password": "d" * 24,
        "appjail_inventree_db_root_password": "r" * 24,
        "appjail_inventree_fqdn": "inventree.example.com",
        "appjail_inventree_tls_certificate_name": "fullchain.pem",
        "appjail_inventree_tls_private_key_name": "privkey.pem",
        "appjail_inventree_tls_redirect_http": True,
        "appjail_inventree_client_max_body_size": "100M",
        "appjail_inventree_gunicorn_workers": 3,
        "appjail_inventree_gunicorn_timeout": 120,
        "appjail_inventree_backup_dir": "/var/backups/inventree",
        "appjail_inventree_backup_dump_command": "mariadb-dump",
        "appjail_inventree_backup_retention_days": 14,
    }

    for tls in (False, True):
        context = dict(base, appjail_inventree_tls_enabled=tls)
        try:
            director_text = render("appjail-director.yml.j2", context)
            director = yaml.load(director_text, Loader=EnvLoader)
            assert set(director["services"]) == {"inventree", "db", "cache", "reverse-proxy"}
            app_service = director["services"]["inventree"]
            assert app_service["makejail"] == (
                "/usr/local/etc/appjail/projects/inventree/inventree-oci.Makejail"
            )
            assert "INVENTREE_ADMIN_PASSWORD" not in app_service.get("environment", [])
            assert {
                "INVENTREE_ADMIN_PASSWORD": "${INVENTREE_ADMIN_PASSWORD}"
            } in app_service["oci"]["environment"]
            assert {
                "INVENTREE_GUNICORN_WORKERS": "3"
            } in app_service["oci"]["environment"]
            db_service = director["services"]["db"]
            assert "arguments" not in db_service
            assert db_service["oci"]["environment"] == [
                {"MARIADB_DATABASE": "inventree"},
                {"MARIADB_USER": "inventree"},
                {"MARIADB_PASSWORD": "${INVENTREE_DB_PASSWORD}"},
                {"MARIADB_ROOT_PASSWORD": "${INVENTREE_DB_ROOT_PASSWORD}"},
            ]
            assert director["volumes"]["db"]["owner"] == 88
            if tls:
                assert "nginx-tls" in director["volumes"]
            else:
                assert "nginx-tls" not in director["volumes"]

            nginx = render("nginx.conf.j2", context)
            assert nginx.count("{") == nginx.count("}")
            assert "proxy_pass http://$endpoint;" in nginx
            assert ("listen 443 ssl;" in nginx) is tls

            env_text = render("env.j2", context)
            env_values = {}
            for line in env_text.splitlines():
                if line and not line.startswith("#"):
                    key, value = line.split("=", 1)
                    env_values[key] = json.loads(value)
            assert env_values["INVENTREE_DB_PASSWORD"] == "d" * 24
            assert env_values["EXTRA_INVENTREE_LOG_LEVEL"] == "WARNING"

            makejail = render("inventree-oci.Makejail.j2", context)
            assert "ARG inventree_from=ghcr.io/pvanoord/inventree-freebsd" in makejail
            assert "ARG inventree_tag=15.1" in makejail
            render("appjail.conf.j2", context)
            render("resolv.conf.j2", context)
            backup = render("backup-inventree.sh.j2", context)
            assert backup.startswith("#!/bin/sh\n")
            assert "set -eu" in backup
            with tempfile.NamedTemporaryFile(mode="w", suffix=".sh") as handle:
                handle.write(backup)
                handle.flush()
                subprocess.run(
                    ["/bin/sh", "-n", handle.name],
                    check=True,
                    capture_output=True,
                    text=True,
                )
        except Exception as exc:  # noqa: BLE001
            errors.append(f"Template validation (TLS={tls}) failed: {exc}")

    required = {
        "defaults/main.yml",
        "tasks/main.yml",
        "handlers/main.yml",
        "meta/main.yml",
        "templates/appjail-director.yml.j2",
        "templates/inventree-oci.Makejail.j2",
        "image/Containerfile",
        "image/entrypoint.sh",
        "image/run-web.sh",
        "image/run-worker.sh",
        ".daemonless/config.yaml",
        ".github/workflows/build-inventree-image.yml",
        "ansible.cfg",
        "inventory.ini",
        "playbook.yml",
        "README.md",
    }
    present = {str(path.relative_to(ROOT)) for path in ROOT.rglob("*") if path.is_file()}
    missing = required - present
    if missing:
        errors.append(f"Required role files missing: {sorted(missing)}")

    workflow = (ROOT / ".github/workflows/build-inventree-image.yml").read_text(
        encoding="utf-8"
    )
    if '.daemonless/config.yaml' not in workflow:
        errors.append("Image workflow must rebuild when .daemonless/config.yaml changes")
    if "cd /tmp/inventree-freebsd" not in workflow:
        errors.append("Image workflow must build from the inventree-freebsd directory")
    if "arch: x86-64" in workflow:
        errors.append("Image workflow must use the FreeBSD VM action's default x86_64 architecture")
    if "mkdir -p /var/cache/dbuild/pkgcache0" not in workflow:
        errors.append("Image workflow must create the dbuild package cache mount")

    if errors:
        print("\n".join(f"ERROR: {error}" for error in errors), file=sys.stderr)
        return 1
    print("Role validation passed: YAML, Jinja rendering, Director model, env, Nginx and OCI image.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

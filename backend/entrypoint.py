#!/usr/bin/env python
"""Railway / Docker entrypoint: verify DB env, migrate, collectstatic, then gunicorn."""
import os
import sys
import time
import subprocess
from urllib.parse import urlparse, unquote


def _db_params():
    url = (
        os.getenv("MYSQL_URL")
        or os.getenv("DATABASE_URL")
        or os.getenv("MYSQL_PRIVATE_URL")
        or ""
    ).strip()
    if url.startswith("mysql"):
        parsed = urlparse(url)
        return {
            "host": parsed.hostname or "127.0.0.1",
            "user": unquote(parsed.username or ""),
            "password": unquote(parsed.password or ""),
            "database": (parsed.path or "/").lstrip("/") or "railway",
            "port": int(parsed.port or 3306),
        }
    return {
        "host": (
            os.getenv("MYSQLHOST")
            or os.getenv("MYSQL_HOST")
            or os.getenv("DB_HOST")
            or "127.0.0.1"
        ),
        "user": (
            os.getenv("MYSQLUSER")
            or os.getenv("MYSQL_USER")
            or os.getenv("DB_USER")
            or "root"
        ),
        "password": (
            os.getenv("MYSQLPASSWORD")
            or os.getenv("MYSQL_PASSWORD")
            or os.getenv("DB_PASSWORD")
            or ""
        ),
        "database": (
            os.getenv("MYSQLDATABASE")
            or os.getenv("MYSQL_DATABASE")
            or os.getenv("DB_NAME")
            or "railway"
        ),
        "port": int(
            os.getenv("MYSQLPORT")
            or os.getenv("MYSQL_PORT")
            or os.getenv("DB_PORT")
            or "3306"
        ),
    }


def main():
    params = _db_params()
    host = params["host"]
    print(f"[yekola] DB host = {host}", flush=True)

    if host in ("127.0.0.1", "localhost"):
        print(
            "[yekola] ERROR: MySQL Railway n'est pas lie a ce service.\n"
            "1) Clique service yekola -> Variables\n"
            "2) Add Variable -> Variable Reference\n"
            "3) Choisis MySQL puis ajoute MYSQL_URL (ou MYSQLHOST, MYSQLPORT, "
            "MYSQLUSER, MYSQLPASSWORD, MYSQLDATABASE)\n"
            "4) Deploy / Redeploy",
            flush=True,
        )
        sys.exit(1)

    import pymysql

    for attempt in range(1, 31):
        try:
            pymysql.connect(
                host=params["host"],
                user=params["user"],
                password=params["password"],
                database=params["database"],
                port=params["port"],
                connect_timeout=5,
            ).close()
            print(f"[yekola] MySQL OK (tentative {attempt})", flush=True)
            break
        except Exception as exc:
            print(f"[yekola] Attente MySQL ({attempt}/30): {exc}", flush=True)
            time.sleep(2)
    else:
        print("[yekola] ERROR: impossible de joindre MySQL apres 60s", flush=True)
        sys.exit(1)

    subprocess.check_call([sys.executable, "manage.py", "migrate", "--noinput"])
    subprocess.check_call([sys.executable, "manage.py", "collectstatic", "--noinput"])

    # Remplit la DB vide (Railway) — désactiver avec BOOTSTRAP_SEED=0
    bootstrap = os.getenv("BOOTSTRAP_SEED", "1").strip().lower()
    if bootstrap in ("1", "true", "yes", "on"):
        print("[yekola] Bootstrap seed si base vide…", flush=True)
        subprocess.check_call([sys.executable, "manage.py", "bootstrap_railway"])

    port = os.getenv("PORT", "8080")
    os.execvp(
        "gunicorn",
        [
            "gunicorn",
            "core.wsgi:application",
            "--bind",
            f"0.0.0.0:{port}",
            "--workers",
            "2",
            "--timeout",
            "120",
        ],
    )


if __name__ == "__main__":
    main()

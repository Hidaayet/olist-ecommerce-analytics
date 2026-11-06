"""
Shared configuration.

The database URL is read, in this order, from:
  1. the DATABASE_URL environment variable
  2. a `.env` file in the repo root  (copy .env.example to .env and edit it)
  3. a local default (postgresql://postgres:postgres@localhost:5432/olist)

Using a .env file avoids shell-specific syntax ($env:... in PowerShell, export in bash)
and keeps your password out of the code and out of git (.env is git-ignored).
"""
from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_URL = "postgresql://postgres:postgres@localhost:5432/olist"


def load_env(path: Path | None = None) -> None:
    """Minimal .env reader: KEY=VALUE lines, '#' comments, optional quotes.
    Real environment variables always win over the file."""
    path = path or REPO_ROOT / ".env"
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))


def database_url() -> str:
    load_env()
    return os.environ.get("DATABASE_URL", DEFAULT_URL)

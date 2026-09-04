"""
run_seed.py -- Single seeding entry point for the BlackLine Journal Certification pilot.

This is the ONLY seeding entry point per CLAUDE.md rule 3. All seed data lives in
SQL files (backend/seed/NN_*.sql). No Python seed scripts exist or are used.

Usage (run from backend/):
    python seed/run_seed.py                     # seed only
    python seed/run_seed.py --schema            # apply schema.sql + indexes.sql first
    python seed/run_seed.py --database mydb     # target a different database

The script discovers every backend/seed/NN_*.sql file automatically, sorted by
leading integer. A new NN_*.sql file is picked up without editing this script.

Environment:
    DATABASE_URL  -- asyncpg-compatible DSN. Defaults to the local dev DB.
                     postgresql+asyncpg:// is rewritten to postgresql:// automatically.
"""

import argparse
import asyncio
import os
import re
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SEED_DIR = Path(__file__).parent.resolve()
SQL_DIR = SEED_DIR.parent / "sql"

_DEFAULT_URL = (
    "postgresql://postgres:ShankLuffy%5E1015r@localhost:5432/baxter_journal_certification"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _db_url(database: str | None) -> str:
    """Return the asyncpg DSN, optionally overriding the database name."""
    url = os.environ.get("DATABASE_URL", _DEFAULT_URL)
    url = url.replace("postgresql+asyncpg://", "postgresql://")
    if database:
        # Replace the database portion at the end of the URL path.
        url = re.sub(r"(/[^/?#]*)(\?.*)?$", f"/{database}\\2", url)
    return url


def _numeric_prefix(path: Path) -> int:
    """Return the leading integer from a filename, e.g. 14 from '14_test_journals.sql'."""
    m = re.match(r"^(\d+)", path.stem)
    return int(m.group(1)) if m else 0


def _discover_seeds() -> list[Path]:
    """Return all NN_*.sql files in SEED_DIR, sorted by numeric prefix."""
    files = [p for p in SEED_DIR.glob("*.sql") if re.match(r"^\d+", p.name)]
    return sorted(files, key=_numeric_prefix)


def _split_sql_with_lines(sql_text: str) -> list[tuple[str, int]]:
    """
    Split SQL text into (statement, start_line) pairs.

    Respects single-quoted strings, dollar-quoted strings ($$...$$, $tag$...$tag$),
    and -- line comments. Skips statements that are comment-only after stripping.
    """
    results: list[tuple[str, int]] = []
    current: list[str] = []
    stmt_start_line = 1
    current_line = 1
    in_quote = False
    in_line_comment = False
    in_dollar_quote = False
    dollar_tag = ""
    i = 0

    while i < len(sql_text):
        ch = sql_text[i]

        # ── line comment ──────────────────────────────────────────────────────
        if in_line_comment:
            current.append(ch)
            if ch == "\n":
                in_line_comment = False
                current_line += 1
            i += 1
            continue

        if ch == "\n":
            current_line += 1

        # ── dollar-quoted string body (e.g. $$ ... $$ or $body$ ... $body$) ──
        if in_dollar_quote:
            tag_len = len(dollar_tag)
            if sql_text[i : i + tag_len] == dollar_tag:
                # Found the closing tag; consume it whole and exit dollar-quote.
                current.append(dollar_tag)
                i += tag_len
                in_dollar_quote = False
                dollar_tag = ""
            else:
                current.append(ch)
                i += 1
            continue

        # ── dollar-quote open tag ─────────────────────────────────────────────
        if ch == "$" and not in_quote:
            j = i + 1
            while j < len(sql_text) and (sql_text[j].isalnum() or sql_text[j] == "_"):
                j += 1
            if j < len(sql_text) and sql_text[j] == "$":
                tag = sql_text[i : j + 1]
                current.append(tag)
                dollar_tag = tag
                in_dollar_quote = True
                i = j + 1
                continue

        # ── line comment open ─────────────────────────────────────────────────
        if ch == "-" and not in_quote and i + 1 < len(sql_text) and sql_text[i + 1] == "-":
            in_line_comment = True
            current.append(ch)
            i += 1
            continue

        # ── single-quoted string ──────────────────────────────────────────────
        if ch == "'" and not in_quote:
            in_quote = True
            current.append(ch)
        elif ch == "'" and in_quote:
            if i + 1 < len(sql_text) and sql_text[i + 1] == "'":
                current.append("''")
                i += 2
                continue
            in_quote = False
            current.append(ch)
        # ── statement separator ───────────────────────────────────────────────
        elif ch == ";" and not in_quote:
            stmt = "".join(current).strip()
            non_comment = "\n".join(
                ln for ln in stmt.splitlines()
                if ln.strip() and not ln.strip().startswith("--")
            ).strip()
            if non_comment:
                results.append((non_comment, stmt_start_line))
            current = []
            stmt_start_line = current_line + (1 if ch == "\n" else 0)
        else:
            current.append(ch)

        i += 1

    # Trailing statement without semicolon
    stmt = "".join(current).strip()
    non_comment = "\n".join(
        ln for ln in stmt.splitlines()
        if ln.strip() and not ln.strip().startswith("--")
    ).strip()
    if non_comment:
        results.append((non_comment, stmt_start_line))

    return results


# ---------------------------------------------------------------------------
# Core runner
# ---------------------------------------------------------------------------

async def _run_sql_file(path: Path, conn) -> int:
    """
    Execute a SQL file via an open asyncpg connection.

    Returns the number of statements executed. Raises on the first failure,
    annotating the exception with the file path and statement line number.
    """
    sql_text = path.read_text(encoding="utf-8")
    statements = _split_sql_with_lines(sql_text)
    count = 0
    for stmt, line_no in statements:
        try:
            await conn.execute(stmt)
            count += 1
        except Exception as exc:
            raise RuntimeError(
                f"File: {path.name}  line ~{line_no}\n"
                f"Statement: {stmt[:200]}{'...' if len(stmt) > 200 else ''}\n"
                f"DB error: {exc}"
            ) from exc
    return count


async def _apply_file(path: Path, db_url: str) -> tuple[int, float]:
    """Open a fresh connection, run one file, return (statements, elapsed_s)."""
    import asyncpg
    t0 = time.monotonic()
    conn = await asyncpg.connect(db_url)
    try:
        count = await _run_sql_file(path, conn)
    finally:
        await conn.close()
    return count, time.monotonic() - t0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Seed the BlackLine journal_certification database from SQL files."
    )
    parser.add_argument(
        "--schema",
        action="store_true",
        help="Apply backend/sql/schema.sql then backend/sql/indexes.sql before seeds.",
    )
    parser.add_argument(
        "--database",
        metavar="NAME",
        default=None,
        help="Override the database name in the connection URL.",
    )
    args = parser.parse_args()

    db_url = _db_url(args.database)
    print(f"Target: {db_url}\n")

    plan: list[Path] = []

    if args.schema:
        for name in ("schema.sql", "indexes.sql"):
            p = SQL_DIR / name
            if not p.exists():
                print(f"ERROR: --schema requested but {p} not found.")
                sys.exit(1)
            plan.append(p)

    seeds = _discover_seeds()
    if not seeds:
        print("ERROR: No NN_*.sql files found in", SEED_DIR)
        sys.exit(1)

    plan.extend(seeds)

    print("Execution plan:")
    for p in plan:
        print(f"  {p.name}")
    print()

    total_stmts = 0
    for p in plan:
        try:
            stmts, elapsed = asyncio.run(_apply_file(p, db_url))
        except RuntimeError as exc:
            print(f"\nFAILED: {exc}")
            sys.exit(1)
        except Exception as exc:
            print(f"\nFAILED (unexpected): {p.name}: {exc}")
            sys.exit(1)
        total_stmts += stmts
        print(f"  OK  {p.name:<45}  {stmts:>5} stmt  {elapsed:.2f}s")

    print(f"\nDone. {len(plan)} files, {total_stmts} statements.")


if __name__ == "__main__":
    main()

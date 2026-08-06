# Changelog

All notable changes to lua_SQLBuilder are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).
This project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Full CI matrix: Lua 5.1/5.2/5.3/5.4/LuaJIT against real SQLite, MySQL 8 and PostgreSQL 16
  (busted for unit/audit/production, zero-dependency runner for LuaJIT).
- Cross-audit invariants (`spec/audit`): determinism, idempotency, no caller-table
  mutation, placeholder/param alignment, escaping round-trip, across every builder × dialect.
- Injection regression suite (`spec/integration/injection_spec.lua`) on real databases.
- Production-usage regression suite derived from fireBookStore-backend call shapes.

### Changed

- Dialect layer (`lua_SQLBuilder/dialect.lua`): identifier quoting, JSON path operators
  (incl. PostgreSQL operator-chain translation) and upsert rendering per dialect;
  per-instance `{ dialect = ... }` options plus `set_default_dialect()`.
- LIMIT renders the portable `LIMIT n OFFSET m` form (was MySQL-only comma syntax).
- Deterministic output: QUERY / SET / DATA / ON_DUPLICATE keys are sorted.
- Unified parameter pipeline: `?` count must match params (errors on mismatch);
  table params expand for IN clauses; `false`/`0` are valid parameter values.
- Dialect-aware string escaping for inline (`to_sql`) values: MySQL backslash style,
  PostgreSQL/SQLite single-quote doubling.
- HAVING parameters now participate in `to_prepare`.
- `%` in string parameters no longer crashes inline rendering (gsub function replacement).
- `quote_to_str` fixed for Lua 5.1 (NUL byte in gsub pattern).
- Removed stale `__SqlBuilder__*.lua` copies (broken require paths).

### Fixed

- A1 UPDATE string-mode prepare double placeholder; A3 JSON boolean garbage SQL;
  A4 boolean QUERY `'true'` strings; A5 falsy params rendering literal `?`;
  A6 DESC without ORDER_BY crash; A10 DATA double-call column misalignment;
  A19 WHERE table-param mutation; A21 multi-param WHERE; ORDER_BY two-arg; PAGE(0).

## [0.1.0] - 2021

Initial release: basic SQLBuilder with WHERE / OR / ORDER BY / GROUP BY /
HAVING / LIMIT / FOR UPDATE / PROCEDURE and SELECT / UPDATE / INSERT / DELETE
helpers (MySQL-flavored SQL only).

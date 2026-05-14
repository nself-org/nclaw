# Database Schema Versioning — nClaw

## Overview

nClaw uses semantic versioning for its local database schema. The version number is stored in the `migrations` table and checked on every app start. The app runs pending migrations automatically if the schema version is below the current version.

## Schema Version Storage

| Table | Column | Type | Notes |
|-------|--------|------|-------|
| `migrations` | `version` | `INTEGER PRIMARY KEY` | Monotonic version number; never decremented |
| `migrations` | `name` | `VARCHAR` | Human-readable migration name (e.g., `initial_schema`, `indexes_v1`) |
| `migrations` | `applied_at` | `TIMESTAMP` | UTC timestamp when migration was applied |

The `migrations` table is created as part of the initial schema (v1).

## Backwards Compatibility

nClaw **never drops columns** in the schema. The following are the only supported schema changes:

1. **ADD COLUMN** — adds a new nullable column (with default if required)
2. **ADD INDEX** — improves query performance without data modification
3. **CREATE TABLE** — introduces a new entity type
4. **RENAME COLUMN** — uses a two-version sequence:
   - v1: Add new column + data; keep old column
   - v2: Update app code to read new column; drop old column
   - Result: old app versions continue reading old column, new apps read new column

The `migrations` table itself is immutable — once a migration is recorded at version N, it is never re-applied.

## Forward Compatibility

nClaw refuses to start if the app's schema version is **lower** than the `migrations` table version. This prevents data loss from downgrade.

**User-facing error:**
```
Could not initialize database:
  Installed schema v2 but app only supports up to v1.
  Please update nClaw to the latest version.
```

## Version Naming Convention

- **v1:** Initial schema shipped with nClaw v1.0.0 (P93). Includes tables: `np_accounts`, `np_topics`, `np_messages`, `np_memories`, `np_vectors`, `device_meta`.
- **v2 (planned):** Adds scope isolation (`source_account_id` column) to all `np_*` tables. Shipped with nClaw v1.1.0.
- **v3+:** Reserved for future versions.

## Backup / Restore Versioning

Backups use JSONL format with a schema-version header line:

```jsonl
{"_metadata": {"schema_version": 1, "timestamp": "2026-05-14T10:30:00Z"}}
{"table": "np_topics", "row": {"id": "xyz", ...}}
{"table": "np_messages", "row": {"id": "abc", ...}}
```

When restoring from a backup with `schema_version < current`:
1. Restore records into the current schema as-is
2. Any missing columns get NULL or default values
3. Migrations are NOT re-run on restore

When restoring from a backup with `schema_version > current`:
1. Error: "Backup was created with a newer nClaw version"
2. User must upgrade before restore

## Runtime Checks

**On app start:**
```rust
let current_version = db.current_schema_version()?;
if current_version < LATEST_SCHEMA_VERSION {
    migrate::run(&mut db)?;  // applies all pending migrations
}
if current_version > LATEST_SCHEMA_VERSION {
    return Err(DbError::SchemaTooNew);
}
```

## Adding a New Migration

1. Create `migrations/{NNNN}_description.sql` and `migrations/{NNNN}_description.sqlite.sql`
2. Add a new `Migration` entry to `db/migrate.rs` with `version: N+1`
3. Verify both SQL variants work against the schema
4. Bump the app version minor (`1.0.x` → `1.1.0`)
5. Document the changes in this file under "Version Naming Convention"
6. PR must include a CHANGELOG entry explaining what changed for end users

## Testing

Every migration is smoke-tested in `tests/migrate_smoke.rs`:
```rust
#[test]
fn test_migrate_v1_to_v2() {
    let mut db = open_test_db(Engine::Sqlite, SchemaVersion::V1)?;
    assert_eq!(db.current_version(), 1);
    migrate::run(&mut db)?;
    assert_eq!(db.current_version(), 2);
}
```

## FAQs

**Q: Can I downgrade nClaw and keep my data?**  
A: No. Once you upgrade to v1.1.0, your schema is v2. A v1.0.0 app cannot read it. Always back up before upgrading.

**Q: What if a migration fails?**  
A: The app will not start. Check the error log, fix the issue, and try again. If the database is corrupted, restore from backup.

**Q: Can I manually edit the `migrations` table?**  
A: No. The app relies on the `migrations` table being the source of truth. Hand-editing it can break the app.

**Q: Does nClaw support multiple schema versions running simultaneously?**  
A: No. All clients must be at the same schema version. Multi-device sync is not supported in v1.

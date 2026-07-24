# Dayi Licensed Integration Contract

PULSE does not bundle Dayi roots or codes without written authorization. The input
method becomes visible only when `dayi.sqlite` passes the runtime license and schema
checks below.

## Required authorization

- Written permission covering iOS distribution and App Store distribution.
- Licensor name and a traceable agreement/reference ID.
- Confirmation whether the licensed package is Dayi 3-code, 4-code, phrase edition,
  Hong Kong character edition, or another defined edition.
- Permission to display the 40 key-root labels in the keyboard UI and candidate info.

## SQLite schema version 1

```sql
CREATE TABLE dayi_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE dayi_key_labels (
    key TEXT PRIMARY KEY,
    root_label TEXT NOT NULL
);

CREATE TABLE dayi_entries (
    code TEXT NOT NULL,
    text TEXT NOT NULL,
    weight INTEGER NOT NULL DEFAULT 0,
    kind INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (code, text)
);

CREATE INDEX idx_dayi_entries_code_weight
ON dayi_entries(code, weight DESC);
```

Required metadata:

```text
schema_version=1
authorization=licensed
layout=dayi40
licensor=<legal entity>
license_reference=<agreement/reference ID>
edition=<licensed edition name>
```

`dayi_key_labels` must contain the complete authorized Dayi 40-key label set.
`dayi_entries` may contain single characters and phrases; `kind` is `0` for a single
character and `1` for a phrase. PULSE treats the database as read-only.

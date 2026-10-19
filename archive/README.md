# Archive

Retired material lives here with provenance and a reason for its status. This folder
is outside the Godot project. Source/data archives are tracked; large local release
archives and player saves/logs under `local/` are ignored and stay on this machine.

| Location | Contents |
|---|---|
| [legacy-recipes](legacy-recipes/README.md) | Retired recipe generators, competing CSV generations and their historical balance proposal/report |
| [scene-recovery](scene-recovery/README.md) | A tracked May editor recovery scene, preserved outside runtime scenes |
| `manifest.json` | Source commit/path/hash, archived path/hash, and removed generated-import records |
| `local/2026-10-19/` | Local old exports, with a separate per-file hash manifest and restore instructions |

Verify tracked archives from the repository root:

```sh
python3 tools/maintenance/check_archive.py
```

Use the [lifecycle index](../docs/project-lifecycle.md) to locate current guidance and
retained future work. Archiving is not permission to reactivate an old generator or
apply historical balance values. Restore source from the archive only into a scratch
directory, or recover its original version from the recorded Git commit for analysis.

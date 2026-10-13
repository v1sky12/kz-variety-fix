# kz_variety_fix installer

The package contains one Roblox place file. The installer validates the ZIP and RBXL header, makes a timestamped backup, and copies the place atomically through a temporary file.

```bash
python3 install_kz_variety_fix.py install kz_variety_fix_updated.zip ./kz_variety_fix.rbxl
```

Rollback to a backup created by the installer:

```bash
python3 install_kz_variety_fix.py rollback ./kz_variety_fix.rbxl.backup-YYYYMMDDTHHMMSSZ ./kz_variety_fix.rbxl
```

Keep `KZBrush_V1` and the V5 backup inside the place. The active controller mutex prevents two movement controllers from running at once. Test in a copy of the Roblox place before publishing.

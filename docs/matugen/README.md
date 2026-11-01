# Matugen colors on Linux

In **Settings → Look & feel → Appearance**, select **Matugen**. Riflay automatically reads the first generated file it finds:

- `$XDG_CONFIG_HOME/riflay/matugen.json` (normally `~/.config/riflay/matugen.json`)
- `$XDG_CACHE_HOME/matugen/colors.json`
- `$XDG_CACHE_HOME/ryoku/colors.json` (Ryoku desktops)

**Choose file** follows another JSON file. Colors update while Riflay is open, including when Matugen replaces the file atomically. Incomplete writes keep the last working colors. No wallpaper commands run from Riflay.

For other Matugen setups, copy [riflay.json](riflay.json) to `~/.config/matugen/templates/riflay.json`, then add this template to your Matugen config:

```toml
[templates.riflay]
input_path = '~/.config/matugen/templates/riflay.json'
output_path = '~/.config/riflay/matugen.json'
```

Run your usual Matugen wallpaper/color command. The template exports both dark and light schemes; Riflay's Mode setting chooses which to display. Flat templates use the brightness of their generated colors. Surface, text, primary, secondary, tertiary, outline and error roles apply to the app and Material components.

Riflay also reads Matugen's `--json hex` output, old mode-first JSON, and flat camelCase color files. Matugen's [template syntax](https://github.com/InioX/matugen/wiki/Templates) and [configuration](https://github.com/InioX/matugen/wiki/Configuration) describe the upstream formats.

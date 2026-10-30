# Dark Fantasy HUD: FREE sample

A small taste of the full pack: **one resource orb set**, **one health bar** and the **wide menu button in all five states** (normal, hover, pressed, disabled, focused), in both colour themes (Iron and Crimson, Obsidian and Azure).

Contents: 32 SVG and 96 PNG (1x, 2x, 3x), `nine_slice.json` for the bar and the button, the cover image and the license.
- Orb (128 x 128): `orb_back`, `orb_fill_health`, `orb_glass`, `orb_socket`, `orb_over` (glass and socket in one), `orb_empty`, `orb_health_pct_50`. Stack them back, fill, glass, socket. For a liquid level in Godot use a TextureProgressBar (Bottom to Top) with min_value -16.667 and max_value 116.667, then value 0 to 100 is the level.
- Bar (256 x 32): `bar_frame`, `bar_track`, `bar_fill_health` on one shared canvas, plus a finished 50 % bar. 3-slice margins 24 left and right; for a TextureProgressBar set min_value -11.538 and max_value 111.538, then value 0 to 100 is the fill.
- Menu button: `menu_button_wide_<state>` (256 x 48), 3-slice with 24 px margins.

**Get the full pack** (170 elements per theme, action bar, unit frames, minimaps, panels, 16 icons, recolour tool, Godot demo): https://stationsupply.itch.io/dark-fantasy-hud

All graphics are hand-coded SVG vectors; no AI image generation was used. The SVG code was written with an AI assistant. License: see LICENSE (commercial use in your games is fine, no resale or redistribution).

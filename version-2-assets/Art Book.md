# FIGHT BACK — ART BIBLE

**Version 1.0 | Visual Production Standard**

*An original Nigerian-inspired fighting game.*

## 02. Official colour system

### Brand colours

| Colour         | Hex code  | Usage                       |
| -------------- | --------- | --------------------------- |
| Fight Back Red | `#B52A27` | Logo, emphasis, accents     |
| Charcoal Black | `#171923` | Main UI backgrounds         |
| Dark Slate     | `#252C3A` | Panels and buttons          |
| Antique Gold   | `#C99A45` | Borders and highlights      |
| Bright Gold    | `#F0C66D` | Selected elements           |
| Warm Ivory     | `#F1E8D7` | Text and highlights         |
| Nigerian Green | `#167447` | Occasional cultural accents |
| Bronze         | `#98603C` | Decorative elements         |

### Colour rules

- Red is our main brand accent.
- Gold communicates importance and prestige.
- Charcoal provides contrast and depth.
- Green should be used sparingly.
- White and ivory should maintain text readability.

Do not make every screen green, white and green. Nigerian identity should come from the complete art direction, not simply the flag colours.

## 03. Character art direction

Characters are among the most important assets in Fight Back.

### Official illustration style

Every fighter should follow these rules:

1. High-detail digital illustration.
2. Strong, recognisable body silhouettes.
3. Anatomically believable proportions.
4. Expressive faces and distinctive personalities.
5. Clean, controlled outlines.
6. Rich painted shadows and highlights.
7. Carefully designed clothing and accessories.
8. Strong colour separation between body, clothing and background.
9. Consistent lighting and rendering quality.
10. Original costume designs and character identities.

### Character proportions

Our reference target at a 1920 × 1080 gameplay resolution:

- Standing character height: approximately 580–700 pixels.
- Characters should have consistent perceived scale.
- Feet must share the same ground baseline when standing at the same depth.
- Preserve each fighter's natural body proportions.
- Keep enough space around the body for attacks and effects.

These are initial targets. Actual proportions will be finalised after testing the first playable fighters.

### Character appearance

Each fighter must have:

- A recognisable face.
- A distinctive hairstyle or headwear.
- A unique costume silhouette.
- A distinctive primary colour palette.
- Recognisable fighting equipment or accessories where appropriate.
- A unique fighting stance.

Do not give every fighter identical clothing, jewellery or accessories.

### Character production requirements

Each character eventually needs:

| Animation      | Requirement                    |
| -------------- | ------------------------------ |
| Idle           | Breathing and stance movement  |
| Walk forward   | Movement towards opponent      |
| Walk backward  | Defensive movement             |
| Crouch         | Low defensive stance           |
| Jump           | Take-off, airborne and landing |
| Light attack   | Fast basic attack              |
| Heavy attack   | Stronger attack                |
| Special attack | Character-specific ability     |
| Block          | Defensive animation            |
| Hit reaction   | Receiving damage               |
| Knockdown      | Falling to the ground          |
| Get-up         | Returning to combat            |
| Victory        | Winning animation              |
| Defeat         | Losing animation               |

**Important:** A beautiful full-body AI-generated character concept is not automatically a usable game sprite. Production animations must maintain the same face, clothing, proportions, accessories and visual identity across frames.

## 04. Environment and arena direction

Fight Back's environments should be inspired by Nigeria.

We want players to recognise the world without making every arena look the same.

### Environment categories

Potential arenas include:

- National Theatre, Lagos.
- Traditional Nigerian palace courtyard.
- Lagos urban street.
- Coastal Nigerian environment.
- Traditional village settlement.
- Nigerian festival-inspired arena.
- Modern African city environment.

Each location should have its own atmosphere, lighting, architecture and colour identity.

### Environment illustration style

- Detailed hand-painted digital backgrounds.
- Strong architectural composition.
- Natural environmental lighting.
- Rich textures.
- Cinematic depth.
- Carefully controlled perspective.
- Clear gameplay visibility.

### Background layer structure

Every arena should be designed using separate 2D layers.

| Layer | Asset                                 |
| ----- | ------------------------------------- |
| 01    | Sky and clouds                        |
| 02    | Distant skyline and vegetation        |
| 03    | Main architectural landmark           |
| 04    | Cultural decorations and side scenery |
| 05    | Fighting floor                        |

All layers should align on the same canvas.

Transparent layers must use genuine alpha transparency, not a simulated checkerboard.

### Background dimensions

**Master stage artwork:**

- 2560 × 1080 pixels.
- 21:9 aspect ratio.
- PNG format.
- Consistent dimensions across all layers.

**Gameplay viewport:**

- 1920 × 1080 pixels.
- 16:9 aspect ratio.

The wider environment provides additional scenery outside the initial camera view.

Keep important architectural features within the central 1920-pixel safe region. The additional 320 pixels on each side can provide scenery for camera movement.

### Fighting floor

The fighting floor must:

- Extend across the full stage width.
- Have a clear, uninterrupted combat area.
- Maintain a consistent horizontal ground baseline.
- Have enough visual depth to accommodate jumping and crouching.
- Avoid foreground objects that obscure fighter feet.
- Avoid excessive floor decorations beneath the characters.

The gameplay collision ground must be separate from the decorative floor artwork.

## 05. Lighting and atmosphere

Lighting must be consistent throughout the game.

### Character lighting

- Clear primary light source.
- Warm highlights where appropriate.
- Defined shadows.
- Strong separation from the background.
- Consistent lighting direction across animation frames.

### Environment lighting

Each arena can have its own lighting atmosphere.

Examples:

| Arena              | Lighting                       |
| ------------------ | ------------------------------ |
| National Theatre   | Warm afternoon sunlight        |
| Traditional palace | Golden evening lighting        |
| Lagos street       | Bright urban daylight          |
| Coastal arena      | Warm sunset                    |
| Festival arena     | Colourful evening illumination |

### Effects

Combat effects should be readable without overwhelming the characters.

Use:

- Impact flashes.
- Motion trails.
- Dust effects.
- Hit sparks.
- Ground impact effects.
- Character-specific special attack effects.

Red, gold and ivory can form the core impact-effect palette. Individual fighters may have distinctive effect colours.

## 06. User interface design

The UI should feel like a premium fighting game.

### Main menu

Preserve the existing Fight Back logo.

Our main menu should have:

- A Nigerian-inspired cinematic background.
- Prominent logo placement.
- Clearly readable menu options.
- Consistent button dimensions.
- Gold borders and dark surfaces.
- Subtle red highlights.
- Smooth menu transitions.

### Button design

Normal state:

- Dark charcoal surface.
- Gold outline.
- Ivory text.

Hover state:

- Brighter gold border.
- Slightly brighter surface.
- Subtle glow.

Selected state:

- Distinct red or gold accent.
- Clear visual indication.

Pressed state:

- Brief visual compression.
- Appropriate click sound.

### Main menu options

1. Versus / Multiplayer
2. Tournament (if implemented)
3. How to Play
4. Settings
5. Quit

Only display features that are actually implemented.

### Other interface screens

The same visual language must extend to:

- Character selection.
- Stage selection.
- Gameplay HUD.
- Pause menu.
- Audio settings.
- Controls settings.
- Victory screen.
- Defeat screen.
- Loading screen.

### Typography

Use two complementary font styles:

**Display typography:** Bold, condensed and impactful for headings and fighter names.

**Interface typography:** Clean, readable sans-serif for buttons, descriptions and statistics.

Potential fonts to evaluate include Rajdhani, Oswald and Inter. Check their licences before distribution.

Avoid excessive fonts, decorative lettering and difficult-to-read text.

## 07. Gameplay HUD

The gameplay HUD must prioritise readability.

Essential elements:

- Player 1 name.
- Player 2 name.
- Player 1 health bar.
- Player 2 health bar.
- Round timer.
- Round indicators.
- Special meter, if implemented.
- Combo counter, if implemented.
- Victory announcement.

Health bars should be symmetrical.

Player information must remain visible without covering important combat animations.

The HUD should use the established charcoal, red, gold and ivory palette.

## 08. Technical asset specifications

These are our starting production standards.

| Asset                  | Recommended specification                      |
| ---------------------- | ---------------------------------------------- |
| Main menu              | 1920 × 1080                                    |
| Character concept art  | 1024 × 1536                                    |
| Animation frame canvas | 768 × 1024                                     |
| Stage master artwork   | 2560 × 1080                                    |
| Stage layers           | 2560 × 1080                                    |
| Character portraits    | 1024 × 1024                                    |
| UI icons               | 256 × 256                                      |
| Button artwork         | Vector or high-resolution PNG                  |
| Logo                   | SVG where available, otherwise transparent PNG |

### File formats

- PNG RGBA for transparent character artwork.
- PNG RGB or RGBA for backgrounds.
- SVG for scalable logos and suitable UI graphics.
- WAV or OGG for audio.
- Godot-compatible sprite atlases for animation.

Keep original source artwork separate from optimised game assets.

### Godot rendering

Fight Back is a 2D game.

Our production approach:

- Use 2D sprites.
- Use AnimatedSprite2D or Sprite2D where appropriate.
- Use AnimationPlayer for animation and UI transitions.
- Use CollisionShape2D for fighter collision and attack areas.
- Use Parallax2D for suitable background movement.
- Use Camera2D for the gameplay camera.

Use smooth texture filtering for painted illustrations. Do not use pixel-art nearest-neighbour filtering.

Keep visual ground placement separate from collision logic.

## 09. Animation and movement standards

Movement must feel responsive and readable.

Characters should have:

- Clear anticipation before powerful attacks.
- Distinct attack poses.
- Proper recovery animations.
- Consistent foot placement.
- Smooth transitions between idle, movement and combat.
- Readable hit reactions.

Do not rely on moving a static character image around the screen to represent every action.

The animation must communicate the actual movement and impact.

## 10. AI image generation rules

AI generators may be used for concept development, environments, props and selected artwork.

However, every generation must follow our visual identity.

### General rules

- Use reference images from approved Fight Back artwork.
- Maintain the established character appearance.
- Maintain the established lighting style.
- Specify exact image dimensions and aspect ratio.
- Request transparent backgrounds when needed.
- Avoid unnecessary text in generated artwork.
- Never let AI redesign the official logo without approval.
- Inspect all generated assets before importing them into Godot.

### Standard prompt direction

Include this instruction when generating new artwork:

"Create artwork for Fight Back, an original Nigerian-inspired 2D fighting game. Follow the established Fight Back Art Bible: detailed hand-painted digital illustration, believable anatomy, strong silhouettes, rich controlled shading, cinematic lighting, distinctive Nigerian-inspired visual influences and consistent professional fighting-game art direction. Maintain the established visual identity. Do not imitate existing fighting-game characters, logos or copyrighted designs."

## 11. Asset naming conventions

Use consistent filenames.

Examples:

- `FB_Character_Warrior_Idle_01.png`
- `FB_Character_Female_Walk_01.png`
- `FB_Stage_NationalTheatre_Sky.png`
- `FB_Stage_NationalTheatre_Floor.png`
- `FB_UI_MainMenu_Background.png`
- `FB_UI_Button_Normal.png`
- `FB_UI_Button_Hover.png`
- `FB_UI_HealthBar.png`
- `FB_Logo_Main.png`

Keep filenames descriptive and avoid spaces.

## 12. Quality control checklist

Before approving any asset, check:

- [ ] Does it match the Fight Back art direction?
- [ ] Is the artwork original or properly licensed?
- [ ] Are the dimensions correct?
- [ ] Is the transparency genuine where required?
- [ ] Is the lighting consistent?
- [ ] Is the asset readable at actual gameplay scale?
- [ ] Does it fit the intended game screen?
- [ ] Does it maintain character or environment continuity?
- [ ] Is the asset optimised for Godot?
- [ ] Has it been tested in the actual game?

## 13. Final creative principles

These rules take precedence over individual artistic preferences.

1. Fight Back must have its own recognisable identity.
2. Nigerian cultural inspiration must be authentic and intentional.
3. Character readability takes priority over excessive detail.
4. Gameplay visibility takes priority over decorative scenery.
5. Consistency takes priority over random visual experimentation.
6. Every screen must feel like part of the same game.
7. Every asset must serve a practical purpose.
8. Quality takes priority over quantity.

---

**END OF ART BIBLE — VERSION 1.0**

*Fight Back is built from Nigerian inspiration, original characters and a fighting experience designed to be enjoyed anywhere in the world.*

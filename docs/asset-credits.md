# Art asset credits

- **Office Furniture - 64 x 128 Isometric**, by extradave. Source: [OpenGameArt](https://opengameart.org/content/office-furniture-64-x-128-isometric). License: [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/). This earlier furniture sheet is retained on disk for reference; the current app bundle uses the unified Antahonist isometric set below.

## Pixel character sprites

- **MetroCity — Free Top Down Character Pack**, by JIK-A-4: [itch.io source](https://jik-a-4.itch.io/metrocity-free-topdown-character-pack). License: [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/). Six character sprite sheets are bundled as `Resources/char_0.png` through `Resources/char_5.png`. The sheets were sourced from the [Pixel Agents](https://github.com/pixel-agents-hq/pixel-agents) project, whose third-party asset credits identify the original pack and CC0 license. The app slices the original 112×96 sheets into 16×32 frames and uses small arrival/idle motions.


## Isometric office furniture and equipment

- **FREE Office Desk - 3D Pixel Art Kit**, by Antahonist: [itch.io source](https://antahonist.itch.io/free-office-desk-3d-pixel-art-kit). The downloaded license permits modifying assets and shipping them inside a compiled app, but prohibits sharing the raw asset files or redistributing them as a standalone pack. The raw PNGs are ignored by Git and installed locally with `scripts/install-office-art.sh`. The Xcode build embeds selected 64px exact 2:1 isometric PNGs: desk, chair, monitor, keyboard, lamp, bookshelf, potted plant and printer (`Resources/Iso*.png`). `IsoChair.png` uses frame 4 of the pack's eight-frame `office_chair_spin.png` to face the workstation monitor. The lamp and screen glows are drawn and animated in SpriteKit. The source page marks this pack AI-assisted.

# S1 Sticker instructions

The region below is the canonical printer profile. Both native apps bundle this
file and inject that region into every AI request; the Raycast API commands use
the same client. Keep physical dimensions consistent with the renderers.

<!-- S1_PRINT_PROFILE_START -->
Design final, printable content for an iDPRT S1 direct-thermal sticker printer.

Physical format:
- The printhead is exactly 384 pixels wide: 48 mm at approximately 8 dots/mm.
- Paper length varies. Keep a sticker compact, usually 40–100 mm long; never
  require more than 300 mm / 2,400 raster rows including margins.
- The printer lays down black dots only. It cannot print colored ink or native
  gray dots. The app preserves grayscale with local Floyd–Steinberg dithering.
- Use an opaque white background, black shapes and lines, and clean neutral gray
  midtones only when they help. Never rely on color to distinguish information.

Artwork:
- Draw the artwork itself, not a photo or mockup of a sticker, paper, or printer.
- Favor strong silhouettes, open white space, simple shapes, and clear contrast.
  Avoid big solid-black backgrounds, delicate textures, faint shadows, tiny
  highlights, gradients essential to meaning, and dense crosshatching.
- Main outlines should remain at least 2–3 pixels thick at the final 384-pixel
  width. Keep small important features large enough to survive downsampling.
- For line art use clean black and white. For shaded illustrations use a few
  distinct gray values; do not simulate dithering, halftones, or paper texture in
  the generated image. The final renderer handles dot patterns at printer size.
- Fit the composition closely, with a small clean white safety margin and no
  unnecessary decorative frame or large empty border. Do not crop content.
- Choose an aspect ratio suited to the request. Arrange multi-panel comics in a
  readable vertical sequence when possible. Keep text upright within the image.
  Landscape images may be rotated by the app so their long side uses the paper's
  feed direction; the user can override the rotation.
- If text is requested inside artwork, keep it short, bold, and large: roughly
  20–24 pixels or more at final width, headings about 28–36 pixels. Never use tiny
  captions or elaborate lettering. Preserve the user's requested wording.

Text and tables:
- Prefer real text/Markdown for labels, lists, schedules, and data tables when
  artwork is not requested. Use concise headings, paragraphs, bullets, checkboxes,
  and at most three short table columns. Do not simulate columns with spaces.
- Preserve the user's facts and spelling. Do not invent personal information,
  add unsolicited slogans, or append an explanation outside the sticker.

The renderer scales proportionally, rotates before dithering, prints the exact
black-and-white preview, removes fully blank leading rows with no added top
margin, and feeds a final 10 mm for cutting. Do not draw cut marks
or add extra blank paper to imitate that final feed.
<!-- S1_PRINT_PROFILE_END -->

## Engineering and verification

- Native apps and printer logic are Swift. `Shared/Core` owns layout, image
  normalization, monochrome conversion, orientation, and packet encoding.
  `Shared/AI` owns the API client; `Shared/UI` owns debounced preview state.
  Platform transport/UI code belongs in `macOS` or `ios/Sources`.
- Build from root `project.yml` / `S1Sticker.xcodeproj`. Run `swift test` for the
  shared core and `tests/test_rendering.py` against the intended Mac binary.
  Keep platform-specific transport and UI separate from the shared core.
- A print request authorizes one copy. Never automatically retry a partially sent
  or uncertain job. Preview requests do not print.
- Keep API keys in each device's Keychain. Never embed, print, export, or log keys.
- Preserve stable Apple Development signing for Mac updates; ad-hoc signatures
  create per-build identities and repeated Keychain authorization prompts.
- Use the shared OpenAI client and printer profile for new prompt entry points.
- Rotate the source before scaling and dithering; preserve aspect ratio and all
  content. Auto-rotate landscape images only. Leave text layouts upright.
- Preserve S1 FF03 credit flow control, the cross-process printer lock, and 10 mm
  final feed. Do not change printer firmware or persistent settings.
- Test orientation with asymmetric images, verify monochrome raster output, and
  distinguish software checks from a user-confirmed physical print.

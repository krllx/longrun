# Prompts for the README banner (hero.png)

Target for all three: a wide banner, 1600 x 600 px (aspect 8:3), PNG, dark background so it sits well in
GitHub's dark and light themes. The README currently shows the hand-drawn `hero.svg`; generate a `hero.png`
and point the `<img>` in README.md at it.

Palette used by the site and the course, worth keeping so the banner matches:
background `#141414`, accent orange `#d97757`, text `#f2f0eb`, muted `#9a9a94`,
session green `#3f7f5f`, context blue-violet `#4a5480`.

Negative prompt for all variants, if the tool accepts one:

> photorealistic, 3D render, glossy plastic, stock-art robots, brains, lightbulbs, clutter, many words,
> misspelled text, watermark, logos of other products, busy background, rainbow gradients.

---

## Variant A: the schematic (what the tool does)

Sells the core mechanic: context degrades through compactions, the note on disk does not.

> A clean, minimal wide banner for a developer tool called "longrun". Dark charcoal background (#141414) with a subtle fine grid. In the center, a horizontal timeline made of a thin light line running left to right. Along the timeline, three translucent rounded panels representing an AI model's context: the first is full of many small text lines, the second is a short summary with most lines faded out, the third is nearly empty. Below the timeline, a solid warm-orange (#d97757) rounded card labelled "notes" that stays the same size all the way across, connected to each panel by thin dotted vertical arrows pointing up into the panels. To the right, two small identical session icons (rounded squares with a chat bubble) linked to the orange card by thin lines. Flat vector style, thin strokes, soft glow on the orange card, no people, no text other than the single word "longrun" in a modern geometric sans-serif at the left, and the small label "notes". Lots of negative space, editorial tech-illustration feel, no 3D, no gradients heavier than a soft glow.

Fallbacks if the result is too literal: the panels become notebook pages fading out and the orange card
becomes a bookmark; or a square 1024 x 1024 logo variant, the orange card with one bright line on it inside
a faint ring of three fading panels, the word "longrun" underneath.

---

## Variant B: the trail markers (the metaphor)

Sells the same idea without any interface: a long route where the road behind disappears, and the markers
you left stay sharp. Warmer and more memorable than A, weaker at explaining the mechanics.

> A wide, atmospheric banner illustration for a developer tool called "longrun". A long winding trail recedes from the bottom-left corner to the far right of a dark charcoal (#141414) landscape drawn as minimal flat vector shapes: a few low ridges, no sky detail, heavy negative space. The left half of the trail behind is swallowed by soft grey fog, its path barely visible; the right half ahead is crisp. Along the whole trail, evenly spaced, stand small glowing warm-orange (#d97757) marker posts, each with a tiny horizontal label plate, all exactly the same brightness whether they are deep in the fog or in the clear part, so the markers read as the only thing the fog does not erase. Two identical thin trail lines join the main path from the top, meeting it at one of the markers, suggesting two travellers sharing the same route. Flat vector, thin strokes, muted palette of charcoal, fog grey and one warm orange, soft glow only on the markers. The single word "longrun" in a modern geometric sans-serif in the upper-left, no other text. Editorial poster feel, no people, no animals, no 3D.

Use when you want the banner to feel like a product poster rather than a diagram. Ask for a version with the
fog denser on the left if the "history is being lost" reading does not land.

---

## Variant C: the shared desk (several sessions)

Sells the other half of the product: many sessions, one shared memory. Good if the repo's pitch leans on
coordination rather than on compaction.

> A wide, minimal isometric banner for a developer tool called "longrun". On a dark charcoal (#141414) surface, four small terminal windows float at equal distance around a single glowing warm-orange (#d97757) disc at the center, drawn as a thin flat-vector plate with a few crisp text lines etched on it, like a shared ledger. Each terminal window is a rounded dark rectangle with a green (#3f7f5f) title bar and a few abstract code lines; three of them are lit and connected to the central disc by thin bright lines, the fourth is dimmed and slightly further away, with one small envelope icon waiting on its connecting line. Faint concentric rings radiate from the disc. Subtle isometric projection, flat vector, thin strokes, soft glow only on the disc and the connecting lines, plenty of empty space around the composition. The single word "longrun" in a modern geometric sans-serif in the upper-left corner, no other text. Calm, technical, editorial, no people, no 3D bevels, no photorealism.

The dimmed fourth window plus the envelope is the inbox: a stopped session gets its message on its next turn.
If the generator crowds the frame, ask for three windows instead of four and a wider empty margin.

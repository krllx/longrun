# assets

`hero.jpg` is the banner at the top of both READMEs: 2000 x 848 px (aspect 2.36:1), shown at 820 px wide.
It was generated from variant A of `hero-prompt.md`, which also holds two other prompts if the banner ever
needs redrawing. `hero.svg` is the earlier hand-drawn version of the same idea, kept as a fallback for
places where a raster image is inconvenient.

`course-banner.svg` and `course-banner.ru.svg` are the clickable call-out to the course under the badges:
1640 x 260 px, shown at 820 px wide, hand-written SVG in the palette of `hero.jpg` (`#141414` on `#d97757`).
They carry their own dark background, so they read the same in GitHub's light and dark themes, and use a
system font stack because GitHub does not load web fonts inside an image. Edit the text in place, and
mind the two limits that fall out of that stack being unknown: the subtitle has to stay left of the
button pill at x=1266 (about 70 characters at 28 px), and the button label has to fit inside the pill's
310 px with room to spare - "Open the course" measures 221 px in the widest of the candidate fonts.

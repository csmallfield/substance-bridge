# Concrete Ribbons: reference analysis

`reference.jpg` (434 x 745 px, front view, raking light from the upper left) shows cast-concrete relief panels.
The output is square and tiles both ways.

## Reading (revised after a 2x gridded zoom: zoomA.png, zoomB.png, zoomC.png)

- **Joint chains:** the black lines are joints between precast pieces. Each one runs down a column line (columns about
  69 px), then S-bends one column to the LEFT at 45 degrees with rounded corners, runs down that line, and so on.
  A line is a joint only from where a chain lands on it until the chain leaves; elsewhere it is empty, so a piece is one
  or two columns wide.
- **Cut joints:** short straight 45-degree joints going down-RIGHT (no rounding) connect two vertical joints, ending
  on them as T-junctions. They split the strips into panels and ignore the relief.
- **Relief inside a piece:** a flat light ribbon along the left joint, about half a column wide, then a broad lit step
  face, then a darker plane that leans back toward the right joint. The step is the left joint shifted right by about
  0.5 column and down by about 1.7 columns. After a joint bends left, the step lags behind and the ribbon flares into
  the wide "bottle" shoulder (zoomC.png shows one piece).
- **Surface:** fine concrete grain and pinholes, nearly white to mid grey, matte.

## Model (ribbon_layout.py)

- N = 6 columns; the square tile is 6 columns tall.
- Line c's chain lands at Y[c+1] + P, stays L[c], and leaves at Y[c]. The values of P + L summed over the lines equal
  4, so the bends close up over the tile.
- The step is the same chain looked up B higher and shifted right by A.
- Each strip gets one cut where both of its lines are joints.

## Treatment (requested)

Concrete with options for weathering, water stains (vertical streaks running from the bends, ledges and joints) and
mould.

# Smarter Walls

**Author**: Monsterfish
**Version**: 1.0.10

Makes drawing walls easier and fixes how damaged stairs and crenellations are repaired.
Every part can be switched off in the settings.

## Walls at any angle

A wall you drag now goes in a straight line from where you start to where you let go, at
any angle. Before, walls could only run straight or at 45 degrees, with a bend in between.

## Walls flow around buildings

When something stands in the way of your wall - a building, a tree, rocks or anything else a
wall cannot go on - the wall goes around it, hugging its shape, and then carries on towards
where you let go. Before, the whole wall turned red and could not be placed.

## Walls flow around other walls

A new wall or crenellation also goes around your undamaged walls, stairs and crenellations instead of
running over them. It can still start or end on one to join onto it, and it still goes over
damaged walls, so dragging a wall along a damaged one repairs it. This needs "Walls flow
around buildings" to be on.

Crenellations and stairs do the same: drag crenellations along a wall and they follow its
shape; stairs go around buildings and walls in straight steps, as stairs always do.

The preview, the cost and the wall that gets built always match.

## Crenellations match the wall they are on

A new crenellation is built a little taller than the tallest wall right next to it, so it
fits walls on hills, in dips and low walls alike. Other crenellations next to it are only
used when it touches nothing else. Next to stairs, the step right beside it decides (the
lower one if it touches two): the top three steps get tall crenellations, step 4 and lower
low ones. Repairing a crenellation uses the same rule.

## Ladders and siege towers can use every crenellation

Ladders and siege towers can attach to the raised parts of crenellations as well. Troops
step onto a raised part only right next to a ladder or a siege tower, to get on or off it;
everywhere else the raised parts stay out of their way as before, so nobody idles or spreads
out onto them. Anyone who still ends up standing on one is moved to the nearest wall tile
(never onto another crenellation; with only those nearby they stay put). Troops waiting
there for their turn on a ladder get more time first (10 seconds, adjustable in the
settings); after that they carry on to where they were going.

## Repairing stairs keeps their height

Building a wall over damaged stairs puts the stairs back at the height they had. Before,
they turned into a block as tall as a wall.

## Repairing crenellations keeps them

Building a wall over a damaged crenellation repairs the crenellation. Only an undamaged
crenellation is turned into wall when you build a wall over it, just like before.

## Multiplayer

Everyone in the game needs this module, with the same settings, because the shape of a
wall is worked out on every player's machine.

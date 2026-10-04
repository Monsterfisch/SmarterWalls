# Smarter Walls

**Author**: Monsterfish
**Version**: 1.0.9

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

## Troops can walk over crenellations

Troops can now walk over the raised parts of crenellations instead of going the long way
round. A group you send onto a wall never picks a raised part as a place to stand when it
spreads out. They cannot stay on them: anyone who stops on one is moved to the nearest wall tile
straight away, and does not try to walk back onto it. They are never moved onto another
crenellation: if only crenellations are nearby, they stay where they are. Troops waiting there for their turn
to climb down a ladder get more time (10 seconds, adjustable in the settings) before they
are moved; after that they carry on to where they were going.

Ladders and siege towers can now attach to every part of a crenellation, raised parts
included, and troops climbing up can get off onto them. Assassins can climb onto them too.

## Ladders and siege towers attack diagonal walls

Laddermen and siege towers can now attack walls and crenellations that run diagonally.
Laddermen lean their ladder against the diagonal wall, and a siege tower parks with one
corner against it, since it needs a 3 by 3 space to set up. Before, diagonal walls could
not be climbed at all.

## Repairing stairs keeps their height

Building a wall over damaged stairs puts the stairs back at the height they had. Before,
they turned into a block as tall as a wall.

## Repairing crenellations keeps them

Building a wall over a damaged crenellation repairs the crenellation. Only an undamaged
crenellation is turned into wall when you build a wall over it, just like before.

## Multiplayer

Everyone in the game needs this module, with the same settings, because the shape of a
wall is worked out on every player's machine.

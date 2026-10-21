# Smarter Walls

**Author**: Monsterfish
**Version**: 1.0.17

Makes drawing walls easier and fixes how damaged stairs and crenellations are repaired.
Every part can be switched off in the settings.

## Walls at any angle

A wall you drag now goes in a straight line from where you start to where you let go, at
any angle. Before, walls could only run straight or at 45 degrees, with a bend in between.

## Walls flow around buildings

When something stands in the way of your wall - a building, a tree, rocks or anything else a
wall cannot go on - the wall goes around it, hugging its shape, and then carries on towards
where you let go. Before, the whole wall turned red and could not be placed.

## Walls flow around trees

A wall goes around trees instead of building straight through them and clearing them away.
The two ends you pick stay exactly where you put them.

## Starting on a damaged wall only repairs

When you start dragging a wall on a damaged wall tile, the drag only repairs the damaged wall
tiles along the way. Nothing new is built on empty ground between or beyond them, and you are
only charged for the repairs.

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

## Troops can cross every crenellation

Troops can walk across the raised parts of crenellations: troops coming up a ladder or a
siege tower, assassins, and anyone else passing by. Ladders and siege towers can attach to
them too, and assassins can climb up onto them, so crenellations of any thickness or
direction never keep assassins off a wall. But nobody is ever sent to stand on one - an order, a group spreading out, an idle
unit making room or a patrol always picks the wall tile next to it instead. Anyone who still
ends up standing on one is moved to the nearest wall tile (never onto another crenellation;
with only those nearby they stay put). Troops waiting there for their turn on a ladder get
more time first (10 seconds, adjustable in the settings).

Ladders can also attack walls that run diagonally. Siege towers docking at diagonal walls used
to be part of this module too; that is in Improved Siegeengines now.

## Fix units stuck at low diagonal walls

Fixes an old bug in the game itself. Where two low walls touch diagonally and ground-level
stairs sit in one corner between them, units trying to step from the stairs to the ground in
the opposite corner got stuck there for good, asking for a new route every moment and
slowing the whole game down. They now step across like anywhere else.

## Only cross crenellations attached to walkable walls

Troops can cross the raised parts of a crenellation only while it touches a wall they can
still walk on. If the wall beside it is destroyed or damaged too badly to walk on, the raised
parts next to it close, so nobody walks across crenellations hanging in the air. Repairing the
wall opens them again.

## Crenellations do not lead into towers

Troops can no longer walk from a crenellation straight into a tower, keep or gatehouse. Only
the wall itself or stairs lead there, so a tower is not reached by a crenellation that happens
to touch it.

## Repairing stairs keeps their height

Building a wall over damaged stairs puts the stairs back at the height they had. Before,
they turned into a block as tall as a wall.

## Low walls repair stairs too

Building a low wall over damaged stairs puts the stairs back at the height they had, exactly
like a normal wall does. Low walls leave damaged crenellations alone, as before.

## Repairing crenellations keeps them

Building a wall over a damaged crenellation repairs the crenellation. Only an undamaged
crenellation is turned into wall when you build a wall over it, just like before.

## Multiplayer

Everyone in the game needs this module, with the same settings, because the shape of a
wall is worked out on every player's machine.

# Movement and camera

**Status:** built and tested · **Code:** `src/shared/Combat/Stamina.luau`,
`src/server/Services/MovementService.luau`, `src/client/Controllers/MovementController.luau`,
`src/client/Controllers/CameraController.luau`, `src/shared/Config/CombatConfig.luau`
· **Tests:** `tests/Stamina.spec.luau`

## Moves

| Move | How | Stamina |
| --- | --- | --- |
| Sprint | Hold dodge while moving | 18 per second |
| Dodge | Tap dodge. Steps back when standing still. 0.3 s of invulnerability | 20 |
| Climb | Run into any steep surface | 12 per second |
| Climb leap | Jump while climbing | 25 |
| Glide | Jump again while falling from at least 6 studs up | 8 per second |

Stamina refills at 30 per second, starting 1 second after the last spend. All values are in
`CombatConfig`.

## Who decides what

The client moves its own character so movement feels instant, but everything that matters is
decided by the server:

- **Stamina lives on the server** and is calculated from timestamps (`Shared.Combat.Stamina`).
  A client that keeps asking to sprint still runs dry; the tests cover this.
- **Sprint speed is set by the server**, only while it accepts the sprint.
- **Dodge invulnerability is granted by the server**, only when the dodge was paid for. Enemy
  strikes check it on the server.
- **Running out ends the move.** The server tells the client, which drops off the wall, folds the
  glider or slows to a walk.
- **Speed sampling:** the server logs characters that keep moving faster than any move allows,
  for review rather than automatic punishment.

## Climbing and gliding

Climbing switches the character to physics control: an `AlignOrientation` keeps it facing the
wall and a `LinearVelocity` moves it along the wall from the movement input, holding a fixed
distance from the surface. Reaching the top hops the character over the ledge; pressing dodge,
or pulling back once the feet touch the ground, lets go. Gliding replaces the fall with a slow,
steerable descent until landing.

## Camera

A custom third-person camera (`CameraType` Scriptable) so lock-on can blend in and out without
snapping:

- Over the shoulder, with mouse, right stick or touch drag to turn, and wheel or pinch to zoom.
- The mouse is locked to the centre in play; hold Left Alt to free it.
- Pulls in when a wall would block the view.
- **Lock-on** picks the enemy closest to the centre of view and turns the camera towards it.
  Attacks aim at the locked enemy, or where the camera looks.
- Small shakes on heavy hits, bursts and taking damage.

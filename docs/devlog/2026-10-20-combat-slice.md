# The combat slice is playable

*2026-10-20 · M1 Combat slice · Owl On The Moon Studios*

## What's new

Farborn has its first real fight. In a grey-box test arena you can now:

- **Fight with a party of four.** Each hero has a four-hit attack chain, an elemental skill and
  a burst that charges as you fight. Press 1 to 4 (or tap a hero) to swap instantly, even in the
  middle of a combo.
- **Mix elements.** Burn an enemy with fire, then swap and splash it with water for Steam, or
  soak it and freeze it solid. Steam, Melt, Overload, Conduct, Freeze and Brittle all work in
  live combat.
- **Move like an adventurer.** Sprint, dodge through attacks, climb any cliff and glide down from
  the top. All of it runs on one stamina bar.
- **Face the Training Grunt.** It always shows you its attack on the ground before it swings, so
  a good dodge beats it every time. Groups take turns instead of piling on, and big hits break
  their guard.

It plays with keyboard and mouse, controller, or touch.

## Behind the scenes

Your hits feel instant because your screen plays them straight away, but the server confirms
every one, along with every cooldown and every bit of stamina, so nobody can cheat the fight.
The rules behind the party, stamina, cooldowns and enemy decisions are all pure code with
automatic tests: there are now 56 of them. Ten enemies at once still run at 60 frames per second.

## What's next

Playtesting how it feels, then real character models, animations and effects to replace the
grey boxes.

## A question for you

Which would you rather master first: perfect dodges or perfect reaction combos?

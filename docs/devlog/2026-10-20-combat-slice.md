# The combat slice is playable

*2026-10-20 · M1 Combat slice · Owl On The Moon Studios*

## What's new

Farborn has its first real fight. In a grey-box test arena you can now:

- **Fight with a party of four.** Each hero has an attack chain, a charged attack, a plunge from
  the air, a Technique and a Finale. Press 1 to 4 (or tap a hero) to swap instantly, even in the
  middle of a combo, and a hero who has rested on the bench jumps in with a Relay.
- **Mix elements.** Soak an enemy with Tide, then hit it with Flame for SCALD, or freeze it with
  Frost for LOCK and smash the ice. Nine reactions are in, from Scald to Starburst.
- **Read every attack.** Enemies flash before they swing: white means a normal attack, gold means
  you can attack into it to LIFT it, red means get out of the way. Dodge just before a hit lands
  for a SLIP and the world slows down for a moment.
- **Take on an elite.** The Training Brute has a gold Composure bar. Break it and the brute is
  RATTLED: it takes extra damage, and your whole party can Pile-On.
- **Move like an adventurer.** Sprint, dodge, climb any cliff and glide down from the top. All of
  it runs on Grip, one bar for everything except dodging.

It plays with keyboard and mouse, controller, or touch.

## Behind the scenes

Your hits feel instant because your screen plays them straight away, but the server confirms
every one, along with every cooldown, every dodge and every bit of Grip, so nobody can cheat the
fight. Dodges and Lifts are judged with a little allowance for your connection, so good timing
works the same on a slow network. The rules behind elements, the party, dodges, cooldowns and
enemy decisions are pure code with automatic tests: there are now 80 of them. Ten enemies at once
still run at 60 frames per second.

## What's next

Playtesting how it feels on a phone, saves that can't be lost, and blocking out the first real
place to explore.

## A question for you

Which would you rather master first: perfect Slips or perfect Lifts?

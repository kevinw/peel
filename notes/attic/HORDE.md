# Horde Mode Roadmap

This is a short list of practical next steps for turning `src/apps/model_scene.jai` into a stronger Vampire Survivors style prototype.

## Immediate Priorities

1. Add a real enemy wave loop.
Timed spawns, ramping enemy counts, and one elite variant every N waves.

2. Give the player one guaranteed auto-attack weapon.
Start with nearest-target projectile, short arc slash, or a simple periodic burst.

3. Add XP gems and level-ups.
Enemies drop XP, the player vacuums nearby gems, and each level-up offers 3 upgrade choices.

4. Implement a first set of upgrade cards.
Good starter upgrades: damage up, attack speed, move speed, extra projectile, pickup radius, max health, crit chance, cooldown reduction.

5. Add enemy contact damage and invulnerability frames.
Survival time needs to matter, and the player needs readable damage feedback.

6. Add a minimal progression HUD.
Show HP, level, XP bar, timer, kills, and current passive bonuses.

7. Add one strong “feel” system.
Pick one and make it good: screen shake, hit flash, damage numbers, death burst, or crit pop.

8. Add a second weapon archetype.
Orbiting blades, AoE pulse, piercing beam, chain lightning, or a boomerang all work.

9. Add a dense trash-mob stress test mode.
This should intentionally validate swarm counts and frame stability, not just gameplay.

10. Add a run fail/restart loop.
Death screen, run summary, restart without rebuilding, and optional seed replay.

## Good Order To Build

1. Wave loop
2. Auto-attack
3. XP and level-ups
4. Upgrade cards
5. HUD
6. Contact damage and invulnerability
7. Second weapon
8. Juice and game feel
9. Stress-test mode
10. Death/restart flow

This order gets from “scene with enemies” to “playable run” as quickly as possible.

## More Ideas

1. Add enemy roles instead of only scaling stats.
Examples: chaser, ranged kiter, charger, tank, summoner, healer, hazard-dropper.

2. Add a simple director.
Use elapsed time plus current player power to bias spawn composition and elite frequency.

3. Add meta choices to weapons.
Branch weapons into two evolution paths rather than only linear stat increases.

4. Add a pickup magnet threshold.
Make gems start homing when the player gets close or after a delay to reduce cleanup friction.

5. Add an enemy corpse or dissolve budget.
A short-lived visual death state helps readability without turning into clutter.

6. Add terrain-aware kiting pressure.
Use blockers, slow zones, or funnels so positioning matters more than only raw move speed.

7. Add temporary power pickups.
Examples: bomb clear, haste shrine, healing orb, bonus XP orb, temporary shield.

8. Add a boss every few minutes.
Bosses should test movement patterns, not just health totals.

9. Add one “panic button” mechanic.
A long-cooldown dash, blink, or radial knockback makes the run more expressive.

10. Add milestone rewards.
Every few minutes or wave milestones, give a guaranteed chest or a rarer upgrade choice.

11. Add enemy spawn telegraphing.
Spawn rings, cracks, shadows, or portals make chaos easier to parse.

12. Add one explicit build-defining stat.
Pierce, chain count, area size, duration, orbit count, or crit scaling are all strong candidates.

13. Add progression snapshots for tuning.
Record time-to-kill, kills per minute, pickup rate, average damage taken, and upgrade picks.

14. Add a sandbox tuning panel.
Spawn multiplier, enemy speed, player damage, XP gain, and cooldown scale are worth exposing live.

15. Add a clean content minimum for “fun enough to tune.”
Suggested target: 3 weapons, 8 upgrades, 4 enemy types, 1 elite, 1 boss, 1 map variation.

## Design Notes

- Keep the first loop simple and legible before adding lots of content.
- Prefer one or two deep systems over many shallow placeholder systems.
- Make enemy pressure and player growth visible every 20-30 seconds.
- If a new system doesn’t change player decisions, it probably isn’t ready yet.
- Performance work should be driven by actual swarm scenarios, not empty-scene benchmarks.

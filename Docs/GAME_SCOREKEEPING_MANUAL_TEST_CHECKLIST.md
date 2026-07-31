# Games and Live Scorekeeping Manual Test Checklist

Use a clearly named disposable test game. Do not use real customer data.

## Calendar and Games

- [ ] Sign in as an organization owner or admin.
- [ ] Open the organization calendar and create a test game.
- [ ] Set the team, opponent, home/away status, venue, arrival time, start time, and innings.
- [ ] Confirm the game appears once in the calendar and relevant Today surfaces.
- [ ] Edit and reschedule the game; confirm no duplicate calendar entry appears.
- [ ] Confirm visibility for the assigned coach, player, and linked parent.
- [ ] Confirm an unrelated user cannot access the game.

## Game Preparation

- [ ] Open the canonical game workspace and review Overview.
- [ ] Add or confirm the roster and submit availability.
- [ ] Configure the batting order and defensive lineup.
- [ ] Confirm the selected ruleset and assign a scorekeeper.

## Live Scoring

- [ ] Start live scorekeeping and confirm score, inning, count, outs, pitcher, pitch count, batter, field, and runners remain visible.
- [ ] Record a ball, called strike, swinging strike, foul, and ball in play.
- [ ] Drag a batter-runner to first and an existing runner to the next base.
- [ ] Record an out and a multi-runner play.
- [ ] Test Undo and confirm play-by-play updates.

## Multiple Devices

- [ ] Open the same game on a second device or simulator.
- [ ] Confirm the second device enters viewer mode and cannot mutate the game.
- [ ] Request and transfer scorekeeping control.
- [ ] Confirm the old scorer becomes read-only and the new scorer can record the next play.

## Special Rules

- [ ] Test a run-cap inning and confirm it ends without fabricated outs.
- [ ] Test an automatic-out lineup vacancy.
- [ ] Test injury handling, an ejection, suspension, and resumption.
- [ ] Test a custom defensive alignment when available.

## Finalization

- [ ] Finish or administratively end the test game, then finalize once.
- [ ] Confirm calendar status becomes final.
- [ ] Confirm the box score and player batting and pitching lines.
- [ ] Confirm the final score in player and parent views.
- [ ] Perform one authorized scoring correction.
- [ ] Confirm statistics and play history update exactly once.

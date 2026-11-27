# Changelog

## 1.1.0
- **Idle fade:** out of combat the box rests at 35% alpha and comes back to full in combat, under the mouse, while a Trance is up and during `/shc test`. On by default; `/shc fade` or the right-click menu turns it off.
- **Trance drain bar:** while a detected Shadow Trance is up, the bar turns violet-white and drains over its 10 seconds (`NIGHTFALL! 6.2s`), then goes back to the Shadow Bolt share bar when the Trance is spent or runs out. It never starts for a Trance the game hides from addons; when no time can be read it stays full with a plain `NIGHTFALL!` instead of counting down.
- **Right-click quick menu** (Blizzard's own menu, out of combat only): sound mode, sound file, idle fade, compact mode, lock, click-through when locked, test preview, reset session and reset position. `/shc menu` opens it too. In combat it doesn't open, and entries of a menu left open do nothing.
- **Compact mode** (`/shc compact`, off by default): a slim 60 px strip with the headline, the instant-bolt count and the bar. Your full width and height are kept and come back when you switch it off.
- **Click-through when locked** (`/shc clickthrough`, off by default): while the box is locked, clicks pass through it to the world. `/shc unlock` or `/shc clickthrough` makes it clickable again (the padlock can't be clicked while click-through is active).
- `/shc test` is now a 10-second preview of the whole Trance look (glow, countdown, drain bar, sound); it stops when combat starts.
- Settings from 1.0.x are kept; the three new switches start at their defaults.

## 1.0.1
- Trance detection now adapts to what the client allows. In combat the game can hide buff data from addons, so Shadow Count checks at runtime whether Shadow Trance is readable or appears as a cast event. When neither is available it no longer treats a hidden buff as "Trance ended": gains show as unknown, and instant Shadow Bolts are still counted.
- The `NIGHTFALL!` glow and 10-second countdown only start when a Trance is actually detected, and stop the moment it's spent.
- This should work on WoW: Forever. Confirmation in real fights will come from players, so please report what `/shc debug` shows if something looks off.
- Interface polish: clearer layout and text.

## 1.0.0
- First release for WoW: Forever (Interface 16001, client 1.60.1).
- `NIGHTFALL!` and a violet-white glow over the whole box while Shadow Trance is up; clears when the bolt is spent or the Trance runs out.
- Counts Trances gained and instant Shadow Bolts spent (a bolt you were already casting does not count), per fight and session.
- After each fight: Shadow Bolt damage (all ranks), share and average per bolt from Blizzard's own damage meter, or "counting procs only".
- Shadow-purple box with talent-tree accents. The game's own Shadow Trance alert sound on every Nightfall, on a new best average, or off.
- Movable, resizable and lockable box (240x150 below the middle of the screen), only shown on Warlocks. `/shc debug`, `/shc meter`, `/shc report`.

# QuestRoute

QuestRoute turns the quests already in your log into a numbered list of stops. Group nearby quests, favor easier fights or shorter trips, then follow one step at a time in a compact window. You decide when to generate the route and when to advance.

**Version 0.3.0** · **World of Warcraft: Forever 1.60.1** · Interface **16001**. QuestRoute works on its own.

## Install or update

1. Download [QuestRoute-0.3.0.zip](../downloads/QuestRoute-0.3.0.zip) from the repository's `downloads` folder on GitHub. Use the **Download raw file** button if GitHub opens the ZIP's file page.
2. Extract the ZIP. Copy the `QuestRoute` folder into `World of Warcraft/_forever_/Interface/AddOns/`. If you downloaded the entire repository, copy just its `QuestRoute` folder to the same place.
3. Check that the installed path ends in `_forever_/Interface/AddOns/QuestRoute/QuestRoute.toc`. Start WoW and enable **QuestRoute** in **AddOns** on the character-selection screen.
4. To update, replace the installed `QuestRoute` folder with the one from the new ZIP and run `/reload` in game. WoW keeps your settings in its separate `WTF` folder. If the addon is missing from the list, check for an extra folder around the manifest and restart the game.

**Windows installer.** If you have the whole repository, open PowerShell in its top-level folder and run `.\Install-QuestRoute.ps1`. The script backs up an existing copy in `dist/backups/` and verifies the installed files. For a custom WoW installation, supply its existing `AddOns` directory as in this example.

```powershell
.\Install-QuestRoute.ps1 -AddOnsPath "D:\Games\World of Warcraft\_forever_\Interface\AddOns"
```

## Plan your first route

1. Click **Plan** on the small QuestRoute window, or type `/qr`. To try the controls before accepting any quests, type `/qr test` for a fictional sample. The preview uses separate sample data.
2. With quests in your log, leave the defaults at **Multi-objective**, **Balanced**, and **Normal** grouping for your first trip. Click **Generate Route** outside combat.
3. Hover a numbered row to see the destination, objective information, and why QuestRoute put it there. Click a row to select it. **Quest Details** opens the game's quest view when available.
4. Click **Use Route** to return to the compact window. Click **Next >** after finishing a stop, **<** to go back, or **Details** to inspect the selected quest. Drag either window by its header to save its position.

A **\*** on the compact window means the plan needs a refresh. Quest-log and level changes flag the existing route for review. Open **Plan** and generate again when you want the new order. A saved schedule reopens in compact view at login. Generate a fresh route when switching characters to use that character's log.

## Choose how stops are ordered

| Control | What it changes |
| --- | --- |
| **Optimization** | In **Single-objective**, choose **Shortest travel**, **Safer levels**, or **Time / effort**. **Multi-objective** combines four priorities and starts at **Balanced**. Both modes keep nearby stops together. |
| **Emphasis** and sliders | Pick a preset or adjust **Distance**, **Quest level**, **Time / effort**, and **Clustering** independently. For a close-to-town circuit, try **Shortest travel** with **Tight** grouping. **Reset to Balanced** restores the defaults. |
| **Grouping** | **Tight**, **Normal**, and **Wide** change how close destinations must be to form a cluster. Wider groups can keep more quests together before you move to another area. |
| **Defer quests 2+ levels above me** | Enabled by default. At level 20, quests rated 22 and above come after the other quests. Turning it off lets harder quests mix into earlier stops with a difficulty penalty. |
| **Favor completed turn-ins** | Gives completed quests extra priority in Multi-objective mode. Both modes include turn-ins. |

Changes to these controls take effect on the next **Generate Route**. In Multi-objective mode the sliders run from 0 to 10 in steps of 0.05. **Balanced** uses 6.00 for distance, 3.00 for quest level, 1.80 for effort, and 1.60 for clustering. Moving a slider selects **Custom**. A zero weight removes that factor's score. Area grouping and the hard-quest rule apply at every weight.

## How to read the schedule

- **One stop per quest.** QuestRoute takes the current waypoint or map pin supplied by the game. This can be an entrance, an objective area, or a turn-in. Generate again after a quest advances to a new stage.
- **Travel.** Distances are straight-line estimates. Roads, caves, terrain, and transport can change the best way to get there. Grouping uses approximately 180, 350, or 700 yards when world coordinates are available. On the same map it can fall back to normalized coordinates.
- **Time / effort.** The estimate counts unfinished objective lines, adjusts for quest level and suggested group size, and gives turn-ins a small interaction cost. A single line can represent many kills or drops. Travel time is separate.
- **Missing data.** Quests without a waypoint appear grouped by area after located quests in their difficulty tier. Failed quests must be restarted. Hover the notice below the schedule for warnings. If the log is temporarily unreadable, QuestRoute keeps the previous schedule.

## Commands

Use `/qr` or `/questroute` with any of the following commands.

| Command | Action |
| --- | --- |
| `/qr` | Open the planner. |
| `/qr generate` | Build a route from your current quest log and options. |
| `/qr min` or `/qr show` | Open the compact view. |
| `/qr next` or `/qr prev` | Select the next or previous saved step. |
| `/qr hide` | Hide both windows until you open one again. |
| `/qr test` | Preview fictional quests. |
| `/qr help` | Print command help in your chat window. |

## Client references

The planner reads quest and waypoint information from the Forever client. [Quest log API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua) · [Map API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua) · [Native quest pins](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedMapDataProviders/QuestDataProvider.lua)

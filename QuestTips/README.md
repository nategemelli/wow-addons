# QuestTips

QuestTips helps you work out the next step of an accepted quest in **WoW Forever 1.60.1** (interface **16001**). Open a quest's details in the map or quest log to see its guide. For *Lazy Peons*, for example, the tip tells you to find a peon asleep under a tree, target it, and use the Foreman's Blackjack.

## Install

1. Download the [QuestTips 0.1.0 ZIP](../downloads/QuestTips-0.1.0.zip) and extract it.
2. Copy the `QuestTips` folder into `World of Warcraft/_forever_/Interface/AddOns/`. The manifest should be at `AddOns/QuestTips/QuestTips.toc`.
3. Start the Forever client and enable **QuestTips** under **AddOns** on the character-selection screen. It runs on its own.

If you have the whole repository on Windows, you can run `.\Install-QuestTips.ps1` from PowerShell in the repository folder. For a custom install location, run `.\Install-QuestTips.ps1 -AddOnsPath 'D:\Games\World of Warcraft\_forever_\Interface\AddOns'`.

## Use the guide

- **Inspect a quest.** Open its details in your quest log. Tips follow the quest you select. Closing quest details closes the guide that opened with them.
- **Keep tips in the field.** Type `/qtips` to open a guide that stays visible when you close the map. It starts with the selected quest, then tries your tracked quest and the first quest in your log. `/questtips` also works.
- **Browse your log.** **Previous** and **Next** cycle through available quests and keep that quest's tips on screen as you play. **Selected quest** returns to the quest selected in your log. Drag the QuestTips header to move the window and scroll inside it to read longer clues.
- **Control when tips appear.** Use `/qtips auto off` for manual use only, or `/qtips auto on` to restore automatic tips. This setting carries over between sessions. Click **×** or type `/qtips hide` to dismiss the current guide.

## What the tips cover

Version 0.1.0 includes handwritten English tips for 32 quests on both factions, from the starting zones and Zephras Isle to class quests and dungeon puzzles in Zul'Farrak and the Sunken Temple. Twelve quests also have handwritten turn-in directions. Each tip uses the quest's numeric ID so different stages with the same title can have different advice. For *Sarkoth*, the hunt points to the plateau south of Hana'zua and the follow-up points to Gornek inside the Den.

Across the rest of the quest log, the guide uses the text and progress the client supplies. It can show directions from the quest giver, unfinished objectives, a quest item, or a waypoint. When the quest is ready to turn in, the guide switches to completion instructions. The available details vary by quest.

## Troubleshooting

- If **QuestTips is missing from the AddOns list**, check for an extra folder level such as `AddOns/QuestTips/QuestTips/`, confirm you installed in `_forever_`, and restart the game.
- If **the guide doesn't appear automatically**, accept the quest, open its details, or use `/qtips auto on`. You can always open the field guide with `/qtips`.
- If **Previous/Next skips a quest**, expand its zone heading in the quest log and select the quest. Some client log views only expose the entries under expanded headings.

To update, close the game and replace the `QuestTips` folder with the one from the newer ZIP.

Handwritten hints were checked against Forever quest records. [The WoW Database](https://thewowdb.com/wow-forever/quest/falling-with-style-92474/) · [Forever Tool](https://forever-tool.com/en/quests/713/) · [Bind on Forever](https://bindonforever.com/quest/3521)

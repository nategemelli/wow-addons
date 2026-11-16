# AuctionPeek

**World of Warcraft: Forever 1.60.1 · Interface 16001 · Addon 0.3.0**

Hover an item to see its cached auction price, the estimated value of your stack, and which professions use it. Prices come from visits to an auctioneer. Crafting uses work as soon as you install the addon.

## Install or update

1. Download the standalone [AuctionPeek-0.3.0.zip](../downloads/AuctionPeek-0.3.0.zip) from this repository's **downloads** folder. If GitHub opens a preview, choose **Download raw file**.
2. Extract the ZIP. Copy the **AuctionPeek** folder into your Forever installation's `_forever_/Interface/AddOns/` folder. If you downloaded the whole repository with **Code → Download ZIP**, open the extracted repository and copy just the **AuctionPeek** folder.
3. Check the final path. It should end in `_forever_/Interface/AddOns/AuctionPeek/AuctionPeek.toc`.
4. Launch WoW Forever and enable **AuctionPeek** in **AddOns** on the character-selection screen. In game, enter `/apeek` to open the controls.

To update, copy the new **AuctionPeek** folder over the old one, then run `/reload`. Your settings, window positions, and saved prices live in WoW's `WTF` folder. The standalone ZIP contains everything AuctionPeek needs, including its recipe index.

**Windows source installation.** From a downloaded or cloned copy of this repository, you can install or update AuctionPeek alone with this PowerShell command.

```powershell
.\Install-AuctionPeek.ps1
```

The installer defaults to `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`. For another location, supply your existing Forever AddOns directory with `-AddOnsPath`. The installer backs up the existing AuctionPeek folder under `dist/backups` in the checkout and verifies every copied file.

## First visit to the auction house

1. Open the auction house. Automatic scanning is on by default. After the auction house is ready, a compact bar appears and counts item groups as they arrive. Click **Expand** to see the scan's level cap and controls.
2. Hover an item in your bags or an item link in chat. The tooltip shows the prices collected so far and their age. A level 20 character scans items requiring up to level 22, including ordinary materials with no level requirement.
3. To check a specific variant, hover the item, open `/apeek`, and click **Refresh Item** while at an auctioneer. Re-hover the item to see its buyout range. This works for items above your scan cap, too.

**Scan Market** starts a fresh level-limited scan manually. A completed browse scan suppresses repeat automatic scans at the same cap for 15 minutes. Leveling up allows the next visit to scan at the new cap. With paged browsing, you can leave as soon as the price you want has appeared. A later visit after an interruption starts a fresh query.

The compact bar hides when work ends. Both panels can be dragged by their headers. Closing or minimizing a panel lets the scan continue while the auction house stays open. **Cancel Scan** stops queued or active work. Closing the auction house or starting another auction search also ends the current scan.

## Reading the tooltip

| What you see | What it means |
| --- | --- |
| **Browse minimum** | Lowest price seen for the same item ID and random suffix in the level-limited browse results. Item levels and bonuses can vary within that group. A confirmed commodity's browse minimum is a unit price. |
| **Min buyout / Max buyout** | Lowest and highest per-item buyouts for the exact variant in a complete result. **Refresh Item** reads additional pages until the server reports full results. Bid-only auctions are excluded from the buyout range. |
| **Observed min / max** | Lowest and highest per-item buyouts among the captured listings. Additional listings can extend the range. |
| **Stack of 7** | An estimate for the actual quantity hovered. Seven cloth at 50 silver each is 3 gold 50 silver. If unit buyouts differ, the estimate shows a range. |
| **Full stack** | An estimate using the maximum stack size, shown for a single item or a link without a stack count. When the only quote is a commodity browse minimum, the estimate assumes every unit is available at that price. |
| **Cached / stale** | Age of the recorded price. Quotes older than 30 minutes are marked stale. Listings can change sooner. |
| **No cached prices** | AuctionPeek has no price for that variant in this market. **No buyout listings in this snapshot** means a completed query found no matching buyouts at the time. |

Prices reflect asking prices. A stack of 20 listed at 10 gold contributes a 50-silver unit buyout. Fractional copper is shown as approximate or `<1c`. Exact ranges distinguish suffixes, bonuses, context, and modifiers. Caches are scoped to client interface, realm, and faction. Battle-pet cage pricing is unsupported.

### Crafting uses

Hover **Linen Cloth** to see **First Aid** with *Linen Bandage* and *Heavy Linen Bandage*, and **Tailoring** with *Bolt of Linen Cloth*. The tooltip lists each profession that directly consumes the material, with up to two named recipes per profession and a count of further uses. Ore can show a smelting recipe, while the resulting bar shows recipes that consume the bar.

The English index covers **531 materials across 12 professions and Rogue Poisons**, using Forever build **1.60.1.70938**. Characters can see uses for professions they haven't trained. This section also works with tooltip prices switched off.

## Commands

Both `/apeek` and `/auctionpeek` accept these commands.

| Command | Action |
| --- | --- |
| `/apeek` | Open or expand the scanner. |
| `/apeek scan` | Scan through your character's level plus two at an auctioneer. |
| `/apeek scan full` | Request an all-level bulk snapshot at an auctioneer. |
| `/apeek refresh` | Request buyouts for the last hovered item. |
| `/apeek auto on`, `/apeek auto off` | Enable or disable automatic scans. `/apeek auto` toggles the saved setting. |
| `/apeek stop` or `/apeek cancel` | Stop a queued or active scan. |
| `/apeek minimize` or `/apeek min` | Use the compact progress bar during a scan. |
| `/apeek hide` | Hide the controls. |
| `/apeek on`, `/apeek off` | Show or hide tooltip price lines. Re-hover the item to apply. |
| `/apeek diag` | Print client version, selected auction API, tooltip status, and cache scope in your chat. |
| `/apeek help` | Print the command summary in chat. |

## Troubleshooting

- **Missing from the AddOns screen?** Verify the folder path in step 3, including the `_forever_` client folder. Restart WoW after a first install if it was already running.
- **No progress bar?** Open `/apeek` for the status. Automatic scans wait for two quiet seconds and the auction house's readiness. The pending request expires after 30 seconds. Check the automatic scan setting and the recent-scan cooldown.
- **Missing an item or seeing a partial range?** Use **Refresh Item** at an auctioneer and keep the auction house open until it finishes. Paged browse saves each group as it arrives. Focused refreshes and bulk scans save their ranges only after processing completes. Submitted requests can time out after two minutes while waiting for a response.
- **Using the bulk scan?** Bulk requests share a separate 15-minute cooldown. Modern bulk snapshots report observed ranges. On clients without paged browsing, a level-limited scan reads the bulk snapshot locally and skips rows above the cap or with unknown requirements. A fully read, unfiltered legacy snapshot can replace that market's cache.

## Data credits and client references

The reagent index uses Blizzard's Forever recipe names and ingredient records. The generator filters retired and seasonal entries and applies the LibProfessionDB v1.10.0 hidden-recipe exclusions. The bundled data file includes the upstream MIT license and copyright notice. [Bundled notice and index](ReagentData.lua) · [Forever ingredient table](https://wago.tools/db2/SpellReagents?build=1.60.1.70938) · [LibProfessionDB release](https://www.curseforge.com/wow/addons/libprofessiondb/files/9619259)

Contributors can run `python tests/run.py` from a source checkout with the Lua 5.1 runtime supplied by `lupa`. The suite exercises price math, scanner and cache behavior, crafting uses, tooltip hooks, and panel controls with a mocked client.

AuctionPeek reads auction listings and saved quotes. Hovering an item uses local data. The implementation follows Blizzard's Forever client interfaces. [Auction API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua) · [Native auction lifecycle](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua) · [Commodity pricing](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseCommoditiesBuyFrame.lua) · [Item and stack APIs](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua) · [Tooltip processing](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua) · [Tooltip item links](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua)

# TankWatch

TankWatch shows which enemies you hold, which are on another tank, and which have turned on a party or raid member. Select an enemy to see how close each teammate is to pulling aggro.

**Version 0.2.1** · **World of Warcraft: Forever 1.60.1** · **Interface 16001**

TankWatch runs on its own. Only the player who wants the panel needs to install it.

## Install or update

1. Download the standalone ZIP and extract it. If you downloaded the whole repository, open the extracted repository folder and find `TankWatch`. [TankWatch-0.2.1.zip](../downloads/TankWatch-0.2.1.zip)
2. With WoW closed, copy the extracted `TankWatch` folder to `World of Warcraft/_forever_/Interface/AddOns/`. To update, replace the previous `TankWatch` folder there. The finished layout should be `AddOns/TankWatch/TankWatch.toc`. WoW stores your settings separately.
3. Start the Forever client and enable **TankWatch** in **AddOns** on the character-selection screen. Log in and type `/tw test` outside combat to verify the installation.

On Windows, if you have the whole repository, you can use the included installer from PowerShell in the repository folder. It backs up any previous TankWatch installation to `dist/backups` and verifies the copied files.

```powershell
.\Install-TankWatch.ps1
```

For a custom WoW install, supply the existing AddOns directory, for example `.\Install-TankWatch.ps1 -AddOnsPath 'D:\Games\World of Warcraft\_forever_\Interface\AddOns'`.

## First pull

1. In **Test** mode, drag the header to place the panel, then click **Lock**. Click **Live** when you're ready. Entering combat also ends the preview.
2. Turn on enemy nameplates (default key **V**). During a pull, the upper list shows observed enemies, their targets, raid markers and threat states. Hover a row for its explanation.
3. Select an enemy using your usual targeting controls. The lower list now shows each group member's role, threat state and percentage against that enemy. Outside combat, you can also left-click an enemy row labeled **Click to target**.
4. For a two-tank group, assign the second tank the **Tank** group role. If your group uses no role assignments, use `/tw tank Name` with their name as shown in the group list. Repeat the command to remove the manual designation.

## Reading threat

| Enemy status | Meaning |
| --- | --- |
| **OFF YOU** · Red | Another group member holds aggro and has no tank designation. |
| **LOSING LEAD** · Amber | You hold aggro and the game reports a weak or threatened lead. |
| **ON YOU** · Green | You hold aggro. |
| **OTHER TANK** · Blue | A designated second tank holds aggro. |
| **TARGETING ALLY** · Orange | The enemy is targeting a teammate. A fixate or scripted attack can make its target differ from its threat holder. |
| **NOT ON YOU** · Orange | You have threat and the holder is unconfirmed. |
| **UNKNOWN** · Grey | The client has restricted or missing threat information. |

The percentages measure progress toward pulling aggro. At 100%, check the status label to see who holds the enemy. The group list sorts by percentage when the client provides a readable value for every member. Otherwise it keeps roster order.

With sound enabled, entering **OFF YOU** or **LOSING LEAD** can play an alert during combat. Sounds are spaced at least four seconds apart. A queued warning expires if the enemy recovers or disappears.

## Commands

Use either `/tw` or `/tankwatch`.

| Command | What it does |
| --- | --- |
| `/tw test` | Switch between sample data and live tracking outside combat. |
| `/tw on` / `/tw off` | Enable or disable the panel, tracking and sounds for this character. `enable` and `disable` are aliases. |
| `/tw show` / `/tw hide` | Show or hide the panel. Tracking and sound alerts continue while hidden. |
| `/tw sound` | Toggle alert sounds. |
| `/tw lock` | Lock or unlock the panel position. |
| `/tw tank Name` | Add or remove a manual tank designation. |
| `/tw reset` | Recenter and show the enabled panel. |
| `/tw diag` | Print the client build, threat API availability, query failures and this character's enabled state in local chat. |
| `/tw help` | Show command help. |

New characters start enabled. For example, use `/tw off` on a healer alt to stop scanning and alerts there. Position, visibility, sound, lock and manual tank designations are shared across characters.

## Troubleshooting

- **Panel missing.** Check that `TankWatch.toc` sits directly under `AddOns/TankWatch/`. Confirm TankWatch is enabled at character selection, then try `/tw on` and `/tw reset`.
- **Enemy list empty or showing UNKNOWN.** TankWatch checks up to 40 nameplates, plus your target, focus and available boss units. Turn on enemy nameplates and try an engaged enemy. The client can restrict threat or identity during an encounter, leaving percentages blank or preventing duplicate rows from being merged.
- **Enemy row says Combat locked.** Use nameplates, Tab or your normal bindings during combat. Outside combat a row click only selects the enemy. Sample rows, despawns and rows whose identity has changed cannot select a target. Taunts and tank swaps are your decision.
- **Reporting an issue.** Include the TankWatch version, the output of `/tw diag`, whether you were in combat, and the text of any Lua error.

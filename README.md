# WoW Forever AddOns

Pick any addon below. Each ZIP installs on its own in **World of Warcraft: Forever 1.60.1** (interface **16001**). The guides cover setup, features, commands, and troubleshooting.

| Addon and guide | What it does | Try it in game | Standalone download |
| --- | --- | --- | --- |
| [AuctionPeek](AuctionPeek/README.md) | Shows auction prices per item and per stack, plus professions and recipes that use a material. Scans through your level plus two at an auctioneer. | `/apeek` | [AuctionPeek 0.3.0 ZIP](downloads/AuctionPeek-0.3.0.zip) |
| [QuestRoute](QuestRoute/README.md) | Groups quests in your log into a route you can follow one stop at a time. Choose travel distance, quest difficulty, or estimated effort as a priority. | `/qr test` to preview | [QuestRoute 0.3.0 ZIP](downloads/QuestRoute-0.3.0.zip) |
| [QuestTips](QuestTips/README.md) | Shows how to finish a quest with handwritten hints, quest-giver clues, remaining objectives, and turn-in directions. | Open a quest's details or type `/qtips` | [QuestTips 0.1.0 ZIP](downloads/QuestTips-0.1.0.zip) |
| [TankWatch](TankWatch/README.md) | Tracks visible enemies, their targets, and group threat. Alerts you when you lose aggro or your lead weakens. | `/tw test` outside combat | [TankWatch 0.2.1 ZIP](downloads/TankWatch-0.2.1.zip) |

## Install your picks

1. Download the ZIP for each addon you want. If GitHub opens the ZIP's file page, use its download button.
2. Extract each ZIP and copy the folder inside it to `World of Warcraft/_forever_/Interface/AddOns/`. For example, installing QuestRoute should give you `AddOns/QuestRoute/QuestRoute.toc`.
3. Start the Forever client, enable your picks under **AddOns** on the character-selection screen, then try the command above.

To update, close WoW and replace just that addon's folder with the one from its new ZIP. WoW keeps character settings and saved data in the separate `WTF` folder.

If you downloaded the entire repository using **Code → Download ZIP**, open the extracted repository and copy the individual addon folders you want. On Windows, you can also use the corresponding `Install-<AddonName>.ps1` script from the repository folder. Each addon's guide includes an example for a custom WoW install location.

## Maintain the collection

The top-level addon folders are the sources for the ZIPs in [downloads](downloads/). Only files inside an addon's own folder ship in its ZIP. Keep tests, packaging tools and development dependencies at the repository root.

To add an addon, create a folder such as `MyAddon/` containing `MyAddon.toc`, its runtime files and a `README.md` covering installation and first use. Set `## Version` in the manifest, then run the packager with Python 3.10 or newer.

```sh
python tools/package_addons.py MyAddon
```

Add the addon, guide and ZIP to the table above. The packager discovers folders with a matching manifest name. For an update, bump the manifest version, refresh the download links in the guides, and stage the new ZIP alongside the source. These same ZIP files can also be attached to a GitHub Release.

Running the packager with no addon name rebuilds every ZIP. The `--check` option verifies the downloads against the current addon folders.

```sh
python tools/package_addons.py
python tools/package_addons.py --check
```

The Lua 5.1 regression suite uses the optional Python package `lupa`. Run these commands from the repository root to check the addons.

```sh
python -m pip install --target .tools/runtime lupa
python tests/run.py
```

Tests in `tests/*_test.lua` run in isolated Lua environments. Players only need their chosen addon folders.

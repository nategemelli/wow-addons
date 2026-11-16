local _, ns = ...

-- Each ID identifies one quest stage, including stages that share a title.
ns.hints = {
    -- Elwynn Forest, Dun Morogh and Teldrassil
    [3904] = "Head southeast from Milly into the Northshire vineyard. Open the grape containers between the vines while watching for Defias.",
    [76] = "Follow the east road out of Goldshire to the Tower of Azora. Turn north into the foothills and follow the mine tunnel until your log records the scouting credit.",
    [3361] = "Search the troll camps southwest of Anvilmar. Felix's box, chest and bucket are separate objects you can pick up off the ground.",
    [3521] = "Check the edges of pools for lilies, look under trees or loot grell for mushrooms, and hunt Webwood Spiders for the ichor.",

    -- Durotar, Mulgore and Tirisfal Glades
    [5441] = "Look for a peon asleep under a tree in the Valley of Trials. Target the sleeper and use the Foreman's Blackjack, then move on to the next tree.",
    [790] = "Climb to the plateau south of Hana'zua. Find the scorpid named Sarkoth there and loot its claw.",
    [804] = "Head back into the Den in the Valley of Trials. Speak to Gornek inside the entrance about Hana'zua.",
    [97279] = "Look on the ground among the boars for discarded training weapons. Bring them past Gornek to Kzan Thornslash inside the Den.",
    [752] = "Walk southeast from Camp Narache to the well. Greatmother Hawkwind is waiting beside it.",
    [6395] = "Follow the road northeast of Deathknell to the ruined camp and loot Samuel Fipps. Carry his remains back to Marla's grave in the front row of the graveyard.",

    -- Zephras Isle
    [92460] = "Walk west from Ailee to the greatfather tree. Rorian the Dayseeker stands at its entrance.",
    [92461] = "Search east of Rorian in Thendal Grove. Look for Vuldren Juveniles there.",
    [92474] = "From the ledge at the top of the Thendal Grove watchtower, jump toward Rorian. Activate Walk on Air during the fall, then speak to him below.",

    -- The Barrens, Ashenvale, Stonetalon Mountains and Badlands
    [877] = "Go southeast from the Crossroads to the Stagnant Oasis. Swim down and interact with the fissure on the bottom of the pool to plant the seeds.",
    [1035] = "At Fallen Sky Lake southeast of Astranaar, hunt the Shadethicket Oracle. The moonstone is loot from that particular enemy.",
    [1069] = "In Stonetalon Mountains, check beneath the trees still standing in Windshear Crag. Open the egg clusters you find there.",
    [713] = "Bring a vial of Frost Oil to Lotwil. An alchemist can make one, and Bro'kin in the Alterac Mountains sells the recipe.",

    -- Tanaris and Un'Goro Crater
    [3161] = "Equip Marvon's Gahz'ridian Detector in your head slot. Watch the minimap for nearby ornaments as you ride or walk through Tanaris.",
    [3844] = "Dive into the pond beside the wrecked raft. Interact with the small pack lying on the bottom.",
    [4005] = "Take Eridan's Supplies to the stone circle on the eastern peninsula of Lost Rigger Cove in Tanaris. Read the Book of Aquor inside the circle and stay there until the totem forms.",

    -- Wetlands, Riverglades and Mount Hyjal
    [631] = "From the Wetlands, walk halfway across Thandol Span. Take the stairs inside the bridge down to Ebenezer Rustlocke's body and inspect it.",
    [1249] = "Watch the exit as you finish speaking to Mikhail at the Menethil inn. Follow Tapoke Jahn when he slips out and subdue him before he escapes.",
    [95642] = "In the cave beneath Sunnyglade, target a dead Twilight Ritualist and use Claire's Crystal Catalyst on the body. The ritual circles there also charge the crystal.",
    [92592] = "Look for the bone pile in the ruins east of Zet'gan. Light it with the Survivor's Torch to draw out the lich carrying the amulet.",

    -- Class quests
    [63] = "Find the shrine on the Silverpine coast west of the Sepulcher. After looting the water elemental's bracers, interact with the brazier there while carrying the remaining drops.",
    [1950] = "At the Shimmering Flats racetrack, target the chicken named \"Plucky\" Johnson near the tower and type /beckon. Speak to him when he turns human.",
    [1951] = "Enter the Library wing of Scarlet Monastery. As you head toward Arcanist Doan, check the bookshelves on your left for a book sticking out from the shelf.",

    -- Feralas, Zul'Farrak and the Sunken Temple
    [3520] = "In central or southern Feralas, use Yeh'kinya's Bramble on a fallen Vale Screecher. Then interact with the spirit that appears to earn credit.",
    [3527] = "In Zul'Farrak, loot the first tablet from Theka the Martyr by the scarabs. Hydromancer Velratha has the second tablet near Gahz'rilla's pool.",
    [3444] = "In Ratchet, look beside the doorway outside Marvon's workshop for his chest. Open it to collect the Stone Circle.",
    [3447] = "Start at the south serpent statue, then activate north, southwest, southeast, northwest and northeast in order. Defeat the guardian and inspect the Idol of Hakkar below.",
    [3528] = "Use the egg in the Sunken Temple's Sanctum of the Fallen God. Loot blood from Hakkari Bloodkeepers to extinguish the flames, then defeat the avatar and use its essence to fill the egg.",
}

-- Delivery and discovery stages may show as complete as soon as they are accepted.
ns.turnInHints = {
    [752] = ns.hints[752],
    [804] = ns.hints[804],
    [92460] = ns.hints[92460],
    [3844] = ns.hints[3844],
    [3361] = "Take all three belongings inside Anvilmar to find Felix Whindlebolt.",
    [97279] = "Walk past Gornek inside the Den. Kzan Thornslash is the weaponsmith who takes the training weapons.",
    [92474] = "Look for Rorian the Dayseeker at the entrance to the greatfather tree below the watchtower.",
    [4005] = "Carry the finished totem to J.D. Collie at Marshal's Refuge in Un'Goro Crater.",
    [631] = ns.hints[631],
    [63] = "Take the bracers and the remaining drops to the Brazier of Everfount at the coastal shrine west of the Sepulcher.",
    [3444] = "Return the Stone Circle to Marvon Rivetseeker at Broken Pillar in Tanaris.",
    [3447] = "Look below the serpent statues for the Idol of Hakkar and inspect it.",
}

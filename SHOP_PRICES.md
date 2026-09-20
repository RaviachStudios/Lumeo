# Shop Prices

All coin prices sourced from `coins_manager.gd`. Real-money prices sourced from `purchase_manager.gd` (editor-fallback USD values shown; live prices come from Google Play Console on device).

## Backgrounds (Themes)

Ordered by price, as shown in the shop.

| Item | Price |
|---|---|
| Default | Free |
| Midnight | 80 |
| Indigo | 80 |
| Sunset | 80 |
| Crimson | 80 |
| Slate | 80 |
| Skybound | 80 |
| Enchanted Forest | 350 |
| Wild West | 350 |
| Dreamy Clouds | 400 |
| Speedway | 450 |
| Neko Pop | 550 |
| Rainbow | 600 |
| Neon City | 800 |
| Dragon's Keep | 900 |
| Inferno | 1,000 |
| Enchanted Fairies | 1,000 |
| Northern Lights | 1,050 |
| Coral Reef | 1,200 |
| Deep Space | 1,600 |

### Modelled backgrounds (3D)

The eight below are a different kind of item behind the same shop card. Everything
above is a full-screen 2D shader painted behind the UI; these are 3D floors built
into the board's own viewport, with the buttons standing on them (`background_scenes.gd`,
imported from `Themes/Themes1.blend`). Ownership, purchase, equip and persistence
are the existing theme path, unchanged — `owned_themes` / `selected_theme`.

The ids carry a `bg_` prefix because `deepspace` and `aurora` are already taken by
two of the shader themes above, and these ids are what saved wallets contain.
"Deep Void" is named apart from the existing "Deep Space" for the same reason.

Priced 100 – 800, cheapest first, which is also the shop's display order
(`BackgroundScenes.ORDER`). The ladder runs from the bare floors to the fully dressed
rooms, because that is the order a player reads them in as "more".

| Item | Id | Price |
|---|---|---|
| Dark Metal | `bg_darkmetal` | 100 |
| Hexagon Floor | `bg_hexfloor` | 200 |
| Neon Grid | `bg_neongrid` | 300 |
| Circuit Board | `bg_circuit` | 400 |
| Deep Void | `bg_deepspace` | 500 |
| Volcanic | `bg_volcanic` | 600 |
| Crystal Cave | `bg_crystal` | 700 |
| Arcade Room | `bg_arcade` | 800 |

### LUME worlds (3D, animated)

The two below are the same kind of item again, imported from
`APP IDEAS/Simon/Themes2/Themes2.blend` and built by `world_scenes.gd`. Where the
eight above are FLOORS the buttons stand on, these are whole environments the
buttons stand in the middle of: a floating island arena with a rim, an underside,
mid-ground clusters and a deep abyss of scenery. Ownership, purchase, equip and
persistence are the existing theme path, unchanged.

Four more were built from the same .blend — Rainbow Sky, Inferno Abyss, Crystal
Cavern and Galaxy Realm — and cut before release. Nothing on disk ever carried
those ids.

The ids carry a `world_` prefix because both other namespaces are taken: "inferno"
and "rainbow" are shader themes and "bg_crystal" is Crystal Cave.

**Both are free.** Price 0 is the same thing Default and the four skin-bound
button frames are: the card still shows a buy button and the player still taps it
once, and that tap is still what writes the id into `owned_themes` and makes the
equip persist. They are deliberately not pre-owned — handing them out in the
default wallet would change the meaning of every save already on disk.

They still sit after the eight priced floors rather than at the front of the grid:
their order is the authored one, from the world with the least happening in frame to
the most, not a price ladder.

| Item | Id | Price | Shelf |
|---|---|---|---|
| Living Forest | `world_forest` | Free | THEMES |
| Ice Kingdom | `world_ice` | 4,000 | **SPECIAL SKINS** |
| Magical Lake | `world_lake` | 4,000 | **SPECIAL SKINS** |
| Royal Casino | `world_casino` | 4,000 | **SPECIAL SKINS** |

**Ice Kingdom, Magical Lake and Royal Casino are sold on the SPECIAL SKINS tab, not
this one.** They are the three themes that also dress the gameplay BUTTONS — the six
snowflakes carved from coloured ice (`ice_buttons.gd`,
`res://models/buttons/Ice_Snowflake_*.glb`), the six lily pads floating on the water
(`lily_buttons.gd`, `res://models/buttons/LilyPad_*.glb`) and the six moulded poker
chips lying on the felt (`chip_buttons.gd`,
`res://models/buttons/PokerChip_*.glb`), each worn automatically on all three boards
while its own world is equipped. That makes each a complete look rather than a
backdrop, and that is the shelf complete looks sell from.

**`world_casino` is NOT the same product as the `casino` wheel skin.** JACKPOT, the
skin labelled with a coin on the SPECIAL SKINS shelf, has had the internal id
`casino` since launch and is a SimonWheel look with its own shader background and
its own level-8 celebration. Royal Casino is a 3D theme with its own id, its own
buttons and its own event system. The two ids are deliberately distinct and neither
should be renamed — saved wallets contain both.

Nothing about the ITEMS changed to move them: same `CoinsManager.THEMES` entries,
same price of 0, same `owned_themes` / `selected_theme`, same buy-then-equip taps,
same save. Each card is an ordinary theme card wearing the skins tab's frame, and its
preview is the same baked still the THEMES card would have shown — the real Hard
board standing on the world, which is already wearing that world's own buttons. Each
is listed in exactly one place so a player is never offered the same id from two
cards. See `ShopScreen.SKIN_DEFS`, and `tools/ice_shop_verify.tscn` /
`tools/lake_verify.tscn` / `tools/casino_verify.tscn` for the flow tests.

Magical Lake is also the first background with no imported asset behind it at all —
no .blend, no .glb, no image: the water is a shader, the environment is generated
(`lake_world.gd`), and only the six pads come from Blender. Royal Casino is built the
same way (`casino_world.gd` for the felt, the lamp, the betting arc and the rail;
`casino_events.gd` for everything that happens on it), with only the six chips coming
from Blender. Nothing on the shop side can tell.

Pricing any of them later is a one-line edit to `CoinsManager.THEMES` — but re-sort
`BackgroundScenes.ORDER` / `WorldScenes.ORDER` and the shop's `CATEGORIES["items"]`
to match, or the tab
stops reading cheapest-first (`tools/bg_verify.tscn` fails on it). They are not
pre-owned: the player still taps Buy once, which is what writes the id into
`owned_themes` and makes the equip persist.

No existing price changed.

### LUMEO worlds (2D, animated)

Eight more, and the first backgrounds in the game with no imported asset at all:
each is a pair of GLSL functions in `lume_worlds.gd`, painted full-frame on
BackgroundManager's canvas layer behind the board — the same place every older
illustrated theme (Dreamy Clouds, Coral Reef, Neon City) already lives.

Each one is the SURFACE THE BOARD STANDS ON, drawn down the same 33.5-degree axis
the board is seen down — a candy hillside, an arcade carpet, a castle courtyard,
the sea floor — with only the things that HANG (vines, banners, kelp, balloons)
reaching into the top of the frame. The device is a panel on a table and
its own perspective says so; a world built as a backdrop behind it makes the
buttons read as pasted onto a poster.

They are 2D on purpose rather than by omission. The ten modelled backgrounds
above live inside the board's own SubViewport, and that viewport cannot see the
sky: measured with `tools/lume_frame.tscn`, every gameplay camera looks down 33.5
degrees through a ~25 degree lens, so its top ray is still ~18 degrees BELOW the
horizon and lands on the ground at z = -3.6 to -5.2. That is also why the frame is
entirely ground on every board at every aspect, which is what makes the tabletop
reading the correct one. See `lume_worlds.gd`'s header.

The `lume_` prefix keeps them clear of all three id namespaces already in use:
`clouds` / `forest` / `rainbow` are shader themes, `bg_arcade` / `bg_volcanic` are
Themes1 floors, `world_forest` is a Themes2 world. Four of the names are also
deliberately distinct from neighbours on the same tab — "Magical Forest" against
"Enchanted Forest" and "Living Forest", "Volcano Party" against "Volcanic" and
"Inferno", "Arcade Night" against "Arcade Room", "Rainbow Skyway" against
"Rainbow" — because the buy flow has no way to disambiguate two cards with one
name.

Priced 0 – 1,500 on their own ladder, cheapest first, which is also their shop
order. **Rainbow Skyway and Deep Ocean are free**, so they lead the block — which
is what keeps it reading cheapest-first. Price 0 is the same thing Default, the
two Themes2 worlds and the four skin-bound frames are: the card shows a buy button
reading FREE, the player still taps it once, and that tap is still what writes the
id into `owned_themes` and makes the equip persist. Nothing in the ownership,
purchase, equip or save path is special-cased for them.

They are deliberately not pre-owned, for the same reason nothing else here is:
handing them out in the default wallet would change the meaning of every save
already on disk. No existing price moved. They are illustrated scenes of the same class as the older shader themes
(80 – 1,600), so the ladder is set against THAT one rather than against the 3D
floors' 100 – 800, and the rung each sits on is how much world it has: an open sky
at the bottom, a whole button kingdom at the top.

| Item | Id | Price |
|---|---|---|
| Rainbow Skyway | `lume_rainbow` | Free |
| Deep Ocean | `lume_ocean` | Free |
| Candy World | `lume_candy` | 500 |
| Space Pets | `lume_space` | 600 |
| Magical Forest | `lume_forest` | 800 |
| Volcano Party | `lume_volcano` | 900 |
| Arcade Night | `lume_arcade` | 1,000 |
| Button Kingdom | `lume_kingdom` | 1,500 |

Not pre-owned, for the same reason nothing else here is: the player taps Buy once,
and that tap is what writes the id into `owned_themes`. `tools/lume_verify.tscn`
holds the entire pre-existing catalog as a frozen literal and fails if any id or
price above this block differs by one coin.

No existing price changed.

## Difficulty Unlocks

| Item | Price |
|---|---|
| Easy | Free (always unlocked) |
| Moderate | 50 |
| Hard | 80 |

## Button Frames (the modelled Medium + Hard boards)

The shop's second tab. Cosmetic bezels for the modelled boards' buttons — ONE
equipped frame is worn by every button of whichever board is in play (Medium's
five, Hard's six). There is no per-difficulty inventory. Easy is not involved: it
plays on the procedural four-segment `SimonWheel`, which has no button bezels to
dress.

The fifteen cosmetics are real Blender meshes from
`models/Button_Frame_Cosmetics.glb` (which also carries the three skin frames
below); the catalog and the loader live in
`button_frames.gd`, and ownership + selection persist on `/users/{uid}` as
`owned_frames` (a map) / `selected_frame`.

Priced 100 – 800 in four tiers — flat neon, patterned hide, polished metal, then the
five patterned looks whose light actually travels. The table below is the shop's
display order (`ButtonFrames.ORDER`), cheapest first.

| Item | Id | Price |
|---|---|---|
| Default (stock black metal) | `default` | Free — always owned |
| Purple Neon | `purple_neon` | 100 |
| Cyan Neon | `cyan_neon` | 100 |
| Magenta Neon | `magenta_neon` | 100 |
| Electric Blue | `electric_blue` | 150 |
| Emerald Neon | `emerald_neon` | 150 |
| Zebra Glow | `zebra_glow` | 250 |
| Tiger Glow | `tiger_glow` | 250 |
| Rose Gold | `rose_gold` | 350 |
| Golden Chrome | `golden_chrome` | 400 |
| Obsidian Chrome | `obsidian_chrome` | 400 |
| Arctic Glow | `arctic_glow` | 500 |
| Circuit | `circuit` | 550 |
| Aurora | `aurora` | 600 |
| Holographic | `holographic` | 700 |
| Volcanic Glow | `volcanic_glow` | 800 |

DEFAULT stays free and always owned — it is the only way back after equipping a
bought frame. Re-pricing any of the fifteen is a one-line edit to
`ButtonFrames.FRAMES`, but re-sort `ButtonFrames.ORDER` to match or the tab stops
reading cheapest-first (`tools/frame_flow_test.tscn` fails on it). Note that `FRAMES`
itself stays grouped by texture family, not by price: it documents the library, while
`ORDER` drives the tab.

These ids are stable and are what saved wallets contain. The three procedural
cosmetics that preceded them (`purple_neon`, `glow_zebra`, `glow_tiger`) were
retired when the Blender set landed: `purple_neon` kept its id, and the two `glow_*`
ids are simply unknown now, so a wallet that owned them loads with those entries
dropped and falls back to DEFAULT if one was equipped.

### Skin frames — not sold, not owned

Three further frames live in the same library and the same catalog but never appear
in this tab, because they are not merchandise: each one belongs to a Special Skin and
is worn for as long as that skin is the active look.

| Frame | Id | Comes with |
|---|---|---|
| Arcade Cabinet | `skin_arcade` | ARCADE |
| House Gold | `skin_casino` | JACKPOT |
| Fairground Lights | `skin_lunapark` | LUNA PARK |

Priority, resolved in `ButtonFrames.effective_frame` and applied by
`MemoryGameUI._refresh_frame`:

    active skin's own frame  >  the equipped cosmetic  >  DEFAULT

Nothing about this is stored. `selected_frame` never changes when a skin is equipped,
so taking the skin off hands the player's own frame straight back, and there is no
migration and no way to lose a purchase. `purchase_frame` refuses these ids and
`_apply_doc` drops them out of `owned_frames`, so a hand-edited wallet cannot equip
one either.

## Complete Wheel Skins

Ordered by price, as shown in the shop. Only Jackpot, Arcade, and Luna Park are currently released; the rest are hidden behind the "coming soon" placeholder.

All three released skins carry an exclusive button frame (see above); their shop
cards say so with an "EXCLUSIVE FRAME" chip on the preview.

| Item | Price |
|---|---|
| Jackpot (Casino) | 4,500 |
| Arcade | 5,000 |
| Luna Park | 5,500 |
| Redline (Racing) | 7,000 |
| Buccaneer (Pirate) | 7,200 |
| Nautilus (Submarine) | 7,500 |
| Phantom | 7,800 |
| Volcano (Inferno) | 8,000 |

## Coin Packs (real money, in-app purchase)

| Item | Coins | Price (USD, editor fallback) |
|---|---|---|
| Starter | 100 | $0.49 |
| Handful | 300 | $0.99 |
| Pouch | 700 | $1.99 |
| Sack | 1,000 | $2.99 |
| Chest | 5,000 | $5.99 |
| Vault | 10,000 | $9.99 |
| Treasury | 25,000 | $19.99 |
| Jackpot | 50,000 | $39.99 |

## Other In-App Purchase

| Item | Price (USD, editor fallback) | Status |
|---|---|---|
| Remove Ads | $2.99 | **Delisted** — deactivated in Play Console, removed from the shop |

Remove Ads was retired when the interstitials it suppressed were taken out of the
game. Players who already bought it keep the entitlement: Play replays the purchase
on every fresh connect and `PurchaseManager` still acknowledges it. Nothing offers
it for sale any more.

Its badge slot (bit 43, formerly "Ad-Free") was repurposed as **Mogul** — earn
250,000 coins in total — so badge completion stays reachable. Legacy owners already
have that bit set, so they keep a badge in the slot rather than losing one.

---

## Retired from the shop UI — wheel parts

The wheel-parts tab (per-part wheel colours, ring patterns, hub motifs and number fonts)
was replaced by BUTTON FRAMES. **Nothing was deleted:** the catalogs still live in
`coins_manager.gd`, previously-purchased items are still owned, and an equipped part
is still applied to the wheel by `game.gd._apply_simon_skin`. There is simply no
longer a storefront selling them, so the prices below are historical.

### Wheel — Flat Colors

Shared catalog usable on both the outer ring and center hub.

| Item | Price |
|---|---|
| Default | Free |
| Crimson | 80 |
| Emerald | 80 |
| Azure | 80 |
| Amethyst | 80 |
| Amber | 80 |
| Rose | 80 |
| Silver | 110 |
| Gold | 130 |

### Wheel — Outer Ring Patterns

Ordered by price, as shown in the shop.

| Item | Price |
|---|---|
| Pink Dots | 150 |
| Zebra | 180 |
| Candy Cane | 200 |
| Tiger | 220 |
| Sunset | 240 |
| Leopard | 250 |
| Ocean Wave | 260 |
| Rainbow | 300 |
| Starry Night | 300 |

### Wheel — Center Hub Motifs

Ordered by price, as shown in the shop.

| Item | Price |
|---|---|
| Bubbles | 150 |
| Bullseye | 160 |
| Gold Star | 180 |
| Smiley | 200 |
| Paw Print | 200 |
| Lightning | 200 |
| Swirl | 220 |
| Crescent Moon | 220 |
| Melody | 230 |
| Lucky Clover | 240 |
| Daisy | 250 |
| Harmony | 260 |
| Diamond | 280 |
| Rainbow | 300 |

### Wheel — Number Fonts

Ordered by price, as shown in the shop.

| Item | Price |
|---|---|
| Classic | Free |
| Neon | 120 |
| Sky | 120 |
| Lavender | 140 |
| Mint | 140 |
| Inferno | 150 |
| Bubblegum | 160 |
| Script | 180 |
| Candy | 200 |
| Gold | 250 |

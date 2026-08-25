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

| Item | Id | Price |
|---|---|---|
| Default (stock black metal) | `default` | Free — always owned |
| Purple Neon | `purple_neon` | 0 |
| Cyan Neon | `cyan_neon` | 0 |
| Magenta Neon | `magenta_neon` | 0 |
| Electric Blue | `electric_blue` | 0 |
| Emerald Neon | `emerald_neon` | 0 |
| Golden Chrome | `golden_chrome` | 0 |
| Rose Gold | `rose_gold` | 0 |
| Obsidian Chrome | `obsidian_chrome` | 0 |
| Zebra Glow | `zebra_glow` | 0 |
| Tiger Glow | `tiger_glow` | 0 |
| Aurora | `aurora` | 0 |
| Circuit | `circuit` | 0 |
| Holographic | `holographic` | 0 |
| Arctic Glow | `arctic_glow` | 0 |
| Volcanic Glow | `volcanic_glow` | 0 |

All fifteen ship at 0 coins deliberately. `CoinsManager.purchase_frame` still runs
the full deduct-and-save path, so re-pricing any of them is a one-line edit to
`ButtonFrames.FRAMES` — nothing else has to change.

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

## Retired from the shop UI — Simon wheel parts

The SIMON tab (per-part wheel colours, ring patterns, hub motifs and number fonts)
was replaced by BUTTON FRAMES. **Nothing was deleted:** the catalogs still live in
`coins_manager.gd`, previously-purchased items are still owned, and an equipped part
is still applied to the wheel by `game.gd._apply_simon_skin`. There is simply no
longer a storefront selling them, so the prices below are historical.

### Simon Wheel — Flat Colors

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

### Simon Wheel — Outer Ring Patterns

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

### Simon Wheel — Center Hub Motifs

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

### Simon Wheel — Number Fonts

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

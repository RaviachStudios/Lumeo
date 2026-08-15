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

## Simon Wheel — Flat Colors

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

## Simon Wheel — Outer Ring Patterns

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

## Simon Wheel — Center Hub Motifs

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

## Simon Wheel — Number Fonts

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

## Complete Wheel Skins

Ordered by price, as shown in the shop. Only Jackpot, Arcade, and Luna Park are currently released; the rest are hidden behind the "coming soon" placeholder.

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

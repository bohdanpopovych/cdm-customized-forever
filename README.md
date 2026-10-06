# CDM Customizer

An addon for **World of Warcraft: Forever** that customizes Blizzard's Cooldown Manager.

## Features

1. **Custom icon size.** Set the width and height of the Essential, Utility and Buff Icon bars independently, in Edit Mode. Icons are cropped to fit, never stretched. An optional zoom trims the artwork edges.
2. **Add any spell or item** from your spellbook or inventory to the Essential or Utility bar: a rogue's Distract, engineering grenades, potions, on-use trinkets and so on. They look and behave like native icons (cooldown swipe, charges, counts, tooltips, range and usability tint).
3. **Two extra groups:** "Additional cooldowns left" and "Additional cooldowns right", placed on either side of the Essential bar. Fill them with anything from your spellbook or inventory.

## Using it

### Resizing icons
1. Open Edit Mode and click the Essential, Utility or Buff Icons bar.
2. A CDM Customizer panel opens next to Blizzard's settings dialog.
3. Tick **Custom icon size**, then set Width, Height and Zoom. Tick **Square** to keep width and height equal.
4. Blizzard's own Icon Size, Icons per row and Padding settings keep working on top of yours.

### Adding spells and items
Open the Cooldown Manager window with **/cdm** (or **/cdmc**) and click the **CDM Customizer** tab. There is one section per group.
- **Drag** a spell from your spellbook, or an item from your bags, onto a section.
- Or type an ID, a name, `s:123` (spell) or `i:123` (item) into the Add box, or shift-click a link into it.
- Or press **Browse...** to pick from your spellbook or inventory, with search.
- Use **^ / v** to reorder, **Move** to send an entry to another group, and **x** to remove it.
- For Essential and Utility you can choose to place your entries **before** or **after** the native icons.

### The two extra groups
In Edit Mode, each group shows a labelled box. Drag it to move it, or click it for options: size, spacing, icons per line, orientation, growth and wrap direction, scale, opacity, visibility (follow Essential / always / in combat), attach to the Essential bar, global-cooldown swipe, timer numbers, tooltips. **Edit contents...** jumps to the tab above.

## Commands

| Command | What it does |
|---|---|
| `/cdmc` | Open the settings tab |
| `/cdmc status` | Version and entry counts |
| `/cdmc list` | List every entry with its index |
| `/cdmc add <essential\|utility\|left\|right> <entry>` | Add an entry |
| `/cdmc remove <group> <index>` | Remove an entry |
| `/cdmc reset <viewers\|groups\|entries\|all>` | Reset settings (asks first) |
| `/cdmc copyfrom [number]` | List other characters, or copy one's setup |
| `/cdmc debug` | Toggle debug output |

`/cdm` opens the same tab, but it is only registered if no other addon or Blizzard already uses it. If it is taken, it most likely already opens the Cooldown Manager window, where the CDM Customizer tab lives.

Settings are saved **per character**.

## Known limitations

- Icons are display-only. They aren't clickable to cast.
- Entries injected into the Essential or Utility bar hide together with that bar. If a bar has zero native icons, Blizzard hides it and ours go with it.
- Turning custom size off may need a `/reload` to restore Blizzard's exact original spacing.
- Not designed to run next to other addons that re-layout the Cooldown Manager (for example CooldownManagerCentered). Disable those.
- If the native bars hit repeated errors, CDM Customizer turns native adjustment off for the session and tells you; `/reload` re-enables it.

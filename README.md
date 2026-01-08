# CooldawnBuffTracker

An addon for tracking buffs and cooldowns in ArcheAge Classic.

## Description

CooldawnBuffTracker helps players track buff durations and ability cooldowns in an intuitive visual interface. This allows for more efficient skill usage and better action planning during combat.

Track buffs and debuffs for multiple unit types:
- **Player** - Your own buffs and cooldowns
- **Player/Mount** - Pet and mount buffs
- **Target** - Current target's buffs and debuffs

## Features

### Core Functionality
- **Multi-unit tracking** - Track buffs for player, pet/mount, and target simultaneously
- **Custom buff system** - Add any buff by ID for tracking
- **Real-time timers** - Display remaining buff duration and cooldown times
- **Visual status indicators** - Color-coded icons (green=active, red=cooldown, white=ready)

### Customization
- **Fully customizable interface** - Adjust size, position, color, and appearance
- **Icon customization** - Icon size, spacing, and positioning
- **Font customization** - Timer and label font size and color
- **Position locking** - Lock icons in place to prevent accidental movement
- **Independent settings** - Separate configuration for each unit type

### Advanced Features
- **Target buff caching** - Smart caching system for seamless target switching
- **Automatic restoration** - Returning to a previously targeted unit restores cached buff states
- **Cache cleanup** - Stale cache entries are automatically cleared after 5 minutes
- **Debug mode** - Display buff IDs in chat and tools for identifying new buffs
- **Pagination support** - Handle large lists of buffs efficiently

## Unit Types

The addon supports tracking buffs and debuffs on three different unit types:

### Player (player)
Track your own buffs and ability cooldowns. Perfect for monitoring your skill rotations and resource management.

### Player/Mount (playerpet)
Monitor buffs and effects on your pet or mount. Essential for players who rely on pet abilities or mount-specific buffs.

### Target (target)
Track active buffs and debuffs on your current target:
- **Real-time monitoring** - See all active effects on targeted units
- **Smart caching** - Buff data is preserved when switching targets
- **Automatic restoration** - Returning to a previously targeted unit restores cached states
- **Separate configuration** - Target tracking has independent position, size, and display settings

## Configuration

Addon settings are available in-game. You can customize:

### Display Settings
- **Interface position** - X and Y coordinates for each unit type
- **Icon size and spacing** - Adjust icon dimensions and gaps between them
- **Position lock/unlock** - Prevent accidental movement of buff icons

### Font Settings
- **Timer font size and color** - Customize countdown timer appearance
- **Label font size and color** - Adjust buff name text style

### Buff Management
- **Tracked buff lists** - Select which buffs to monitor for each unit type
- **Custom buff IDs** - Add any buff by ID (even if not in default list)
- **Enable/disable tracking** - Turn tracking on/off for specific unit types
- **Clear all buffs** - Remove all tracked buffs at once

### Debug Settings
- **Debug mode** - Display buff IDs in chat for identifying new buffs

## Custom Buffs

The addon includes a flexible custom buff system:
- **Add any buff by ID** - Track buffs that aren't in default list
- **Pagination support** - Easily manage large lists of buffs with page navigation
- **Auto-save** - All custom buff IDs are saved to settings automatically
- **Remove individually** - Delete specific buffs from your tracking list

## Target Tracking

The addon supports tracking buffs and debuffs on your current target:

- **Real-time monitoring**: Track active buffs/debuffs on any targeted unit
- **Smart caching**: When you switch targets, buff data is preserved in cache
- **Automatic restoration**: Returning to a previously targeted unit restores cached buff states
- **Cache cleanup**: Stale cache entries are automatically cleared after 5 minutes of inactivity
- **Separate configuration**: Target tracking has its own position, size, and display settings independent from player/mount tracking

## Buff Debugging

The addon includes tools for debugging buffs:
- **Display buff IDs in game chat** - See buff IDs when they are added or removed
- **Support for all unit types** - Debug mode works for player, pet, and target
- **Tools for adding new buffs** - Easily identify and add any buff you encounter

## Version

**Current Version:** 1.4.0

## Credits

- **Adfazer** - Original author
- **Claude** - Co-developer and contributor

## License

This project is distributed under the [MIT License](LICENSE), which allows you to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, subject to the conditions in the license.

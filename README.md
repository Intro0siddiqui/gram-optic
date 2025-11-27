# Gram-Optic: Advanced Workspace-Based Memory Management System

Gram-Optic is an innovative system that implements a three-tier memory management approach based on Hyprland workspaces. It intelligently allocates different memory strategies depending on the active workspace number.

## Features

- **Three-tier memory system**:
  - Workspaces 1-3: Pure RAM (highest performance)
  - Workspaces 4-6: Disk swap with low compression (balanced)
  - Workspaces 7-9: ZRAM with medium compression (space-efficient)

- **Automatic workspace detection**: Monitors active workspace and adjusts memory allocation accordingly

- **Configurable sizes**: Supports custom zram and disk swap sizes

## Installation

1. Clone the repository or download the scripts
2. Make the scripts executable: `chmod +x gram-optic.sh g-ram`
3. Run with appropriate permissions as needed

## Usage

The system is controlled using the `g-ram` command:

```bash
# Show help
g-ram --help

# Activate the Gram-Optic system (workspace-based memory management)
g-ram --spectre

# Show current status of the system
g-ram --spectre-status

# Start the system manually
g-ram --spectre-start

# Stop the system
g-ram --spectre-stop

# Restart the system
g-ram --spectre-restart

# Configure the system
g-ram --spectre-config
```

For specific size configuration:
```bash
# Start with custom size (e.g., 4G)
g-ram --spectre-start 4G
```

## Requirements

- Linux system with zram support
- Hyprland compositor
- sudo privileges for system-level operations
- jq or Python3 for JSON parsing (fallback mechanism included)

## How It Works

The system creates different types of swap based on the active workspace:
- Lower-numbered workspaces (1-3) are prioritized for pure RAM usage
- Mid-range workspaces (4-6) utilize disk-based swap with low compression
- Higher-numbered workspaces (7-9) use zram with medium compression for space efficiency

A monitoring daemon tracks the active workspace and logs system adjustments accordingly.

## Local Development Note

For local development, the original command `intro` is maintained as an alias to `g-ram`, 
but the public repository uses `g-ram` to maintain a professional naming convention.
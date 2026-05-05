# Genesi OS - Calamares Configuration

This repository contains the Calamares installer configuration for Genesi OS.

## Overview

Forked from [CachyOS/calamares-config](https://github.com/CachyOS/calamares-config) and customized for Genesi OS.

## Contents

- **etc/calamares/branding/genesi/** - Branding files (logos, colors, slideshow)
- **etc/calamares/modules/** - Module configuration files
- **etc/calamares/scripts/** - Installation scripts
- **etc/calamares/settings.conf** - Main Calamares configuration

## Installation

This repository is used as a submodule in the main Genesi OS build system.

## Customization

### Branding
Edit `etc/calamares/branding/genesi/branding.desc` to customize:
- Product name and version
- Window size and behavior
- Colors and styling
- Slideshow

### Scripts
Installation scripts are located in `etc/calamares/scripts/`:
- `update-mirrorlist` - Updates package mirrors
- `create-pacman-keyring` - Initializes pacman keyring
- `mkinitcpio-install-calamares` - Modified mkinitcpio hook

### Modules
Module configurations in `etc/calamares/modules/` control:
- Partitioning
- Package installation
- User creation
- Bootloader setup
- And more...

## License

GPL-3.0 (inherited from CachyOS/calamares-config)

## Credits

Based on CachyOS Calamares configuration.

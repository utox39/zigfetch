# Zigfetch

![Zig](https://img.shields.io/badge/Zig-%23F7A41D.svg?style=flat&logo=zig&logoColor=white)
![GitHub Release](https://img.shields.io/github/v/release/utox39/zigfetch)
![GitHub License](https://img.shields.io/github/license/utox39/zigfetch)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/utox39/zigfetch/build.yml)
![macOS](https://img.shields.io/badge/mac%20os-000000?style=flat&logo=macos&logoColor=F0F0F0)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)

|                     Default config                      |                     Custom config                     |
| :-----------------------------------------------------: | :---------------------------------------------------: |
| ![dafault-config](assets/screenshot-default-config.png) | ![custom-config](assets/screenshot-custom-config.png) |

---

- [Description](#description)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Configuration](#configuration)
- [Roadtrip](#roadtrip)
- [Contributing](#contributing)

## Description

Zigfetch is a minimal [neofetch](https://github.com/dylanaraps/neofetch)/[fastfetch](https://github.com/fastfetch-cli/fastfetch) like system information tool

> [!NOTE]
> For macOS users and contributors: see this [Issue](https://codeberg.org/ziglang/translate-c/issues/289)

## Requirements

- \>= [zig v0.16.0](https://ziglang.org/)

### Linux only

- [libpci](https://github.com/pciutils/pciutils)

## Installation

### Build from source

> [!NOTE]
> If you want to use the `master` version of Zig, use the `zig-master` branch

```bash
# Clone the repo
$ git clone https://github.com/utox39/zigfetch.git

# cd to the path
$ cd path/to/zigfetch

# Build zigfetch
$ zig build -Doptimize=ReleaseSafe

# Then move it somewhere in your $PATH. Here is an example:
$ mv ./zig-out/zigfetch ~/bin/
```

### Via [Homebrew](https://brew.sh/) tap

```bash
brew install utox39/tap/zigfetch
```

### Other package managers

[![Packaging status](https://repology.org/badge/vertical-allrepos/zigfetch.svg)](https://repology.org/project/zigfetch/versions)

- nixpkg: Thanks to [@heisfer](https://github.com/heisfer)
- AUR: Thanks to [@GoldBro233](https://github.com/GoldBro233)

## Usage

```bash
zigfetch
```

### Configuration

> [!IMPORTANT]
> Currently, Zig does not have a built-in library for JSON validation via JSON schema, so it is very important to follow the pattern shown in the default configuration file ([config.json](https://github.com/utox39/zigfetch/blob/main/config.json)) to avoid errors

- Create the config folder

```bash
mkdir -p ~/.config/zigfetch
```

- Create the config file

```bash
cd ~/.config/zigfetch
touch config.json
```

- Or copy the default config (preferred way)

```bash
cp /path/to/zigfetch/config.json ~/.config/zigfetch/config.json
```

#### Modules

Available modules:

- Os
- Kernel
- Uptime
- Packages
- Shell
- Cpu
- Gpu
- Ram
- Swap
- Disk
- Net
- WM (Window Manager)
- Terminal
- Locale
- Custom

| Module type |      Linux      |          macOS           | Windows |
| :---------: | :-------------: | :----------------------: | :-----: |
|     os      |       Yes       |           Yes            |   WIP   |
|   kernel    |       Yes       |           Yes            |   WIP   |
|   uptime    |       Yes       |           Yes            |   WIP   |
|  packages   |       Yes*      | Yes (Homebrew, Macports) |   WIP   |
|    shell    | Yes (bash, zsh) |     Yes (bash, zsh)      |   WIP   |
|     cpu     |       Yes       |           Yes            |   WIP   |
|     gpu     |       Yes       | Yes (Apple Silicon only) |   WIP   |
|     ram     |       Yes       |           Yes            |   WIP   |
|    swap     |       Yes       |           Yes            |   WIP   |
|    disk     |       Yes       |           Yes            |   WIP   |
|     net     |       Yes       |           Yes            |   WIP   |
|     wm      |       Yes       |           Yes            |   WIP   |
|  terminal   |       Yes       |           Yes            |   WIP   |
|   locale    |       Yes       |           Yes            |   WIP   |

\*(flatpak, nix, dpkg, pacman, xbps)

```json
  "modules": [
    {
      "type": "os",
      "key": "OS",
      "key_color": "#5E81AC"
    },
    ...
  ]
```

#### Custom module

```json
  "modules": [
    {
      "type": "custom",
      "key": "-----------",
      "key_color": "#5E81AC"
    },
    ...
  ]
```

#### Custom ASCII art

To use an ASCII art of your choice:

```json
"ascii_abs_path": "absolute_path/to/your/ascii_art.txt"
```

You can use multiple ASCII arts:

```json
"ascii_abs_path": [
  "absolute_path/to/your/ascii_art.txt",
  "absolute_path/to/your/ascii_art2.txt"
]
```

If multiple ASCII arts are specified, one will be selected pseudo-randomly.

Don't use the `~` character.

#### Images

>[!IMPORTANT]
> Only PNG images are supported.

To use images:

```json
"images": [
    {
      "abs_path": "absolute_path/to/your/image.png",
      "height": 25,
      "width": 35
    },
    {
      "abs_path": "absolute_path/to/your/image2.png",
      "height": 30,
      "width": 35
    }
]
```

Don't use the `~` character.

If multiple images are specified, one will be selected pseudo-randomly.

> [!NOTE]
> If both the `images` and `ascii_abs_path` fields are specified, the images are prioritized.

#### Username and Hostname color

To change the Username and Hostname color (HEX colors only):

```json
"username_hostname_color": "#5E81AC"
```

## Roadtrip

- [ ] Add ASCII art for each operating system and Linux distro
- [x] Add GPU info for Linux
- [x] Add packages info for Linux
- [x] Add user customization
- [ ] Add support for Windows

## Contributing

Please see [CONTIBUTING](https://github.com/utox39/zigfetch/blob/main/CONTRIBUTING.md). Thanks!

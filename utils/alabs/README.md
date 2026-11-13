# alabs-mod-desktop

This fork of MOD Desktop (branch `devel`) builds **alabs-mod-desktop**: MOD Desktop with an emulated MOD
controller, the Dwarf, the Duo X or the Duo, running the real controller firmware next to it
([mod-hw-emulator](https://github.com/sejerpz/mod-hw-emulator)). It is meant for developing HMI features
([aLabs HMI widgets](https://github.com/sejerpz/alabs-hmi-widgets) first) and is not an official MOD Audio build.

What differs from mod-audio's `main`:

| Where | What |
|---|---|
| `src/mod-ui` | [sejerpz/mod-ui](https://github.com/sejerpz/mod-ui) `devel`: HMI widgets, the HMI line over TCP, the Device addressing tab and the Display dialog with a controller attached |
| `src/mod-host` | [sejerpz/mod-host](https://github.com/sejerpz/mod-host) `devel`, built with `MOD_HMI_EMULATOR=1` (the HMI control, `/sys_msgs` over TCP) |
| `src/mod-hw-emulator` | [sejerpz/mod-hw-emulator](https://github.com/sejerpz/mod-hw-emulator) `main`, with the firmwares and mod-system-control as its own submodules |
| `src/systray` | the launcher: an **Open Emulator** button and tray entry (with `MOD_HW_EMULATOR`, the command line of the emulator), and a `MOD_DATA_DIR` given to it kept |
| `utils/alabs/` | the package script and the launchers of the package |
| `.github/workflows/alabs.yml` | the release workflow |

## Packages

Portable, for Windows (x86_64), Linux (x86_64, glibc 2.35 or later) and macOS (universal, 10.15 or later, not
signed with a Developer ID): unpacked anywhere, they run apart from an installed MOD Desktop and keep their data
(pedalboards, user files, the launcher log) in `data/` next to them.

```sh
alabs-mod-desktop/mhe-desktop.sh                 # Linux, macOS: --device duox|duo, --shared-data
alabs-mod-desktop\mhe-desktop.cmd                :: Windows: -Device duox|duo, -SharedData
```

`mhe-desktop` writes MOD Desktop's descriptor for the device, starts the emulator and then MOD Desktop; they
talk over 127.0.0.1: 9900 for mod-ui's HMI line, 9901 for mod-host's `/sys_msgs`. `SOURCES.txt` in a package
lists the commits it was built from.

## Building

```sh
git clone --recursive --shallow-submodules -b devel https://github.com/sejerpz/mod-desktop.git
cd mod-desktop
src/PawPaw/.github/workflows/bootstrap-deps.sh linux-x86_64
utils/apply-patches.sh
src/PawPaw/bootstrap-mod.sh linux-x86_64
make
utils/alabs/package.sh linux-x86_64              # alabs-mod-desktop-linux-x86_64.tar.xz
```

(`make win64` and `package.sh win64`; `make PAWPAW_TARGET=macos-universal-10.15` and
`package.sh macos-universal-10.15` on macOS.) The Dwarf firmware pins its protocol submodule by its SSH URL:
without an SSH key for GitHub, `git config --global url."https://github.com/".insteadOf git@github.com:` first.

## Releases

[.github/workflows/alabs.yml](../../.github/workflows/alabs.yml) builds the three packages on GitHub Actions
(Linux and Windows in mod-desktop's ubuntu:22.04 container, macOS on macos-15) from the submodules at the
commits pinned: run it by hand (Actions, alabs, Run workflow) for the packages as artifacts of the run, or push
a tag `alabs-mod-desktop-<version>` to also attach them to a draft release of that tag. A run whose PawPaw
dependencies are not in the cache yet only builds and caches them: run it again for the packages. The cache is
named after the commit of `src/PawPaw`.

After pushing to the forks, move the submodules and commit that:

```sh
git submodule update --remote --depth 1 src/mod-ui src/mod-host src/mod-hw-emulator
git -C src/mod-hw-emulator submodule update --init --recursive --depth 1
git commit -am "Update mod-ui, mod-host and the emulator"
```

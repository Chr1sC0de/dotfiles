#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
export HOME="$T/home space"
mkdir -p "$HOME/.config/herdr" "$HOME/.config/herdr-sessionizer"
printf keep >"$HOME/.config/herdr/keep"
bash utils/dotfiles-install.sh
[[ -L $HOME/.config/herdr/config.toml ]]
[[ -L $HOME/.config/herdr-sessionizer/config.toml && -f $HOME/.config/herdr-sessionizer/config.toml ]]
[[ $(readlink "$HOME/.config/herdr-sessionizer/config.toml") == "$ROOT/config/herdr-sessionizer/config.toml" ]]
[[ $(cat "$HOME/.config/herdr/keep") == keep ]]
[[ ! -e $HOME/.config/herdr/herdr ]]
for name in herdr-sessionizer herdr-sessionizer-preview; do
    [[ -x $HOME/.local/bin/$name && -L $HOME/.local/bin/$name ]]
done
before=$(stat -c %i "$HOME/.local/bin/herdr-sessionizer")
bash utils/dotfiles-install.sh --force
[[ $(stat -c %i "$HOME/.local/bin/herdr-sessionizer") == "$before" ]]
bash utils/dotfiles-uninstall.sh
[[ ! -L $HOME/.local/bin/herdr-sessionizer ]]
[[ ! -L $HOME/.config/herdr-sessionizer/config.toml ]]
[[ $(cat "$HOME/.config/herdr/keep") == keep ]]
for kind in file directory symlink; do
    dest="$HOME/.local/bin/herdr-sessionizer"
    case $kind in
    file) echo keep >"$dest" ;;
    directory) mkdir "$dest" ;;
    symlink) ln -s "$T/foreign" "$dest" ;;
    esac
    if bash utils/symlink-create.sh herdr-sessionizer; then exit 1; fi
    bash utils/symlink-remove.sh herdr-sessionizer
    [[ -e $dest || -L $dest ]]
    if [[ $kind == symlink ]]; then
        bash utils/symlink-create.sh herdr-sessionizer --force
        [[ $(readlink "$dest") == "$ROOT/my-profile/scripts/herdr-sessionizer/picker.sh" ]]
    else
        if bash utils/symlink-create.sh herdr-sessionizer --force; then exit 1; fi
        [[ ! -L $dest ]]
    fi
    rm -rf -- "$dest"
done
if bash utils/symlink-create.sh sessionizer; then exit 1; fi
# A relative link to this repository is owned and can be removed.
ln -s "$(realpath --relative-to="$HOME/.local/bin" "$ROOT/my-profile/scripts/herdr-sessionizer/picker.sh")" "$HOME/.local/bin/herdr-sessionizer"
bash utils/symlink-remove.sh herdr-sessionizer
[[ ! -L $HOME/.local/bin/herdr-sessionizer ]]
# The old partial match accepted this directory and nested herdr/herdr.
if bash utils/symlink-create.sh config/herdr; then exit 1; fi
[[ ! -e $HOME/.config/herdr/herdr ]]
for target in config/herdr/config.toml config/herdr-sessionizer/config.toml; do
    dest="$HOME/.$target"
    for kind in file directory directory-link; do
        case $kind in
        file) printf keep >"$dest" ;;
        directory)
            mkdir "$dest"
            printf keep >"$dest/keep"
            ;;
        directory-link)
            mkdir -p "$T/foreign-dir"
            ln -s "$T/foreign-dir" "$dest"
            ;;
        esac
        if bash utils/symlink-create.sh "$target"; then exit 1; fi
        bash utils/symlink-remove.sh "$target"
        if [[ $kind == directory-link ]]; then
            bash utils/symlink-create.sh "$target" --force
            [[ $(readlink "$dest") == "$ROOT/$target" ]]
            [[ ! -e $T/foreign-dir/config.toml ]]
        else
            if bash utils/symlink-create.sh "$target" --force; then exit 1; fi
            if [[ $kind == file ]]; then
                [[ $(cat "$dest") == keep ]]
            else
                [[ $(cat "$dest/keep") == keep && ! -e $dest/config.toml ]]
            fi
        fi
        rm -rf -- "$dest"
    done
    bash utils/symlink-create.sh "$target"
    before=$(stat -c %i "$dest")
    bash utils/symlink-create.sh "$target" --force
    [[ $(stat -c %i "$dest") == "$before" ]]
    bash utils/symlink-remove.sh "$target"
done
# A destination created after the guard must still never receive a nested link.
# Invoked by the installer subprocess through the exported function.
# shellcheck disable=SC2329
mkdir() {
    command mkdir "$@"
    command mkdir "$HOME/.config/herdr/config.toml"
}
export -f mkdir
if bash utils/symlink-create.sh config/herdr/config.toml; then exit 1; fi
unset -f mkdir
[[ -d $HOME/.config/herdr/config.toml ]]
[[ ! -e $HOME/.config/herdr/config.toml/config.toml ]]
printf 'symlink tests passed\n'

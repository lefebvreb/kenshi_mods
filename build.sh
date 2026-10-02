#!/usr/bin/env bash
# Build KenshiLib plugins on Linux using the Visual C++ 2010 x64 compiler under Wine.
#
# Usage: ./build.sh [ModName ...]   (default: every directory containing a .vcxproj)
#
# Expects the toolchain at ../toolchain (override with TOOLCHAIN=/path):
#   msvc10/VC, msvc10/SDK          - VC10 compilers + Windows SDK 7.1
#   deps/boost_1_60_0              - Boost 1.60 headers + vc100 libs
#   kenshilib-<ver>/KenshiLib.lib  - must match the KenshiLib headers in ../KenshiLib
#   wine/                          - dedicated Wine prefix
# The built DLL is copied into <Mod>/<Mod>/, next to RE_Kenshi.json, and that folder
# is then rsynced into Kenshi's mods folder (override with KENSHI_MODS_DIR=/path,
# or set it empty to skip). *.log files in the game copy are left alone.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
toolchain="${TOOLCHAIN:-$here/../toolchain}"
toolchain="$(cd "$toolchain" && pwd)"
kenshilib_dir="${KENSHILIB_DIR:-$here/../KenshiLib}"
kenshilib_dir="$(cd "$kenshilib_dir" && pwd)"
kenshilib_lib="${KENSHILIB_LIB:-$toolchain/kenshilib-0.5.1}"
kenshi_mods_dir="${KENSHI_MODS_DIR-$here/../../common/Kenshi/mods}"

export WINEPREFIX="$toolchain/wine"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree,mshtml="
# link.exe spawns a persistent mspdbsrv.exe that holds our stdout/stderr open;
# the prefix is dedicated to this toolchain, so just shut it down when done.
trap 'wineserver -k 2>/dev/null || true' EXIT

winpath() { echo "Z:${1//\//\\}"; }

vc="$(winpath "$toolchain/msvc10/VC")"
sdk="$(winpath "$toolchain/msvc10/SDK")"
boost="$(winpath "$toolchain/deps/boost_1_60_0")"
klib="$(winpath "$kenshilib_dir")"

export WINEPATH="$vc\\bin\\amd64"
export INCLUDE="$vc\\include;$sdk\\Include;$klib\\Include;$klib\\Include\\ogre;$boost"
export LIB="$vc\\lib\\amd64;$sdk\\Lib\\x64;$(winpath "$kenshilib_lib");$klib\\Libraries;$klib\\Libraries\\ogre;$boost\\stage\\lib"

# Wine's GPU probing spams stderr; drop that noise only.
quiet() { "$@" 2> >(grep -v -e '^MESA' -e 'pci id for fd' >&2); }

build_mod() {
	local mod="$1"
	local src_dir="$here/$mod"
	local out_dir="$here/build/$mod"
	mkdir -p "$out_dir"

	local sources=()
	while IFS= read -r f; do sources+=("$(winpath "$src_dir/$f")"); done \
		< <(grep -oP '<ClCompile Include="\K[^"]+' "$src_dir/$mod.vcxproj")

	echo "==> $mod"
	(
		cd "$out_dir"
		# Mirrors the Release|x64 config of the .vcxproj.
		quiet wine cl.exe /nologo /c /W3 /O2 /Oi /GL /Gy /EHsc /MD /Z7 \
			/DNDEBUG /D_CONSOLE /D_WINDLL /D_UNICODE /DUNICODE \
			"${sources[@]}"
		quiet wine link.exe /nologo /DLL /LTCG /OPT:REF /OPT:ICF /DEBUG /SUBSYSTEM:CONSOLE \
			"/OUT:$mod.dll" "/PDB:$mod.pdb" ./*.obj \
			kenshilib.lib OgreMain_x64.lib
	)

	if [[ -d "$src_dir/$mod" ]]; then
		cp "$out_dir/$mod.dll" "$src_dir/$mod/"
		echo "    -> $mod/$mod/$mod.dll"
		install_mod "$mod"
	fi
}

install_mod() {
	local mod="$1"
	[[ -n "$kenshi_mods_dir" ]] || return 0
	if [[ ! -d "$kenshi_mods_dir" ]]; then
		echo "    (skipping sync: $kenshi_mods_dir not found)"
		return 0
	fi
	if [[ -L "$kenshi_mods_dir/$mod" ]]; then
		echo "    (skipping sync: $kenshi_mods_dir/$mod is a symlink)" >&2
		return 0
	fi
	rsync -a --delete --exclude '*.log' "$here/$mod/$mod/" "$kenshi_mods_dir/$mod/"
	echo "    -> $(realpath "$kenshi_mods_dir/$mod")"
}

mods=("$@")
if [[ ${#mods[@]} -eq 0 ]]; then
	for p in "$here"/*/*.vcxproj; do mods+=("$(basename "$(dirname "$p")")"); done
fi
for m in "${mods[@]}"; do build_mod "$m"; done

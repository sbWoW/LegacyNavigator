#!/bin/sh
# Fetch third-party libs into Libs/ (same sources as .pkgmeta). Idempotent: re-run to update.
set -e
cd "$(dirname "$0")/.."
ACE=https://github.com/WoWUIDev/Ace3.git
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# get <repo-url> <subdir-or-.> <dest-name>
get() {
  d="$tmp/$(echo "$1" | tr '/:' '__')"
  [ -d "$d" ] || git clone -q --depth 1 "$1" "$d"
  rm -rf "Libs/$3"; mkdir -p Libs
  cp -R "$d/$2" "Libs/$3"
  rm -rf "Libs/$3/.git"
  echo "ok Libs/$3"
}

for l in LibStub CallbackHandler-1.0 AceAddon-3.0 AceConsole-3.0 AceDB-3.0 AceEvent-3.0 AceTimer-3.0; do
  get "$ACE" "$l" "$l"
done
get https://github.com/tekkub/libdatabroker-1-1.git . LibDataBroker-1.1
# LibDBIcon: official WowAce SVN (only SVN exception); keep local copy if svn is missing
if command -v svn >/dev/null 2>&1; then
  svn export -q https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0 "$tmp/LibDBIcon-1.0"
  rm -rf Libs/LibDBIcon-1.0 && mv "$tmp/LibDBIcon-1.0" Libs/LibDBIcon-1.0
  echo "ok Libs/LibDBIcon-1.0 (svn)"
else
  echo "skip Libs/LibDBIcon-1.0: svn not installed, keeping existing local copy" >&2
fi

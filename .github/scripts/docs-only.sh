#!/usr/bin/env bash
# Reads changed paths on stdin; prints true when a pull request touches only docs, so CI can skip the ROM shards.
while IFS= read -r path || [ -n "$path" ]; do
  case $path in
    lib/*|test/*|tools/*|data/*|bin/*|.github/*) echo false; exit ;;
    docs/*|*.md) found=1 ;;
    *) echo false; exit ;;
  esac
done
[ -n "${found:-}" ] && echo true || echo false

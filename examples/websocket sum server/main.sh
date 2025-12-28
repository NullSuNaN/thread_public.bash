#! /bin/bash
dir="${0%/*}"
[ "$dir" ] || {
  echo 'Unable to locate the executable file!'
  exit 1
}
trap '' SIGINT
. "$dir"/../../thread_public.bash
tpubCreate 3 4
echo "${!tpubMapFd1[@]}"
websocketd --port="${1-3000}" "$dir"/instance.sh
# Outdated way to end
tpubRelease main
#!/usr/bin/env bash

dir="${0%/*}"
[ "$dir" ] || {
  echo 'Unable to locate the executable file!'
  exit 1
}
trap '' SIGINT
source "$dir"/../thread_public.bash

tpubCreate 10 11 main
trap tpubReleaseAll EXIT

tpubExp main msg=hello additional_msg=' LOL'
tpubExp main @msg @additional_msg $'\n'
sleep 1

echo I mean
sleep 1

# Unset additional_msg and ` UwU` is ignored
tpubSet main additional_msg ' UwU' U
tpubExp main @msg @additional_msg $'\n'
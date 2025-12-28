#! /bin/bash

dir="${0%/*}"
[ "$dir" ] || {
  echo 'Unable to locate the executable file!'
  exit 1
}
trap '' SIGINT
source "$dir"/../thread_public.bash

tpubCreate 10 11 main
trap tpubReleaseAll EXIT

tpubExp main name=Linus hello " " 'world ' @name '!!' $':)\n'

tpubExp main \
  counter=10 \
  msg=hello \
  "Value: " \
  '$counter' \
  arr='(' a b c ')'
tpubExp main \
  ", size" \
  "_eq==" \
  @_eq \
  @{#arr[@]}
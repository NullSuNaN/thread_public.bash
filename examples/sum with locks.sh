#!/usr/bin/env bash

dir="${0%/*}"
[ "$dir" ] || {
  echo 'Unable to locate the executable file!'
  exit 1
}
trap '' SIGINT
source "$dir"/../thread_public.bash

tpubCreate 10 11 main

tpubSet main counter 0

tasks=()
for i in {1..5}; do
  (
    echo "TASK $i"
    tpubLock main counter
    tpubGetAs val main counter
    tpubSet main counter "$((val + 1))"
    tpubUnlock main counter
    echo "TASK $i END"
  ) &
  tasks[${#tasks[@]}]="$!"
done
echo "waiting"
wait "${tasks[@]}"

echo "Final value:" "$(tpubGet main counter)"

tpubReleaseAll
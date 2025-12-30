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

tpubExp main a='(' 1 1 ')'

tasks=()
for i in {2..7}; do
  (
    while :;do
      echo "TASK $i"
      tpubLock main a
      tpubGetAs v1 main a[$((i - 1))]
      tpubGetAs v2 main a[$((i - 2))]
      [ -z "$v1" ] || [ -z "$v2" ] && {
        tpubUnlock main a
        continue
      }
      tpubSet main a[$i] "$((v1 + v2))"
      tpubUnlock main a
      echo "TASK $i END"
      break
    done
  ) &
  tasks[${#tasks[@]}]="$!"
done
echo "waiting"
wait "${tasks[@]}"

echo "Final value:" "$(tpubGet main a A)"
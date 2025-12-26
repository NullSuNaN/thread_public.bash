#!/bin/bash

source ../thread_public.bash

tpubCreate 10 11 main

tpubSet main counter 0

tasks=()
for i in {1..5}; do
  (
    echo "TASK $i"
    # no lock between get and set, so the result may not be exact 5
    val="`tpubGet main counter`"
    # tpubGet main counter
    tpubSet main counter "$((val + 1))"
  ) &
  tasks[${#tasks[@]}]="$!"
done
echo "waiting"
wait "${tasks[@]}"

echo "Final value:" "$(tpubGet main counter)"

tpubReleaseAll
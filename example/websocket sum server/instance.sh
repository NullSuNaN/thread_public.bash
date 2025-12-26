#! /bin/bash
dir="${0%/*}"
[ "$dir" ] || {
  echo 'INTERNAL_ERROR'
  exit 1
}
. "$dir"/../../thread_public.bash
# with the websocketd layer, bash variables won't inherit
tpubInherit 3 4 main
isNumber() {
  local v="$1"
  [ "$v" == 0 ] && return 0
  [ "${v:0:1}" == '-' ] && v="${v:1}"
  [[ "$v" =~ [^0-9] ]] && return 1
  [[ "${v:0:1}" != [1-9] ]] && return 1
  return 0
}
echo 'HELLO'
while read -r l;do
  [ "$l" ] || continue
  [ "$l" == kill ] && {
    {
      sleep 1
      kill $(ps -o ppid= $$)
    } &
    exit 0
  }
  isNumber "$l" && {
    res=$(("`tpubGet main num`"+l))
    tpubSet main num "$res"
    echo 'SUM_IS '"$res"
    true
  } || {
    echo 'INVALID_NUMBER '"$l"
  }
done
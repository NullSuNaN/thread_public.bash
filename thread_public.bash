#! /bin/echo This Library should be sourced by a BASH script:
# Create Thread Public read-write variables in bash
# This file MUST BE INCLUDED IN THE MAIN THREAD
# Make sure the env don't have $THREAD_PUBLIC_INCLUDED by default, since having it will prevent the lib from loading
[ -v THREAD_PUBLIC_INCLUDED ] || {
  readonly THREAD_PUBLIC_INCLUDED=
  # fd1: lock stream
  # fd2: data stream
  # DATA STREAM COMMANDS
  # G$tid $getTarget $vName\0 - a c2s GET request
  # S$tid $vName\0$vType $vVal\0 - a c2s SET request
  # R$tid $vVal\0 - a s2c GET result
  # r$tid\0 - a s2c SET result
  # l$tid $mode $var\0 - a c2s LOCK request
  # L$tid $suc\0 - a s2c LOCK result
  # W$tid\0 - a s2c WAIT result
  # Q\0 - a c2all RELEASE request
  declare -Ag tpubMapFd1= tpubMapFd2=
  ## tpubCreate <fd1> <fd2> [<name>] [<tempFile>]
  #  Create a thread public variable container
  #  Because the limitation of bash, each container requires 2 file descriptors
  #  Note: threads created before tpubCreate cannot access the container, so just create at the start of the program!
  #  Warn: When the program ends, RELEASE ALL THE 
  #  @arg 1 - file descriptor 1 to bind
  #  @arg 2 - file descriptor 2 to bind
  #  @arg 3 - (Optional, default: 'main')container name to create
  #  @arg 4 - (Optional)temporary file
  #  @return 0 when success
  #  @return 1 illegal arguments
  #  @return 2 on file system error
  #  @return 3 on file descriptor error
  #  @return 4 when the name is already taken
  tpubCreate() {
    local fd1="$1" fd2="$2" name="${3-main}"
    local tmpf="${4-"/tmp/$$.$fd1.$fd2.tpub.fifo"}"
    [[ "$fd1" == [0-9]* ]] || return 1
    [[ "$fd2" == [0-9]* ]] || return 1
    [[ "${tpubMapFd1["f$name"]}" ]] && return 4
    local fd=
    for fd in "$fd1" "$fd2";do
      mkfifo "$tmpf" || return 2
      eval 'exec '"$fd"'<> "$tmpf"' || {
        rm -- "$tmpf" || return 2
        return 3
      }
      rm -- "$tmpf" || return 2
    done
    tpubMapFd1["f$name"]="$fd1"
    tpubMapFd2["f$name"]="$fd2"
    echo >&"$fd1"
    _tpubHostThread "$fd1" "$fd2" &
    return 0
  }
  ## tpubInherit <fd1> <fd2> [<name>]
  #  Can be used when the file descriptor is public but variable(not exported) aren't.
  #  @arg 1 - file descriptor 1 to bind
  #  @arg 2 - file descriptor 2 to bind
  #  @arg 3 - (Optional, default: 'main')container name to create
  #  @return 0 when success
  #  @return 1 illegal arguments
  #  @return 4 when the name is already taken
  tpubInherit() {
    local fd1="$1" fd2="$2" name="${3-main}"
    [[ "$fd1" == [0-9]* ]] || return 1
    [[ "$fd2" == [0-9]* ]] || return 1
    [[ "${tpubMapFd1["f$name"]}" ]] && return 4
    tpubMapFd1["f$name"]="$fd1"
    tpubMapFd2["f$name"]="$fd2"
    return 0
  }
  ## tpubRelease [<name>]
  #  arg 1 - (Optional, default: 'main')target to release
  #  return 1 if the container does not exist
  tpubRelease() {
    local name="${1-main}"
    local fd1="${tpubMapFd1["f$name"]}"
    [ "$fd1" ] || return 1
    local fd2="${tpubMapFd2["f$name"]}"
    local lIFS="$IFS"
    IFS=''
    unset tpubMapFd1["f$name"] tpubMapFd2["f$name"]
    read -rN 1 <&"$fd1"
    echo -ne 'Q\0' >&"$fd2"
    echo A >&"$fd1"
    local fd=
    for fd in "$fd1" "$fd2";do
      eval 'exec '"$fd"'<&-'
      eval 'exec '"$fd"'>&-'
    done
    IFS="$lIFS"
  }
  ## tpubReleaseAll
  #  Release all the containers created, MUST BE CALLED AFTER THE PROGRAM EXIT
  tpubReleaseAll(){
    local i=
    for i in "${!tpubMapFd1[@]}";do
      [ "$i" != 0 ] &&
      tpubRelease "${i:1}"
    done
  }
  ## _tpubIgnore <dataFd> <op>
  #  Ignore a message and send it back
  #  IFS='' is required
  _tpubIgnore() {
    local fd="$1" op="$2" cl
    case "$op" in
      S)
        read -rd $'\0' cl
        echo -n "$op$cl" >&"$fd2"
        echo -ne '\0' >&"$fd2"
        read -rd $'\0' cl
        echo -n "$cl" >&"$fd2"
        echo -ne '\0' >&"$fd2"
        ;;
      *)
        read -rd $'\0' cl
        echo -n "$op$cl" >&"$fd2"
        echo -ne '\0' >&"$fd2"
        ;;
    esac <&"$fd2"
  }
  ## _tpubReadLock <lockFd> <refuseLockType>
  #  IFS='' is required
  #  Fail if the fd is down
  _tpubReadLock() {
    local fd1="$1" lt="$2" lock
    while read -rN 1 lock <&"$fd1";do
      [ "$lock" != "$lt" ] && return 0
      echo -n "$lt" >&"$fd1"
      sleep 0.05
      continue
    done
    return 1
  }
  _tpubHostCheckLock() {
    local vName="${1%%'['*}" tid="$2"
    [ -v locks[l"$vName"] ] && [ "${locks[l"$vName"]}" != "$tid" ]
  }
  _tpubHostThread() {
    trap '' SIGINT
    trap '' SIGABRT
    local fd1="$1" fd2="$2" lock
    IFS=''
    unset locks
    local tid getTarget vName vType vVar mode suc curVar
    declare -Ag locks
    while _tpubReadLock "$fd1" $'\n';do
      lock=h
      {
        read -rN 1 op
        case "$op" in
          G)
            read -rd ' ' tid
            read -rd ' ' getTarget
            read -rd $'\0' vName
            if _tpubHostCheckLock "$vName" "$tid"; then
              # Locked, wait
              echo -n "W$tid" >&"$fd2"
              echo -ne '\0' >&"$fd2"
            else
              declare -n "curVar=tpubHostVar_$vName"
              local res=
              case "$getTarget" in
                S) # There is a bug of bash itself so I cannot just use ${#curVar}
                  res="$curVar"
                  res="${#res}"
                  ;;
                L) res="${#curVar[@]}" ;;
                A)
                  IFS=' '
                  res="${curVar[*]}"
                  IFS='';;
                K)
                  IFS=' '
                  res="${!curVar[*]}"
                  IFS='';;
                *) res="$curVar" ;;
              esac
              echo -n "R$tid $res" >&"$fd2"
              echo -ne '\0' >&"$fd2"
            fi
            lock=$'\n'
            ;;
          S)
            read -rd ' ' tid
            read -rd $'\0' vName
            read -rd ' ' vType
            read -rd $'\0' vVar
            if _tpubHostCheckLock "$vName" "$tid"; then
              # Locked, wait
              echo -n "W$tid" >&"$fd2"
              echo -ne '\0' >&"$fd2"
            else
              declare -n "curVar=tpubHostVar_$vName"
              case "$vType" in
                v) curVar="$vVar";;
                a)
                  declare -a "tpubHostVar_$vName"'=()'
                  curVar[0]="$vVar";;
                A)
                  declare -A "tpubHostVar_$vName"'=()';;
                U)
                  unset "tpubHostVar_$vName";;
              esac
              echo -n "r$tid" >&"$fd2"
              echo -ne '\0' >&"$fd2"
            fi
            lock=$'\n'
            ;;
          l)
            read -rd ' ' tid
            read -rd ' ' mode
            read -rd $'\0' vName
            if _tpubHostCheckLock "$vName" "$tid"; then
              # Locked, wait
              echo -n "W$tid" >&"$fd2"
              echo -ne '\0' >&"$fd2"
            else
              suc='-'
              if [ -v locks[l"$vName"] ]; then
                [ "$mode" == U ] && {
                  unset locks[l"$vName"]
                  suc='+'
                }
              else
                [ "$mode" == L ] && {
                  locks[l"$vName"]="$tid"
                  suc='+'
                }
              fi
              echo -n "L$tid $suc" >&"$fd2"
              echo -ne '\0' >&"$fd2"
            fi
            lock=$'\n'
            ;;
          Q)
            echo -ne 'Q\0' >&"$fd2"
            echo A >&"$fd1"
            exit 0;;
          *) _tpubIgnore "$fd2" "$op";;
        esac
      } <&"$fd2"
      echo -n "$lock" >&"$fd1"
    done
  }
  ## _tpubProcessWait <lockFd> <dataFd> <lock>
  #  IFS='' is required
  _tpubProcessWait() {
    local fd1="$1" fd2="$2" lock="$3" tid
    
    read -rd $'\0' tid <&"$fd2"
    if [ "$tid" == "$BASHPID" ]; then
      sleep 0.05
      return 1
    else
      echo -n "W$tid" >&"$fd2"
      echo -ne "\0" >&"$fd2"
      return 0
    fi
  }
  ## tpubGetAs <resultVar> <container> <var> [<type>]
  #  @arg 1 - result var name
  #  @arg 2 - container name, like `main`
  #  @arg 3 - var name
  #  @arg 4 - (Optional, default: '')get type, S for size(${#a}), L for length(${#a[@]}), (EMPTY) for value($a)
  #  Get the thread public var, and put to a regular thread-own resultVar
  #  Note:
  #    If type(arg 4) is `A` or `N`, you will still get a string of the result,
  #    and this is an illegal operation and will be implemented and change its behavior.
  #  @return 0 when success
  #  @return 1 illegal arguments
  #  @return 2 if the container does not exist
  tpubGetAs() {
    # Parse Arguments
    local varToSet="$1"
    shift || return 1
    local fd1="${tpubMapFd1["f$1"]}"
    [ "$fd1" ] || return 2
    local fd2="${tpubMapFd2["f$1"]}"
    local var="$2" type="$3"
    [[ "$3" =~ ' ' ]] && return 1
    # Send Request
    local lIFS="$IFS" resend=0
    IFS=''
    while :;do
      resend=0
      _tpubReadLock "$fd1" h || return 2
      echo -n "G$BASHPID $type $var" >&"$fd2"
      echo -ne '\0' >&"$fd2"
      echo -n h >&"$fd1"
      # Wait for Response
      local tid= res= cl= op= lock=$'\n'
      while read -rN 1 lock <&"$fd1";do
        {
          read -rN 1 op
          case "$op" in
            R)
              read -rd ' ' tid
              read -rd $'\0' res
              [ "$tid" == "$BASHPID" ] && {
                echo -n "$lock" >&"$fd1"
                declare -n "resVar=$varToSet"
                resVar="$res"
                IFS="$lIFS"
                return 0
                true
              } || {
                echo -n "R$tid $res" >&"$fd2"
                echo -ne '\0' >&"$fd2"
              };;
            Q)
              echo -ne 'Q\0' >&"$fd2"
              echo -n A >&"$fd1"
              IFS="$lIFS"
              tpubRelease "$1"
              return 2;;
            W) _tpubProcessWait "$fd1" "$fd2" "$lock" || resend=1 ;;
            *) _tpubIgnore "$fd2" "$op";;
          esac
        } <&"$fd2"
        echo -n "$lock" >&"$fd1"
        [ "$resend" == 1 ] && break
      done
      [ "$resend" == 1 ] && continue
      break
    done
    IFS="$lIFS"
    return 2
  }
  ## tpubGet <container> <var> [<type>]
  #  @arg 1 - container name, like `main`
  #  @arg 2 - var name
  #  @arg 3 - (Optional, default: '')get type, S for size(${#a}), L for length(${#a[@]}), A for all(IFS=' ';${a[*]}}), N for names(IFS=' ';${!a[@]}), (EMPTY) for value($a)
  #  Output the value
  #  @return 0 when success
  #  @return 1 illegal arguments
  #  @return 2 if the container does not exist
  #  @return 3 if some silly thing readonly'd the internal `__tpub__Result`
  tpubGet() {
    unset __tpub__Result || return 3
    local __tpub__Result=
    tpubGetAs __tpub__Result "$@"
    local rv="$?" 
    echo -n "$__tpub__Result"
    return $rv
  }
  ## tpubSet <container> <var> <val> [<type>]
  #  @arg 1 - container name, like `main`
  #  @arg 2 - var name
  #  @arg 3 - value to set
  #  @arg 4 - (Optional, can be [vaA])v: normal, a: array, A: map, u:unset
  #  Output the value
  #  @return 0 when success
  #  @return 1 illegal arguments
  #  @return 2 if the container does not exist
  tpubSet()  {
    # Parse Arguments
    local fd1="${tpubMapFd1["f$1"]}"
    [ "$fd1" ] || return 2
    local fd2="${tpubMapFd2["f$1"]}"
    local var="$2" value="$3" type="${4-v}"
    [[ "$type" != [vaAU] ]] && return 1
    # Send Request
    local lIFS="$IFS" resend=0
    IFS=''
    while :;do
      resend=0
      _tpubReadLock "$fd1" h || return 2
      echo -n "S$BASHPID $var" >&"$fd2"
      echo -ne '\0' >&"$fd2"
      echo -n "$type $value" >&"$fd2"
      echo -ne '\0' >&"$fd2"
      echo -n h >&"$fd1"
      # Wait for Response
      local tid= res= cl= op= lock=$'\n'
      while read -rN 1 lock <&"$fd1";do
        {
          read -rN 1 op
          case "$op" in
            Q)
              echo -ne 'Q\0' >&"$fd2"
              echo -n A >&"$fd1"
              IFS="$lIFS"
              tpubRelease "$1"
              return 2;;
            r)
              read -rd $'\0' tid
              [ "$tid" == "$BASHPID" ] && {
                echo -n "$lock" >&"$fd1"
                IFS="$lIFS"
                return 0
              } || {
                echo -n "r$tid" >&"$fd2"
                echo -ne '\0' >&"$fd2"
              };;
            W) _tpubProcessWait "$fd1" "$fd2" "$lock" || resend=1 ;;
            *) _tpubIgnore "$fd2" "$op";;
          esac
        } <&"$fd2"
        echo -n "$lock" >&"$fd1"
        [ "$resend" == 1 ] && break
      done
      [ "$resend" == 1 ] && continue
      break
    done
    IFS="$lIFS"
    return 2
  }
  # _tpubLock <mode> <container> [<var>] 
  _tpubLock() {
    # Parse Arguments
    local mode="$1"
    local fd1="${tpubMapFd1["f$2"]}"
    [ "$fd1" ] || return 2
    local fd2="${tpubMapFd2["f$2"]}"
    # Send Request
    local lIFS="$IFS" resend=0
    IFS=''
    while :;do
      resend=
      _tpubReadLock "$fd1" h || return 2
      echo -n "l$BASHPID $mode " >&"$fd2"
      local var="$3"
      [ -z "$var" ] && return 1
      [[ "$var" =~ ['[]'] ]] && return 1
      echo -n "$var" >&"$fd2"
      echo -ne '\0' >&"$fd2"
      echo -n h >&"$fd1"
      # Wait for Response
      # Return 1 on illegal args, 2 on container not exist, 3 on fail to (un)lock
      local tid= res= cl= op= lock=$'\n'
      while read -rN 1 lock <&"$fd1";do
        {
          read -rN 1 op
          case "$op" in
            L)
              read -rd ' ' tid
              read -rd $'\0' suc
              [ "$tid" == "$BASHPID" ] && {
                echo -n "$lock" >&"$fd1"
                IFS="$lIFS"
                [ "$suc" == '+' ] && return 0
                return 3
                true
              } || {
                echo -n "L$tid $suc" >&"$fd2"
                echo -ne '\0' >&"$fd2"
              };;
            Q)
              echo -ne 'Q\0' >&"$fd2"
              echo -n A >&"$fd1"
              IFS="$lIFS"
              tpubRelease "$1"
              return 2;;
            W) _tpubProcessWait "$fd1" "$fd2" "$lock" || resend=1 ;;
            *) _tpubIgnore "$fd2" "$op";;
          esac
        } <&"$fd2"
        echo -n "$lock" >&"$fd1"
        [ "$resend" == 1 ] && break
      done
      [ "$resend" == 1 ] && continue
      break
    done
    IFS="$lIFS"
    return 2
  }
  #  tpubLock <container> <var>
  #  Lock a variable of a container
  #
  #  When locked, only the host thread and the lock owner can access the container
  #  Must have a tpubUnlock after this in the same thread to release the lock!
  #  @return 0 when success
  #  @return 1 illegal arguments
  #  @return 2 if the container does not exist
  #  @return 3 if it failed to lock(already locked)
  tpubLock() {
    _tpubLock L "$@"
  }
  #  tpubUnlock <container> <var>
  #  Unlock a variable of a container
  #
  #  When locked, only the host thread and the lock owner can access the container
  #  Must do this after tpubLock in the same thread to release the lock!
  #  @return 0 when success
  #  @return 1 illegal arguments
  #  @return 2 if the container does not exist
  #  @return 3 if it failed to lock(already locked)
  tpubUnlock() {
    _tpubLock U "$@"
  }
  ## tpubExp <container> <expr> [expr ...]
  #  Expression-style interface for thread-public variables.
  #
  #  This function processes <expr> arguments strictly left-to-right.
  #  Each argument is interpreted as one of:
  #
  #    • GET expression
  #    • SET expression
  #    • Array creation syntax
  #    • Pass-through literal output
  #
  #  ─────────────────────────────────────────────────────────────
  #  GET EXPRESSIONS
  #  ─────────────────────────────────────────────────────────────
  #
  #  An expression is treated as GET if it starts with '$' or '@'.
  #
  #    $var
  #    ${var}
  #    ${var[index]}
  #
  #      → tpubGet <container> <var>
  #
  #    ${var[@]}   ${var[*]}
  #
  #      → tpubGet <container> <var> A
  #
  #    ${#var}     ${#var[@]}   ${#var[*]}
  #
  #      → tpubGet <container> <var> S
  #
  #  GET results are written to stdout in argument order.
  #
  #  ─────────────────────────────────────────────────────────────
  #  SET EXPRESSIONS
  #  ─────────────────────────────────────────────────────────────
  #
  #    var=value
  #
  #      → tpubSet <container> <var> <value>
  #
  #  The value is the substring after the first '=' and is taken
  #  verbatim. No shell evaluation or globbing is performed.
  #
  #  ─────────────────────────────────────────────────────────────
  #  ARRAY CREATION SYNTAX
  #  ─────────────────────────────────────────────────────────────
  #
  #    var=(
  #      elem1
  #      elem2
  #      ...
  #    )
  #    [NO MORE ARGS ALLOWED]
  #
  #  Note:
  #    Bash would treat `( ... )` as a code block, so you need to use:
  #      var='(' ... ')'
  #
  #  Rules (STRICT):
  #    • Start token MUST be exactly "var=(".
  #    • After entering array mode:
  #        - Every following argument is an element.
  #        - The array NEVER ends early.
  #        - The array ends ONLY with the FINAL argument ")",
  #        -   or actually, if you don't add that ")", it will function normally
  #        -   except the return value will be 1.
  #    • A lone ")" is a valid element unless it is the final argument.
  #    • No other syntax is allowed while in array mode.
  #
  #  Implementation:
  #    - Array is first initialized empty.
  #    - Each element is appended via:
  #        tpubSet <container> <var> <element> a
  #
  #  ─────────────────────────────────────────────────────────────
  #  PASS-THROUGH OUTPUT
  #  ─────────────────────────────────────────────────────────────
  #
  #  Any argument that is neither GET nor SET nor array syntax
  #  is written directly to stdout.
  #
  #    ''   → outputs a literal NUL byte (\0)
  #    other → outputs the argument verbatim
  #
  #  ─────────────────────────────────────────────────────────────
  #  OUTPUT
  #  ─────────────────────────────────────────────────────────────
  #
  #    • GET expressions output their result
  #    • SET expressions output nothing
  #    • Array creation outputs nothing
  #    • Pass-through arguments output directly
  #
  #  ─────────────────────────────────────────────────────────────
  #  Preserved
  #  ─────────────────────────────────────────────────────────────
  #
  #  The following expressions are **preserved** and you should not use them:
  #
  #    Bash Parameter Expansion Modifiers:
  #      ^[$@]\{.*\[.*\].+\}$
  #    Preserved for special operations:
  #      ^!(.?[^!])*$
  #
  #  ─────────────────────────────────────────────────────────────
  #  RETURN VALUE
  #  ─────────────────────────────────────────────────────────────
  #
  #    0  Success
  #    1  Illegal expression or syntax error
  #    2  Container does not exist (from tpubGet / tpubSet)
  #
  #  ─────────────────────────────────────────────────────────────
  true IMPORTANT
  #  ─────────────────────────────────────────────────────────────
  #
  #  Make sure the whole var name don't contain a '=' when using the SET expression!
  #  a '=' can be contained by a map key("var[sth=sth]")!
  #
  #  Any expression exactly matching "var=(" ALWAYS starts array
  #  creation. To set a literal "(" value, use:
  #
  #    tpubSet $container $var '('
  #
  tpubExp() {
    local container="$1" argc="$#"
    shift || return 1
    argc=$((argc-1))

    local arg exp var idx val
    local in_array=0 array_idx
    local array_var=

    for arg; do
      ((--argc))
      # ================= ARRAY MODE =================
      if (( in_array )); then
        # the final argument
        if [[ "$argc" == 0 && "$arg" == ')' ]]; then
          in_array=0
          array_var=
          continue
        fi

        # Every argument is an element
        tpubSet "$container" "$array_var[$array_idx]" "$arg" || return $?
        ((++array_idx))
        continue
      fi

      # ================= NORMAL MODE =================
      case "$arg" in
        # ---------- ARRAY START ----------
        *=\()
          # must be exactly: var=(
          [[ "$arg" == *"=(" && "$arg" != *")"* ]] || return 1
          array_var="${arg%%=*}"
          in_array=1 array_idx=0
          # initialize empty array
          tpubSet "$container" "$array_var" "" a || return $?
          ;;

        # ---------- GET ----------
        \$*|@*)
          exp="${arg:1}"

          # ${...}
          if [[ "$exp" == \{*\} ]]; then
            exp="${exp:1:-1}"
          fi

          # Size query
          if [[ "$exp" == \#* ]]; then
            var="${exp#\#}"
            if [[ "$exp" == *"["[@'*']"]" ]]; then
              tpubGet "$container" "${var%%'['*']'}" L || return $?
            else
              tpubGet "$container" "$var" S || return $?
            fi
            continue
          fi

          # Indexed / expansion
          if [[ "$exp" == *"["*"]" ]]; then
            var="${exp%%[*}"
            idx="${exp#*[}"
            idx="${idx%]}"

            case "$idx" in
              @|\*)
                tpubGet "$container" "$var" A || return $?
                ;;
              *)
                tpubGet "$container" "$var[$idx]" || return $?
                ;;
            esac
          else
            tpubGet "$container" "$exp" || return $?
          fi
          ;;

        # ---------- SET ----------
        *=*)
          var="${arg%%=*}"
          val="${arg#*=}"
          tpubSet "$container" "$var" "$val" || return $?
          ;;

        # ---------- SPECIAL OPERATIONS ----------
        !*)
          if [[ "$arg" =~ [^!] ]] then
            echo -n 'PRESERVED OPERATION'
          else
            echo -n "${arg:1}"
          fi;;

        # ---------- PASS-THROUGH ----------
        '')
          # literal NUL
          echo -ne '\0'
          ;;
        *)
          echo -n "$arg"
          ;;
      esac
    done

    # Unclosed array is illegal
    (( in_array )) && return 1

    return 0
  }
}
# Thread Public Variables for Bash (`tpub`)

SEE [THIS](#tpubreleaseall)!

A Bash library that implements **thread-public, synchronized variables**.

This allows multiple Bash threads(background jobs / subshells) to safely **share variables** through a single host process.

---

## Features

* Thread-safe shared variables in pure Bash
* Supports Scalars, Arrays and Associative arrays (maps).
* No external dependencies (uses `mkfifo`, file descriptors)
* Deterministic locking (single host thread)
* Works across subshells and background jobs

---

## Installation

Save the file as `./thread_public.bash` and source it in the main thread:

```bash
source ./thread_public.bash
```

> The library will refuse to load if `THREAD_PUBLIC_INCLUDED` already exists.

---

## API Reference

The host thread may output some error message to `stderr`(`&2`) when an illegal expression is sent to it, you can use `2>/dev/null` when doing `tpubCreate`.

If you discovered a way to crash the host thread via the following APIs, please [report it](issues/new?title=Host%20Thread%20Crash%20With%20PUT_IT_HERE)

### `tpubCreate <fd1> <fd2> [name] [tmpfile]`

Create a new thread-public variable container.

```bash
tpubCreate 10 11 main
```

**Arguments**

* `fd1`: first FD to use(lock stream)
* `fd2`: second FD to use(data stream)
* `name`: container name (default: `main`)
* `tmpfile`: FIFO temporary file (optional)

The FDs should not be used!

**Returns**

* `0` success
* `1` invalid arguments
* `2` filesystem error
* `3` file descriptor error
* `4` name already exists

> ⚠️ Mostly must be called **before spawning threads**

---

### `tpubInherit <fd1> <fd2> [name]`

Bind an existing container to the current shell.

Used when FDs are inherited but variables are not.

The FDs should be the already existed ones.

```bash
tpubInherit 10 11 main
```

---

### `tpubGet <container> <var> [type]`

Read a variable from the container.

```bash
val="`tpubGet main counter`"
```

**Type options**

* *(empty)*: value
* `S`: size (`${#var}`)
* `A`: array expansion (`${var[*]}`)

---

### `tpubSet <container> <var> <value> [type]`

Write a variable to the container.

```bash
tpubSet main counter 42
```

**Type options**

* `v` (default): scalar
* `a`: array
* `A`: associative map
* `U`: unset

---

### `tpubExp <container> <exp> [<exp> ...]`

Really easy to use, but not really safe, do tests before using!

See [tpub Expression Document](expressions.md)

---

### `tpubRelease [name]`

Gracefully shut down a container.

```bash
tpubRelease main
```

* Signals host thread to exit
* Closes file descriptors
* Frees all shared variables

---

## `tpubReleaseAll`

Release **all thread-public containers** created in the current process.

```bash
tpubReleaseAll
```

### Important Notes

* **Do not rely on shell exit alone** — background host threads will survive if not released
* Recommended usage:

  * In `trap EXIT`
  * Or explicitly at the end of `main`

```bash
trap tpubReleaseAll EXIT
```

Failing to call this may result in creating zombie background processes!

---

## Example

```bash
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
```

---

## Implementation Notes

* Uses `mkfifo` + bidirectional FD reopening
* Compatible with Bash 5+
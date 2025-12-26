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

### `tpubCreate <fd1> <fd2> [name] [tmpfile]`

Create a new thread-public variable container.

```bash
tpubCreate 10 11 main
```

**Arguments**

* `fd1`: lock stream FD
* `fd2`: data stream FD
* `name`: container name (default: `main`)
* `tmpfile`: FIFO temporary file (optional)

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

---

### `tpubRelease [name]`

Gracefully shut down a container.

```bash
tpubRelease main
```

* Signals host thread to exit
* Closes file descriptors
* Frees all shared variables

> ⚠️ Must be called for EVERY CONTAINER CREATED at the end, 
  otherwise the host thread will continue running even the
  program ended!

---

Here is the **section to add** to your existing `README.md`. You can paste it under the API Reference (after `tpubRelease` is a good place).

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
* Host thread owns all variables
* Communication is binary and order-preserving
* Compatible with Bash 5+

---

## Limitations

* Requires **two FDs per container**
* Containers must be created **before threads**
* No garbage collection if host thread is force-killed
* Performance is bounded by FIFO IPC speed

---

## Safety & Portability

* Linux / POSIX systems
* Not compatible with `dash` or `sh`
* Requires `mkfifo`
# Get Operations
[Return To Readme](..)

## `tpubGetAs <resultVar> <container> <var> [type]`

Safely retrieve a thread-public variable **without spawning a new thread**.

```bash
tpubGetAs result main counter
```

### Arguments

1. `resultVar`
   Name of a **regular, thread-local variable** to store the result

2. `container`
   Container name (e.g. `main`)

3. `var`
   Variable name

4. `type` (optional)

   * *(empty)*: value (`$var`)
   * `S`: size (`${#var}`)
   * `L`: length (`${#var[@]}`)

### Description

* Internally calls `tpubGet`
* Assigns the result to `resultVar`
* **Does not use command substitution**
* **Does not create a new subshell**
* Safe to use while holding locks

### Notes

* If `type` is `A` (all values) or `N` (names):

  * The result is still returned as a **string**
  * This is currently considered **illegal operation**
  * The behavior **will change in the future**

### Returns

* `0` success
* `1` illegal arguments
* `2` container does not exist

---

## `tpubGet <container> <var> [type]`

Read a variable from the container.

```bash
val="`tpubGet main counter`"
```

**Type options**

* *(empty)*: value
* `S`: size (`${#var}`)
* `L`: Length (`${#var[@]}`)
* `A`: array expansion (`IFS=' ';${var[*]}}`)
* `N`: names (`IFS=' ';${!a[@]}`)

### ⚠️ Important Warning: `tpubGet` is Outdated for saving variables

> **READ THIS CAREFULLY — THIS IS A REAL DEADLOCK HAZARD**

`tpubGet` should be considered **outdated** and **unsafe**.

#### Why?

When you write any of the following:

```bash
$(tpubGet main var)
`tpubGet main var`
tpubGet main var | some_command
```

Bash will:

1. **Spawn a new subshell (new thread)**
2. Execute `tpubGet` inside that new thread
3. Attempt to acquire the container lock again

If the **original thread already holds the lock** (via `tpubLock`), then:

* The new subshell **cannot acquire the lock**
* The original thread **waits for the subshell to finish**
* The subshell **waits for the lock**
* 👉 **DEADLOCK — the program freezes forever**

This can happen **even if it looks like you are reading in a single thread**.

#### Recommendation

* ❌ **DO NOT** use `tpubGet` inside:

  * command substitution
  * pipelines
  * backticks
* ✅ Prefer:

  * `tpubGetAs`
  * direct calls without subshell creation
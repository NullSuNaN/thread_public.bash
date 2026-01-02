## Operations that **spawn a new Bash process / subshell**
[Return To Readme](..#operations)

### 1. **Command substitution** ❗ (most dangerous)

```bash
$(command)
`command`
```

Creates:

* A **new subshell**
* Runs `command` inside it
* Parent shell **waits** for completion

⚠️ **Deadlock-prone** when locks are held.

---

### 2. **Pipelines**

```bash
command1 | command2
command1 | command2 | command3
```

Creates:

* **Every command is a new subshell**
* Each side runs concurrently

Even this:

```bash
tpubGet main var | cat
```

creates a new subshell.

---

### 3. **Background execution**

```bash
command &
```

Creates:

* A new process
* Executes concurrently

Common footgun:

```bash
tpubGet main var &
```

---

### 4. **Subshell grouping**

```bash
( command1; command2 )
```

Always creates:

* A new subshell
* Isolated variable scope

---

### 5. **Process substitution**

```bash
command < <(producer)
command > >(consumer)
```

Creates:

* A new process to run `producer` / `consumer`
* Often invisible but very real

---

### 6. **Explicit shell invocation**

```bash
bash script.sh
sh script.sh
/bin/bash -c 'command'
```

Creates:

* A brand-new shell instance

---

### 7. **Pipelines hidden in compound commands**

These still fork:

```bash
while read x; do ...; done < <(command)
mapfile < <(command)
```

---

### 8. **`xargs` (most people forget this)**

```bash
echo foo | xargs command
```

`command` runs in a **separate process**.

---

### 9. **`coproc`**

```bash
coproc myproc { command; }
```

Creates:

* A background process
* With IPC via FDs

---

### 10. **`find -exec`, `parallel`, `env`, etc.**

```bash
find . -exec command {} \;
env VAR=1 command
```

Creates:

* New processes for `command`

---

## ❌ Things that **do NOT** create a new thread

These are **safe**:

```bash
var=$(...)          # ❌ actually unsafe → command substitution
var=value           # ✅ safe
echo "$var"         # ✅ safe
{ command1; }       # ✅ same shell
source file.sh      # ✅ same shell
```

⚠️ Note:

```bash
{ command; }
```

is **NOT** a subshell
but:

```bash
( command )
```

**IS**

---

## ⚠️ Special note about `$(...)` vs assignment

This is **the single biggest trap**:

```bash
val=$(tpubGet main var)   # ❌ creates a subshell → DEADLOCK RISK
```

Even though it *looks* like a variable read, it is **not**.

Correct approach:

```bash
tpubGetAs val main var    # ✅ same shell
```

---

## Practical Rule for `tpub` Users

> **If Bash might fork, assume it WILL fork.**

Safe patterns:

* `tpubGetAs`
* `tpubExp`
* Direct function calls

Unsafe patterns:

* `$(tpubGet …)`
* backticks
* pipelines
* background jobs
* process substitution

---

## Minimal mental checklist

If your code contains **any** of the following characters, double-check:

```
$()  ` `  |  &  ( )  <(  >(
```

Chances are high that Bash is creating a new process.

---

If you want, I can:

* convert this into a **README warning box**
* provide a **deadlock minimal repro**
* or write a **static checker script** that scans for unsafe patterns

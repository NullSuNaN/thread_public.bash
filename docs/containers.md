# Container Operations
[Return To Readme](..)

## `tpubCreate <fd1> <fd2> [name] [tmpfile]`

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

## `tpubInherit <fd1> <fd2> [name]`

Bind an existing container to the current shell.

Used when FDs are inherited but variables are not.

The FDs should be the already existed ones.

```bash
tpubInherit 10 11 main
```

---

## `tpubRelease [name]`

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

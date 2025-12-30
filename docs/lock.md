# Lock Operations
[Return To Readme](..)

## `tpubLock <container> <var>`

Lock a variable in a container.

```bash
tpubLock main counter
```

### Description

* Locks a variable so that:

  * Only the **current owning thread**
    can access the container
* Prevents race conditions across threads
* **⚠️ Must be paired with `tpubUnlock` in the same thread**

### Returns

* `0` success
* `1` illegal arguments
* `2` container does not exist
* `3` failed to lock (already locked)

---

## `tpubUnlock <container> <var>`

Unlock a previously locked variable.

```bash
tpubUnlock main counter
```

### Description

* Releases a lock acquired by `tpubLock`
* Must be called in the **same thread** after `tpubLock`
* Unlocking from a different thread is illegal
* * this will freeze the thread, and will change its behavior

### Returns

* `0` success
* `1` illegal arguments
* `2` container does not exist
* `3` failed to unlock (not locked)
# `tpubExp <container> <expr>...`
[Return To Readme](.)

Evaluate a sequence of **expressions** against a thread-public container.

Really easy to use, but not really safe, do tests before using!

`tpubExp` processes its arguments **left to right**, interpreting each argument as one of:

1. [**GET expression**](#get-expressions)
2. [**SET expression**](#set-expressions)(with a warning)
3. [**Array creation expression**](#array-creation)(with a warning)
4. [**Literal passthrough**](#literal-passthrough)
5. [**Preserved expressions**](#literal-passthrough)
6. [***Example***](#example)

If an **illegal expression** is detected, `tpubExp`:

* performs **no output**
* performs **no modification**
* **returns immediately** with a non-zero status

```bash
tpubExp <container> expr1 expr2 ...
```

---

## GET expressions

If an argument **starts with `$` or `@`**, it is treated as a `tpubGet`.

Supported forms:

### Scalar / element access

```bash
$var
${var}
${var[index]}
```

→ Outputs the value returned by `tpubGet`.

### Array expansion

```bash
${var[@]}
${var[*]}
```

→ Equivalent to:

```bash
tpubGet <container> var A
```

### Size query

```bash
${#var}
${#var[@]}
${#var[*]}
```

→ Equivalent to:

```bash
tpubGet <container> var S
tpubGet <container> var L
tpubGet <container> var L
```

(outputs array size)

---

### SET expressions

Any argument **not starting with `$` or `@`** and containing a **`=`** is treated as a `tpubSet`.

```bash
name=value
```

Equivalent to:

```bash
tpubSet <container> name value
```

* The **first `=`** splits name and value
* Produces **no output**

---

⚠️ **Important warning**

Make sure the whole var name don't contain a `=` when using the SET expression,
a `=` can be contained by a map key(`var[sth=sth]=sth`)!

### Array creation

`tpubExp` supports **explicit array construction** using a strict syntax.

```bash
tpubExp main var='(' val1 val2 val3 ')'
```

Rules:

* The array **starts only** with an argument exactly matching:

  ```bash
  var=(
  ```
* All **subsequent arguments** are treated as array elements
* The array **ends only** when an argument exactly equal to:

  ```bash
  )
  ```

  is encountered
* Everything between is taken **verbatim** as elements
* No nesting is allowed
* No extra arguments are allowed after `)` for that array expression

Equivalent to:

```bash
tpubSet <container> var "val1 val2 val3" a
```

⚠️ **Important warning**

If the user intends to set a variable to a literal string `"("`, this syntax will **always** be interpreted as array creation.

There is **no escaping mechanism** for this form.

---

### Literal passthrough

If an argument is **not** a GET, SET, or array construct, it is **output verbatim**.

Note: Expressions like `!sth`(`^!.*$`) is preserved for special ops, so when you want literal texts **start with** `!`, you should split the `!`s out and add an additional `!` in front of the text.

```bash
tpubExp main name=Linus hello " " 'world ' @name '!!' $':)\n'
# `!!:)` is illegal
```

Output:

```text
hello world Linus!:)
```

#### Empty string special case

If an argument is an **empty string** (`''`), `tpubExp` outputs a **literal NUL byte** (`\0`).

---

### Error handling

The only illegal expression so far is an illegal array creation with no ending `)`.
Which will let the program have a return value of `1`, but it actually does not affect anything.

---

### Return values

* `0` — success
* `1` — illegal expression detected

---

## Preserved expressions

The following expressions are **preserved** and you should not use them:
```regex
# Bash Parameter Expansion Modifiers:
^[$@]\{.*\[.*\].+\}$
# Preserved for special operations:
^!(.?[^!])*$
```

### Example

```bash
tpubExp main \
  counter=10 \
  msg=hello \
  "Value: " \
  '$counter' \
  arr='(' a b c ')'
tpubExp main \
  ", size" \
  "_eq==" \
  @_eq \
  @{#arr[@]}
```

Output (without other threads' modification):

```text
Value: 10, size=3
```
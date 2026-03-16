# PSJinja

A PowerShell implementation of a Jinja2-style template engine, targeting Windows PowerShell 5.1 and later.

## Requirements

- Windows PowerShell 5.1 or higher

## Installation

Clone the repository and import the module directly:

```powershell
Import-Module .\PSJinja.psm1
```

## Usage

PSJinja exposes a single public command: **`Invoke-Jinja`**.

```
Invoke-Jinja [-Template] <string> [[-Data] <object>]
```

| Parameter  | Type              | Description                                                                 |
|------------|-------------------|-----------------------------------------------------------------------------|
| `Template` | `string`          | The Jinja2-style template string to render. Accepts pipeline input.        |
| `Data`     | `hashtable` / `PSCustomObject` | Variables available inside the template. May be `$null` or omitted. |

Returns the fully-rendered `string`.

---

## Supported Syntax

### Variables

Use `{{ variable }}` to interpolate a value from the data context.

```powershell
Invoke-Jinja -Template 'Hello, {{ Name }}!' -Data @{ Name = 'World' }
# Hello, World!
```

**Dot notation** accesses nested hashtable keys or object properties:

```powershell
Invoke-Jinja -Template '{{ User.Name }}' -Data @{ User = @{ Name = 'Alice' } }
# Alice
```

**Array index notation** accesses elements by zero-based index:

```powershell
Invoke-Jinja -Template '{{ Items[0] }}' -Data @{ Items = @('first', 'second') }
# first
```

Undefined variables resolve to an empty string.

---

### Filters

Apply transformations to values with the pipe operator `|`. Multiple filters can be chained.

```powershell
Invoke-Jinja -Template '{{ Name | upper }}' -Data @{ Name = 'alice' }
# ALICE

Invoke-Jinja -Template '{{ Name | lower | trim }}' -Data @{ Name = '  HELLO  ' }
# hello
```

| Filter        | Description                                           | Example argument          |
|---------------|-------------------------------------------------------|---------------------------|
| `upper`       | Converts to uppercase                                 |                           |
| `lower`       | Converts to lowercase                                 |                           |
| `capitalize`  | Capitalizes the first letter, lowercases the rest     |                           |
| `title`       | Title-cases every word                                |                           |
| `trim`        | Strips leading and trailing whitespace                |                           |
| `length`      | Returns the count of items in a collection            |                           |
| `default`     | Returns the argument when the value is null or empty  | `default('n/a')`          |
| `join`        | Joins a collection with an optional separator         | `join(', ')`              |
| `first`       | Returns the first element of a collection             |                           |
| `last`        | Returns the last element of a collection              |                           |
| `sort`        | Sorts a collection                                    |                           |
| `reverse`     | Reverses a collection                                 |                           |
| `replace`     | Replaces a substring                                  | `replace('old', 'new')`   |
| `int`         | Converts the value to an integer                      |                           |
| `float`       | Converts the value to a float                         |                           |
| `string`      | Converts the value to a string                        |                           |

---

### If / Elif / Else

```
{% if <condition> %} ... {% elif <condition> %} ... {% else %} ... {% endif %}
```

```powershell
$tmpl = '{% if score -ge 90 %}A{% elif score -ge 80 %}B{% else %}F{% endif %}'
Invoke-Jinja -Template $tmpl -Data @{ score = 85 }
# B
```

Supported comparison operators (PowerShell style):
`-eq`, `-ne`, `-gt`, `-ge`, `-lt`, `-le`, `-like`, `-notlike`, `-match`, `-notmatch`, `-in`, `-notin`, `-contains`, `-notcontains`

Prefix a condition with `not` to negate it:

```powershell
Invoke-Jinja -Template '{% if not flag %}hidden{% endif %}' -Data @{ flag = $false }
# hidden
```

---

### For Loops

```
{% for <item> in <list> %} ... {% endfor %}
```

```powershell
$tmpl = '{% for item in items %}{{ item }} {% endfor %}'
Invoke-Jinja -Template $tmpl -Data @{ items = @('a', 'b', 'c') }
# a b c
```

Inside the loop body a `loop` variable is automatically available:

| Property      | Description                       |
|---------------|-----------------------------------|
| `loop.index`  | Current iteration (1-based)       |
| `loop.index0` | Current iteration (0-based)       |
| `loop.first`  | `$true` on the first iteration    |
| `loop.last`   | `$true` on the last iteration     |
| `loop.length` | Total number of items in the list |

```powershell
$tmpl = '{% for item in items %}{% if loop.first %}[{% endif %}{{ item }}{% if loop.last %}]{% endif %}{% endfor %}'
Invoke-Jinja -Template $tmpl -Data @{ items = @('a', 'b', 'c') }
# [abc]
```

---

### Set

Assign a value to a template variable:

```
{% set <name> = <expression> %}
```

```powershell
Invoke-Jinja -Template '{% set greeting = "Hello" %}{{ greeting }}, World!' -Data @{}
# Hello, World!
```

---

### Comments

Text inside `{# ... #}` is ignored and produces no output:

```powershell
Invoke-Jinja -Template 'Hello{# this is a comment #} World'
# Hello World
```

---

### Whitespace Control

Block tags support optional whitespace-control dashes (`{%- ... -%}`), which are stripped during parsing and behave identically to `{% ... %}`.

---

## Examples

```powershell
# Simple variable substitution
Invoke-Jinja -Template 'Hello, {{ Name }}!' -Data @{ Name = 'World' }

# Conditional rendering
$tmpl = '{% if admin %}Welcome, admin.{% else %}Access denied.{% endif %}'
Invoke-Jinja -Template $tmpl -Data @{ admin = $true }

# Loop with separator
$tmpl = '{% for item in items %}{{ item }}{% if not loop.last %}, {% endif %}{% endfor %}'
Invoke-Jinja -Template $tmpl -Data @{ items = @('apple', 'banana', 'cherry') }
# apple, banana, cherry

# Filter chain
Invoke-Jinja -Template '{{ name | trim | title }}' -Data @{ name = '  john doe  ' }
# John Doe

# Pipeline input
'Hello, {{ X }}!' | Invoke-Jinja -Data @{ X = 'pipe' }
# Hello, pipe!
```

---

## Running Tests

Tests use [Pester](https://pester.dev/) 5.x:

```powershell
Invoke-Pester .\Tests\PSJinja.Tests.ps1
```

---

## License

© PSJinja Contributors. All rights reserved.
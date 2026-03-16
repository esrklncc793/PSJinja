#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'PSJinja.psm1'
    Import-Module (Resolve-Path $modulePath).Path -Force
}

AfterAll {
    Remove-Module PSJinja -ErrorAction SilentlyContinue
}

Describe 'PSJinja Module' {

    # -------------------------------------------------------------------------
    Describe 'Module Manifest' {
        It 'has a valid PSJinja.psd1 manifest' {
            $psd1 = Join-Path $PSScriptRoot '..' 'PSJinja.psd1'
            Test-ModuleManifest -Path (Resolve-Path $psd1).Path | Should -Not -BeNullOrEmpty
        }

        It 'exports only Invoke-Jinja' {
            $commands = Get-Command -Module PSJinja
            $commands | Should -HaveCount 1
            $commands[0].Name | Should -Be 'Invoke-Jinja'
        }
    }

    # -------------------------------------------------------------------------
    Describe 'Invoke-Jinja — Parameter Validation' {

        It 'accepts an empty string and returns it unchanged' {
            Invoke-Jinja -Template '' | Should -Be ''
        }

        It 'accepts a null Data parameter without error' {
            Invoke-Jinja -Template 'Hello' -Data $null | Should -Be 'Hello'
        }

        It 'renders a plain text template with no tags' {
            Invoke-Jinja -Template 'No tags here.' | Should -Be 'No tags here.'
        }

        It 'accepts Data as a PSCustomObject' {
            $obj = [PSCustomObject]@{ Name = 'World' }
            Invoke-Jinja -Template 'Hello, {{ Name }}!' -Data $obj | Should -Be 'Hello, World!'
        }

        It 'accepts template from pipeline' {
            'Hello, {{ X }}!' | Invoke-Jinja -Data @{ X = 'pipe' } | Should -Be 'Hello, pipe!'
        }

        It 'returns an empty string for a null Template value' {
            # [string] coerces $null to ''
            Invoke-Jinja -Template ([string]$null) | Should -Be ''
        }
    }

    # -------------------------------------------------------------------------
    Describe 'Parsing — Variables' {

        Context 'Simple substitution' {
            It 'replaces a single variable' {
                Invoke-Jinja -Template '{{ Name }}' -Data @{ Name = 'Alice' } |
                    Should -Be 'Alice'
            }

            It 'replaces multiple variables' {
                Invoke-Jinja -Template '{{ A }} and {{ B }}' -Data @{ A = 'foo'; B = 'bar' } |
                    Should -Be 'foo and bar'
            }

            It 'returns empty string for an undefined variable' {
                Invoke-Jinja -Template '{{ Missing }}' -Data @{} | Should -Be ''
            }

            It 'returns empty string for a null variable value' {
                Invoke-Jinja -Template '{{ X }}' -Data @{ X = $null } | Should -Be ''
            }

            It 'renders an integer variable' {
                Invoke-Jinja -Template 'Count: {{ N }}' -Data @{ N = 42 } |
                    Should -Be 'Count: 42'
            }
        }

        Context 'Dot notation' {
            It 'accesses a nested hashtable key' {
                $data = @{ User = @{ Name = 'Bob' } }
                Invoke-Jinja -Template '{{ User.Name }}' -Data $data | Should -Be 'Bob'
            }

            It 'accesses a PSCustomObject property' {
                $data = @{ User = [PSCustomObject]@{ Name = 'Carol' } }
                Invoke-Jinja -Template '{{ User.Name }}' -Data $data | Should -Be 'Carol'
            }

            It 'returns empty string for a missing nested key' {
                $data = @{ User = @{ Name = 'Dave' } }
                Invoke-Jinja -Template '{{ User.Age }}' -Data $data | Should -Be ''
            }

            It 'returns empty string when a parent key is missing' {
                Invoke-Jinja -Template '{{ Missing.Prop }}' -Data @{} | Should -Be ''
            }

            It 'returns empty for deeply nested missing path' {
                $data = @{ A = @{} }
                Invoke-Jinja -Template '{{ A.B.C }}' -Data $data | Should -Be ''
            }
        }

        Context 'Array index notation' {
            It 'accesses an array element by index' {
                $data = @{ Items = @('x', 'y', 'z') }
                Invoke-Jinja -Template '{{ Items[1] }}' -Data $data | Should -Be 'y'
            }

            It 'returns empty string for an out-of-range index' {
                $data = @{ Items = @('x') }
                Invoke-Jinja -Template '{{ Items[5] }}' -Data $data | Should -Be ''
            }
        }
    }

    # -------------------------------------------------------------------------
    Describe 'Parsing — Comments' {

        It 'removes a comment entirely' {
            Invoke-Jinja -Template 'A{# this is a comment #}B' | Should -Be 'AB'
        }

        It 'removes a comment leaving surrounding text intact' {
            Invoke-Jinja -Template 'Hello {# greeting #} World' | Should -Be 'Hello  World'
        }

        It 'removes multiple comments' {
            Invoke-Jinja -Template '{# c1 #}X{# c2 #}Y{# c3 #}' | Should -Be 'XY'
        }
    }

    # -------------------------------------------------------------------------
    Describe 'Parsing — Filters' {

        It 'applies the upper filter' {
            Invoke-Jinja -Template '{{ Name | upper }}' -Data @{ Name = 'alice' } |
                Should -Be 'ALICE'
        }

        It 'applies the lower filter' {
            Invoke-Jinja -Template '{{ Name | lower }}' -Data @{ Name = 'ALICE' } |
                Should -Be 'alice'
        }

        It 'applies the capitalize filter' {
            Invoke-Jinja -Template '{{ Name | capitalize }}' -Data @{ Name = 'hELLO' } |
                Should -Be 'Hello'
        }

        It 'applies the title filter' {
            Invoke-Jinja -Template '{{ Title | title }}' -Data @{ Title = 'hello world' } |
                Should -Be 'Hello World'
        }

        It 'applies the trim filter' {
            Invoke-Jinja -Template '{{ Name | trim }}' -Data @{ Name = '  hi  ' } |
                Should -Be 'hi'
        }

        It 'applies the length filter' {
            Invoke-Jinja -Template '{{ Items | length }}' -Data @{ Items = @(1,2,3) } |
                Should -Be '3'
        }

        It 'applies the default filter when value is null' {
            Invoke-Jinja -Template '{{ Missing | default("n/a") }}' -Data @{} |
                Should -Be 'n/a'
        }

        It 'does not apply default filter when value exists' {
            Invoke-Jinja -Template '{{ Name | default("n/a") }}' -Data @{ Name = 'Alice' } |
                Should -Be 'Alice'
        }

        It 'applies the join filter with separator' {
            Invoke-Jinja -Template '{{ Items | join(", ") }}' -Data @{ Items = @('a','b','c') } |
                Should -Be 'a, b, c'
        }

        It 'applies the first filter' {
            Invoke-Jinja -Template '{{ Items | first }}' -Data @{ Items = @('x','y','z') } |
                Should -Be 'x'
        }

        It 'applies the last filter' {
            Invoke-Jinja -Template '{{ Items | last }}' -Data @{ Items = @('x','y','z') } |
                Should -Be 'z'
        }

        It 'applies the sort filter' {
            Invoke-Jinja -Template '{{ Items | sort | join(", ") }}' -Data @{ Items = @('c','a','b') } |
                Should -Be 'a, b, c'
        }

        It 'applies the reverse filter' {
            Invoke-Jinja -Template '{{ Items | reverse | join(", ") }}' -Data @{ Items = @('a','b','c') } |
                Should -Be 'c, b, a'
        }

        It 'applies the int filter' {
            Invoke-Jinja -Template '{{ Val | int }}' -Data @{ Val = '42' } |
                Should -Be '42'
        }

        It 'applies the float filter' {
            Invoke-Jinja -Template '{{ Val | float }}' -Data @{ Val = '3.14' } |
                Should -BeExactly '3.14'
        }

        It 'applies the string filter' {
            Invoke-Jinja -Template '{{ Val | string }}' -Data @{ Val = 123 } |
                Should -Be '123'
        }

        It 'chains multiple filters' {
            Invoke-Jinja -Template '{{ Name | lower | trim }}' -Data @{ Name = '  HELLO  ' } |
                Should -Be 'hello'
        }

        It 'applies upper filter to null returning empty string' {
            Invoke-Jinja -Template '{{ Missing | upper }}' -Data @{} | Should -Be ''
        }

        It 'applies length filter to null returning 0' {
            Invoke-Jinja -Template '{{ Missing | length }}' -Data @{} | Should -Be '0'
        }

        It 'warns and passes through unknown filter' {
            $result = Invoke-Jinja -Template '{{ Name | unknownfilter }}' -Data @{ Name = 'hi' } -WarningVariable wv
            $result | Should -Be 'hi'
        }
    }

    # -------------------------------------------------------------------------
    Describe 'Control Flow — If / Elif / Else' {

        Context 'Simple if' {
            It 'renders the body when condition is true' {
                Invoke-Jinja -Template '{% if flag %}yes{% endif %}' -Data @{ flag = $true } |
                    Should -Be 'yes'
            }

            It 'renders nothing when condition is false' {
                Invoke-Jinja -Template '{% if flag %}yes{% endif %}' -Data @{ flag = $false } |
                    Should -Be ''
            }

            It 'evaluates truthy non-null value' {
                Invoke-Jinja -Template '{% if Name %}set{% endif %}' -Data @{ Name = 'Alice' } |
                    Should -Be 'set'
            }

            It 'evaluates falsy null value' {
                Invoke-Jinja -Template '{% if Name %}set{% endif %}' -Data @{ Name = $null } |
                    Should -Be ''
            }

            It 'evaluates a missing variable as falsy' {
                Invoke-Jinja -Template '{% if Missing %}yes{% endif %}' -Data @{} |
                    Should -Be ''
            }
        }

        Context 'If / else' {
            It 'renders if branch when true' {
                Invoke-Jinja -Template '{% if flag %}YES{% else %}NO{% endif %}' -Data @{ flag = $true } |
                    Should -Be 'YES'
            }

            It 'renders else branch when false' {
                Invoke-Jinja -Template '{% if flag %}YES{% else %}NO{% endif %}' -Data @{ flag = $false } |
                    Should -Be 'NO'
            }
        }

        Context 'If / elif / else' {
            BeforeAll {
                $tmpl = '{% if score -ge 90 %}A{% elif score -ge 80 %}B{% elif score -ge 70 %}C{% else %}F{% endif %}'
            }

            It 'renders first branch (score=95)' {
                Invoke-Jinja -Template $tmpl -Data @{ score = 95 } | Should -Be 'A'
            }

            It 'renders second branch (score=85)' {
                Invoke-Jinja -Template $tmpl -Data @{ score = 85 } | Should -Be 'B'
            }

            It 'renders third branch (score=75)' {
                Invoke-Jinja -Template $tmpl -Data @{ score = 75 } | Should -Be 'C'
            }

            It 'renders else branch (score=50)' {
                Invoke-Jinja -Template $tmpl -Data @{ score = 50 } | Should -Be 'F'
            }
        }

        Context 'Comparison operators' {
            It 'evaluates -eq' {
                Invoke-Jinja -Template '{% if X -eq 5 %}yes{% endif %}' -Data @{ X = 5 } | Should -Be 'yes'
            }

            It 'evaluates -ne' {
                Invoke-Jinja -Template '{% if X -ne 5 %}yes{% endif %}' -Data @{ X = 3 } | Should -Be 'yes'
            }

            It 'evaluates -gt' {
                Invoke-Jinja -Template '{% if X -gt 3 %}yes{% endif %}' -Data @{ X = 5 } | Should -Be 'yes'
            }

            It 'evaluates -ge' {
                Invoke-Jinja -Template '{% if X -ge 5 %}yes{% endif %}' -Data @{ X = 5 } | Should -Be 'yes'
            }

            It 'evaluates -lt' {
                Invoke-Jinja -Template '{% if X -lt 10 %}yes{% endif %}' -Data @{ X = 5 } | Should -Be 'yes'
            }

            It 'evaluates -le' {
                Invoke-Jinja -Template '{% if X -le 5 %}yes{% endif %}' -Data @{ X = 5 } | Should -Be 'yes'
            }

            It 'evaluates -like' {
                Invoke-Jinja -Template '{% if Name -like "Al*" %}yes{% endif %}' -Data @{ Name = 'Alice' } |
                    Should -Be 'yes'
            }

            It 'evaluates -notlike' {
                Invoke-Jinja -Template '{% if Name -notlike "Z*" %}yes{% endif %}' -Data @{ Name = 'Alice' } |
                    Should -Be 'yes'
            }

            It 'evaluates -match' {
                Invoke-Jinja -Template '{% if Name -match "^Al" %}yes{% endif %}' -Data @{ Name = 'Alice' } |
                    Should -Be 'yes'
            }

            It 'evaluates -notmatch' {
                Invoke-Jinja -Template '{% if Name -notmatch "^Z" %}yes{% endif %}' -Data @{ Name = 'Alice' } |
                    Should -Be 'yes'
            }

            It 'evaluates -in' {
                Invoke-Jinja -Template '{% if X -in Items %}yes{% endif %}' -Data @{ X = 2; Items = @(1,2,3) } |
                    Should -Be 'yes'
            }

            It 'evaluates -notin' {
                Invoke-Jinja -Template '{% if X -notin Items %}yes{% endif %}' -Data @{ X = 5; Items = @(1,2,3) } |
                    Should -Be 'yes'
            }

            It 'evaluates -contains' {
                Invoke-Jinja -Template '{% if Items -contains 2 %}yes{% endif %}' -Data @{ Items = @(1,2,3) } |
                    Should -Be 'yes'
            }

            It 'evaluates -notcontains' {
                Invoke-Jinja -Template '{% if Items -notcontains 5 %}yes{% endif %}' -Data @{ Items = @(1,2,3) } |
                    Should -Be 'yes'
            }
        }

        Context 'not operator' {
            It 'negates a true value' {
                Invoke-Jinja -Template '{% if not flag %}yes{% endif %}' -Data @{ flag = $true } |
                    Should -Be ''
            }

            It 'negates a false value' {
                Invoke-Jinja -Template '{% if not flag %}yes{% endif %}' -Data @{ flag = $false } |
                    Should -Be 'yes'
            }

            It 'negates a comparison' {
                Invoke-Jinja -Template '{% if not X -eq 5 %}yes{% endif %}' -Data @{ X = 3 } |
                    Should -Be 'yes'
            }
        }

        Context 'Literal comparison values' {
            It 'compares to a string literal' {
                Invoke-Jinja -Template '{% if Name -eq "Alice" %}match{% endif %}' -Data @{ Name = 'Alice' } |
                    Should -Be 'match'
            }

            It 'compares to an integer literal' {
                Invoke-Jinja -Template '{% if N -eq 7 %}match{% endif %}' -Data @{ N = 7 } |
                    Should -Be 'match'
            }

            It 'compares to true literal' {
                Invoke-Jinja -Template '{% if Flag -eq true %}yes{% endif %}' -Data @{ Flag = $true } |
                    Should -Be 'yes'
            }
        }

        Context 'Nested if' {
            It 'evaluates nested if correctly' {
                $tmpl = '{% if A %}{% if B %}both{% else %}A only{% endif %}{% endif %}'
                Invoke-Jinja -Template $tmpl -Data @{ A = $true; B = $true } | Should -Be 'both'
                Invoke-Jinja -Template $tmpl -Data @{ A = $true; B = $false } | Should -Be 'A only'
                Invoke-Jinja -Template $tmpl -Data @{ A = $false; B = $true } | Should -Be ''
            }
        }
    }

    # -------------------------------------------------------------------------
    Describe 'Control Flow — For Loops' {

        Context 'Basic iteration' {
            It 'iterates over a simple array' {
                $result = Invoke-Jinja -Template '{% for i in Items %}{{ i }}{% endfor %}' -Data @{ Items = @('a','b','c') }
                $result | Should -Be 'abc'
            }

            It 'produces no output for an empty array' {
                $result = Invoke-Jinja -Template '{% for i in Items %}{{ i }}{% endfor %}' -Data @{ Items = @() }
                $result | Should -Be ''
            }

            It 'produces no output for a null list' {
                $result = Invoke-Jinja -Template '{% for i in Missing %}{{ i }}{% endfor %}' -Data @{}
                $result | Should -Be ''
            }

            It 'iterates over a single-element array' {
                $result = Invoke-Jinja -Template '{% for i in Items %}{{ i }}{% endfor %}' -Data @{ Items = @('only') }
                $result | Should -Be 'only'
            }
        }

        Context 'Loop variable' {
            It 'exposes loop.index (1-based)' {
                $result = Invoke-Jinja -Template '{% for i in Items %}{{ loop.index }}{% endfor %}' -Data @{ Items = @('a','b','c') }
                $result | Should -Be '123'
            }

            It 'exposes loop.index0 (0-based)' {
                $result = Invoke-Jinja -Template '{% for i in Items %}{{ loop.index0 }}{% endfor %}' -Data @{ Items = @('a','b') }
                $result | Should -Be '01'
            }

            It 'exposes loop.first' {
                $result = Invoke-Jinja -Template '{% for i in Items %}{% if loop.first %}F{% endif %}{% endfor %}' -Data @{ Items = @('a','b','c') }
                $result | Should -Be 'F'
            }

            It 'exposes loop.last' {
                $result = Invoke-Jinja -Template '{% for i in Items %}{% if loop.last %}L{% endif %}{% endfor %}' -Data @{ Items = @('a','b','c') }
                $result | Should -Be 'L'
            }

            It 'exposes loop.length' {
                $result = Invoke-Jinja -Template '{% for i in Items %}{{ loop.length }}{% endfor %}' -Data @{ Items = @('a','b','c') }
                $result | Should -Be '333'
            }
        }

        Context 'Nested loops' {
            It 'renders a nested for loop correctly' {
                $tmpl   = '{% for row in Rows %}{% for cell in row %}{{ cell }}{% endfor %}|{% endfor %}'
                $data   = @{ Rows = @(@('1','2'), @('3','4')) }
                $result = Invoke-Jinja -Template $tmpl -Data $data
                $result | Should -Be '12|34|'
            }

            It 'accesses outer context inside inner loop' {
                $tmpl   = '{% for item in Items %}{{ Prefix }}{{ item }} {% endfor %}'
                $result = Invoke-Jinja -Template $tmpl -Data @{ Items = @('a','b'); Prefix = '>' }
                $result | Should -Be '>a >b '
            }
        }

        Context 'For with conditional inside' {
            It 'applies an if condition inside a for loop' {
                $tmpl   = '{% for n in Numbers %}{% if n -gt 2 %}{{ n }}{% endif %}{% endfor %}'
                $result = Invoke-Jinja -Template $tmpl -Data @{ Numbers = @(1,2,3,4,5) }
                $result | Should -Be '345'
            }
        }

        Context 'For loop over object properties' {
            It 'iterates over an array of hashtables' {
                $tmpl  = '{% for user in Users %}{{ user.Name }}{% endfor %}'
                $data  = @{ Users = @(@{ Name = 'Alice' }, @{ Name = 'Bob' }) }
                $result = Invoke-Jinja -Template $tmpl -Data $data
                $result | Should -Be 'AliceBob'
            }
        }
    }

    # -------------------------------------------------------------------------
    Describe 'Control Flow — Set' {

        It 'sets a variable and renders it' {
            $tmpl = '{% set greeting = "Hello" %}{{ greeting }}'
            Invoke-Jinja -Template $tmpl -Data @{} | Should -Be 'Hello'
        }

        It 'overwrites an existing variable' {
            $tmpl = '{% set X = "new" %}{{ X }}'
            Invoke-Jinja -Template $tmpl -Data @{ X = 'old' } | Should -Be 'new'
        }

        It 'sets an integer value' {
            $tmpl = '{% set N = 42 %}{{ N }}'
            Invoke-Jinja -Template $tmpl -Data @{} | Should -Be '42'
        }
    }

    # -------------------------------------------------------------------------
    Describe 'Edge Cases & Graceful Error Handling' {

        It 'handles a template with only whitespace' {
            Invoke-Jinja -Template '   ' | Should -Be '   '
        }

        It 'handles a template with only tags and no text' {
            Invoke-Jinja -Template '{{ A }}{{ B }}' -Data @{ A = '1'; B = '2' } | Should -Be '12'
        }

        It 'treats unclosed {{ as plain text (no match)' {
            # The regex won't match unclosed delimiters; they pass through as TEXT
            Invoke-Jinja -Template 'Hello {{ World' | Should -Be 'Hello {{ World'
        }

        It 'treats unclosed {% as plain text' {
            Invoke-Jinja -Template '{% if flag' | Should -Be '{% if flag'
        }

        It 'handles whitespace-control dashes in block tags' {
            # {%- and -%} should work the same as {% and %} for parsing
            Invoke-Jinja -Template '{%- if flag -%}yes{%- endif -%}' -Data @{ flag = $true } |
                Should -Be 'yes'
        }

        It 'handles a Data object that is not a hashtable or PSCustomObject' {
            # Falls back to empty context; no variable substitution
            Invoke-Jinja -Template '{{ X }}' -Data 'not-an-object' | Should -Be ''
        }

        It 'handles unknown block tags gracefully (warning + skip)' {
            $result = Invoke-Jinja -Template '{% unknowntag foo %}hello' -Data @{} -WarningVariable wv
            $result | Should -Be 'hello'
        }

        It 'handles deeply nested if/for combination' {
            $tmpl = '{% for row in M %}{% for v in row %}{% if v -gt 0 %}+{% else %}-{% endif %}{% endfor %}|{% endfor %}'
            $data = @{ M = @(@(1,-1),@(-1,1)) }
            Invoke-Jinja -Template $tmpl -Data $data | Should -Be '+-|-+|'
        }

        It 'renders Booleans correctly inside conditions' {
            Invoke-Jinja -Template '{% if IsAdmin -eq $true %}admin{% endif %}' -Data @{ IsAdmin = $true } |
                Should -Be 'admin'
        }

        It 'handles invalid for-loop syntax gracefully' {
            # Warning is expected; body is skipped
            $result = Invoke-Jinja -Template '{% for badloop %}{{ x }}{% endfor %}' -Data @{} -WarningVariable wv
            $result | Should -Be ''
        }

        It 'handles a parenthesised condition' {
            Invoke-Jinja -Template '{% if (Flag) %}yes{% endif %}' -Data @{ Flag = $true } |
                Should -Be 'yes'
        }
    }
}

#Requires -Version 5.1
Set-StrictMode -Version Latest

#region --- Tokenizer ---

function ConvertTo-JinjaTokenList {
    <#
    .SYNOPSIS
        Tokenizes a Jinja2 template string into a flat list of typed tokens.
    .DESCRIPTION
        Scans the template for Jinja2 delimiters and splits it into TEXT, VAR,
        BLOCK, and COMMENT tokens that can be consumed by the parser.
    .PARAMETER Template
        The raw template string to tokenize.
    .OUTPUTS
        System.Collections.Generic.List[hashtable]
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[hashtable]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Template
    )

    $list = [System.Collections.Generic.List[hashtable]]::new()
    if ([string]::IsNullOrEmpty($Template)) {
        return , $list
    }

    $re   = [System.Text.RegularExpressions.Regex]::new(
        '(?s)\{\{.*?\}\}|\{%.*?%\}|\{#.*?#\}',
        [System.Text.RegularExpressions.RegexOptions]::None
    )
    $last = 0

    foreach ($m in $re.Matches($Template)) {
        if ($m.Index -gt $last) {
            [void]$list.Add(@{ Type = 'TEXT'; Value = $Template.Substring($last, $m.Index - $last) })
        }

        $raw = $m.Value
        if ($raw.StartsWith('{{')) {
            [void]$list.Add(@{ Type = 'VAR'; Value = $raw.Substring(2, $raw.Length - 4).Trim() })
        }
        elseif ($raw.StartsWith('{%')) {
            # Strip optional whitespace-control dashes and re-trim
            $blockVal = $raw.Substring(2, $raw.Length - 4).Trim()
            $blockVal = $blockVal.TrimStart('-').TrimEnd('-').Trim()
            [void]$list.Add(@{ Type = 'BLOCK'; Value = $blockVal })
        }
        elseif ($raw.StartsWith('{#')) {
            [void]$list.Add(@{ Type = 'COMMENT' })
        }

        $last = $m.Index + $m.Length
    }

    if ($last -lt $Template.Length) {
        [void]$list.Add(@{ Type = 'TEXT'; Value = $Template.Substring($last) })
    }

    return , $list
}

#endregion

#region --- Value / Condition Resolution ---

function Get-JinjaVariableValue {
    <#
    .SYNOPSIS
        Resolves a dotted-path / array-index expression from the data context.
    .DESCRIPTION
        Walks segment-by-segment through the expression, supporting hashtable
        key access, PSCustomObject property access, and integer array indexes
        in the form  name[0].
    .PARAMETER Expression
        The variable path to resolve (e.g. "user.address.city" or "items[2]").
    .PARAMETER Context
        The current data context hashtable.
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Expression,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $current = $Context
    $parts   = $Expression.Trim() -split '\.'

    foreach ($part in $parts) {
        if ($null -eq $current) { return $null }

        # Handle array index notation: segment[N]
        if ($part -match '^(.+)\[(\d+)\]$') {
            $propName    = $Matches[1]
            $arrayIndex  = [int]$Matches[2]

            if ($current -is [hashtable]) {
                if (-not $current.ContainsKey($propName)) { return $null }
                $current = $current[$propName]
            }
            elseif ($current -is [System.Management.Automation.PSCustomObject]) {
                $prop = $current.PSObject.Properties[$propName]
                $current = if ($null -ne $prop) { $prop.Value } else { return $null }
            }
            else {
                try { $current = $current.$propName } catch { return $null }
            }

            if ($null -eq $current) { return $null }
            $arr = @($current)
            if ($arrayIndex -lt $arr.Count) { return $arr[$arrayIndex] } else { return $null }
        }
        else {
            if ($current -is [hashtable]) {
                if (-not $current.ContainsKey($part)) { return $null }
                $current = $current[$part]
            }
            elseif ($current -is [System.Management.Automation.PSCustomObject]) {
                $prop = $current.PSObject.Properties[$part]
                $current = if ($null -ne $prop) { $prop.Value } else { return $null }
            }
            else {
                try { $current = $current.$part } catch { return $null }
            }
        }
    }

    return $current
}

function Invoke-JinjaFilter {
    <#
    .SYNOPSIS
        Applies a single Jinja2 filter to a value.
    .DESCRIPTION
        Supported filters: upper, lower, title, trim, length, default, join,
        first, last, sort, reverse, capitalize, replace, int, float, string.
    .PARAMETER Value
        The value to filter.
    .PARAMETER Filter
        The filter name, optionally with arguments: name or name('arg').
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Filter
    )

    if (-not ($Filter -match '^(\w+)(?:\((.+)\))?$')) {
        return $Value
    }

    $filterName = $Matches[1].ToLower()
    $filterArg  = if ($Matches.Count -gt 2 -and $null -ne $Matches[2]) { $Matches[2] } else { $null }

    switch ($filterName) {
        'upper'      {
            if ($null -eq $Value) { return '' } else { return $Value.ToString().ToUpper() }
        }
        'lower'      {
            if ($null -eq $Value) { return '' } else { return $Value.ToString().ToLower() }
        }
        'capitalize' {
            if ($null -eq $Value) { return '' }
            $s = $Value.ToString()
            if ($s.Length -eq 0) { return $s } else { return $s[0].ToString().ToUpper() + $s.Substring(1).ToLower() }
        }
        'title'      {
            if ($null -eq $Value) { return '' }
            return (($Value.ToString() -split '\s+') | ForEach-Object {
                if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() } else { $_ }
            }) -join ' '
        }
        'trim'       {
            if ($null -eq $Value) { return '' } else { return $Value.ToString().Trim() }
        }
        'length'     {
            if ($null -eq $Value) { return 0 } else { return @($Value).Count }
        }
        'default'    {
            if ($null -eq $Value -or $Value -eq '') {
                if ($null -ne $filterArg) {
                    $stripped = $filterArg.Trim().Trim('"').Trim("'")
                    return $stripped
                }
                return ''
            }
            return $Value
        }
        'join'       {
            if ($null -eq $Value) { return '' }
            $sep = if ($null -ne $filterArg) { $filterArg.Trim().Trim('"').Trim("'") } else { '' }
            return (@($Value) -join $sep)
        }
        'first'      {
            if ($null -eq $Value) { return $null }
            $arr = @($Value)
            if ($arr.Count -gt 0) { return $arr[0] } else { return $null }
        }
        'last'       {
            if ($null -eq $Value) { return $null }
            $arr = @($Value)
            if ($arr.Count -gt 0) { return $arr[-1] } else { return $null }
        }
        'sort'       {
            if ($null -eq $Value) { return @() }
            return @($Value | Sort-Object)
        }
        'reverse'    {
            if ($null -eq $Value) { return @() }
            $arr = @($Value)
            [array]::Reverse($arr)
            return $arr
        }
        'replace'    {
            if ($null -eq $Value) { return '' }
            if ($null -ne $filterArg -and $filterArg -match "^['""](.+)['""],\s*['""](.+)['""]$") {
                return $Value.ToString().Replace($Matches[1], $Matches[2])
            }
            return $Value
        }
        'int'        {
            try { return [int]$Value } catch { return 0 }
        }
        'float'      {
            try { return [double]$Value } catch { return 0.0 }
        }
        'string'     {
            if ($null -eq $Value) { return '' } else { return $Value.ToString() }
        }
        default      {
            Write-Warning "PSJinja: Unknown filter '$filterName'"
            return $Value
        }
    }
}

function Get-JinjaValue {
    <#
    .SYNOPSIS
        Evaluates a Jinja2 expression (variable, literal, or filtered expression).
    .DESCRIPTION
        Handles string/int/float/bool/null literals, variable lookups, and
        pipe-separated filter chains such as  name | upper | trim.
    .PARAMETER Expr
        The expression string.
    .PARAMETER Context
        The current data context hashtable.
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Expr,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    # Split on pipe to separate base expression from filter chain
    $segments  = [regex]::Split($Expr.Trim(), '\s*\|\s*')
    $baseExpr  = $segments[0].Trim()
    $filters   = if ($segments.Count -gt 1) { $segments[1..($segments.Count - 1)] } else { @() }

    # Resolve base value
    $val = Resolve-JinjaLiteral -Expr $baseExpr -Context $Context

    # Apply filters in order
    foreach ($f in $filters) {
        $fTrimmed = $f.Trim()
        if (-not [string]::IsNullOrEmpty($fTrimmed)) {
            $val = Invoke-JinjaFilter -Value $val -Filter $fTrimmed
        }
    }

    return $val
}

function Resolve-JinjaLiteral {
    <#
    .SYNOPSIS
        Resolves a base expression to a literal value or context variable.
    .PARAMETER Expr
        A single, un-filtered expression.
    .PARAMETER Context
        The current data context hashtable.
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Expr,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $e = $Expr.Trim()

    # String literals (single or double quoted)
    if ($e -match '^"(.*)"$' -or $e -match "^'(.*)'$") {
        return $Matches[1]
    }

    # Integer literal
    if ($e -match '^-?\d+$') {
        return [int]$e
    }

    # Float literal
    if ($e -match '^-?\d+\.\d+$') {
        return [double]$e
    }

    # Boolean literals
    if ($e -eq 'true'  -or $e -eq '$true')  { return $true  }
    if ($e -eq 'false' -or $e -eq '$false') { return $false }

    # None / null
    if ($e -eq 'none' -or $e -eq 'null' -or $e -eq '$null') { return $null }

    # Variable lookup
    return Get-JinjaVariableValue -Expression $e -Context $Context
}

function Test-JinjaCondition {
    <#
    .SYNOPSIS
        Evaluates a Jinja2 condition string to a boolean result.
    .DESCRIPTION
        Supports: PowerShell comparison operators (-eq, -ne, -gt, -ge, -lt, -le,
        -like, -notlike, -match, -notmatch, -in, -notin, -contains, -notcontains),
        the "not" prefix, and simple truthy/falsy evaluation.
    .PARAMETER Condition
        The condition expression string.
    .PARAMETER Context
        The current data context hashtable.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Condition,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $cond = $Condition.Trim()

    # Parenthesised expression — unwrap and recurse
    if ($cond -match '^\((.+)\)$') {
        return Test-JinjaCondition -Condition $Matches[1] -Context $Context
    }

    # "not ..." negation
    if ($cond -match '^not\s+(.+)$') {
        return -not (Test-JinjaCondition -Condition $Matches[1] -Context $Context)
    }

    # Comparison operators
    $compPattern = '^(.+?)\s+(-eq|-ne|-gt|-ge|-lt|-le|-like|-notlike|-match|-notmatch|-in|-notin|-contains|-notcontains)\s+(.+)$'
    if ($cond -match $compPattern) {
        $left  = Get-JinjaValue -Expr $Matches[1].Trim() -Context $Context
        $op    = $Matches[2]
        $right = Get-JinjaValue -Expr $Matches[3].Trim() -Context $Context

        switch ($op) {
            '-eq'          { return $left -eq $right          }
            '-ne'          { return $left -ne $right          }
            '-gt'          { return $left -gt $right          }
            '-ge'          { return $left -ge $right          }
            '-lt'          { return $left -lt $right          }
            '-le'          { return $left -le $right          }
            '-like'        { return $left -like $right        }
            '-notlike'     { return $left -notlike $right     }
            '-match'       { return $left -match $right       }
            '-notmatch'    { return $left -notmatch $right    }
            '-in'          { return $left -in $right          }
            '-notin'       { return $left -notin $right       }
            '-contains'    { return $left -contains $right    }
            '-notcontains' { return $left -notcontains $right }
            default        { return $false }
        }
    }

    # Simple truthy / falsy evaluation
    $val = Get-JinjaValue -Expr $cond -Context $Context
    if ($null -eq $val) { return $false }
    return [bool]$val
}

#endregion

#region --- Parser (Token List → AST) ---

function Invoke-JinjaParseBlock {
    <#
    .SYNOPSIS
        Parses a sequence of tokens into a 'template' AST node.
    .DESCRIPTION
        Reads tokens from the list (advancing $Index) until either the list is
        exhausted or a BLOCK token whose leading keyword is listed in $StopAt is
        encountered.  The stop token is NOT consumed — it is left for the caller.
    .PARAMETER Tokens
        The flat token list produced by ConvertTo-JinjaTokenList.
    .PARAMETER Index
        A [ref] integer cursor into the token list.
    .PARAMETER StopAt
        A list of BLOCK keywords that should halt this parse level.
    .OUTPUTS
        hashtable  — AST node of type 'template'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[hashtable]]$Tokens,

        [Parameter(Mandatory = $true)]
        [ref]$Index,

        [Parameter(Mandatory = $false)]
        [string[]]$StopAt = @()
    )

    $children = [System.Collections.Generic.List[hashtable]]::new()

    while ($Index.Value -lt $Tokens.Count) {
        $token = $Tokens[$Index.Value]

        if ($token.Type -eq 'TEXT') {
            [void]$children.Add(@{ Type = 'text'; Value = $token.Value })
            $Index.Value++
        }
        elseif ($token.Type -eq 'COMMENT') {
            $Index.Value++
        }
        elseif ($token.Type -eq 'VAR') {
            [void]$children.Add(@{ Type = 'var'; Expr = $token.Value })
            $Index.Value++
        }
        elseif ($token.Type -eq 'BLOCK') {
            $keyword = ($token.Value -split '\s+')[0].ToLower()

            # Stop (but do NOT consume) when the caller owns this token
            if ($StopAt -contains $keyword) {
                break
            }

            if ($keyword -eq 'if') {
                $condition = $token.Value -replace '^if\s+', ''
                $Index.Value++
                $ifNode = Invoke-JinjaParseIf -Tokens $Tokens -Index $Index -Condition $condition
                [void]$children.Add($ifNode)
            }
            elseif ($keyword -eq 'for') {
                $header = $token.Value
                $Index.Value++
                $forNode = Invoke-JinjaParseFor -Tokens $Tokens -Index $Index -Header $header
                [void]$children.Add($forNode)
            }
            elseif ($keyword -eq 'set') {
                if ($token.Value -match '^set\s+(\w+)\s*=\s*(.+)$') {
                    [void]$children.Add(@{ Type = 'set'; VarName = $Matches[1]; ValueExpr = $Matches[2].Trim() })
                }
                $Index.Value++
            }
            else {
                Write-Warning "PSJinja: Unrecognized block tag '$($token.Value)'"
                $Index.Value++
            }
        }
        else {
            $Index.Value++
        }
    }

    return @{ Type = 'template'; Children = $children.ToArray() }
}

function Invoke-JinjaParseIf {
    <#
    .SYNOPSIS
        Parses an if/elif/else/endif construct into an 'if' AST node.
    .DESCRIPTION
        Called after the opening  {% if condition %}  token has been consumed.
        Recursively collects elif and else branches until  {% endif %}  is found.
    .PARAMETER Tokens
        The flat token list.
    .PARAMETER Index
        A [ref] integer cursor.
    .PARAMETER Condition
        The condition text stripped from the opening if/elif token.
    .OUTPUTS
        hashtable  — AST node of type 'if'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[hashtable]]$Tokens,

        [Parameter(Mandatory = $true)]
        [ref]$Index,

        [Parameter(Mandatory = $true)]
        [string]$Condition
    )

    $ifBody       = Invoke-JinjaParseBlock -Tokens $Tokens -Index $Index -StopAt @('elif', 'else', 'endif')
    $elifBranches = [System.Collections.Generic.List[hashtable]]::new()
    $elseBody     = $null

    while ($Index.Value -lt $Tokens.Count) {
        $token   = $Tokens[$Index.Value]
        if ($token.Type -ne 'BLOCK') { break }
        $keyword = ($token.Value -split '\s+')[0].ToLower()

        if ($keyword -eq 'endif') {
            $Index.Value++
            break
        }
        elseif ($keyword -eq 'else') {
            $Index.Value++
            $elseBody = Invoke-JinjaParseBlock -Tokens $Tokens -Index $Index -StopAt @('endif')
            if ($Index.Value -lt $Tokens.Count -and
                $Tokens[$Index.Value].Type -eq 'BLOCK' -and
                ($Tokens[$Index.Value].Value -split '\s+')[0].ToLower() -eq 'endif') {
                $Index.Value++
            }
            break
        }
        elseif ($keyword -eq 'elif') {
            $elifCond = $token.Value -replace '^elif\s+', ''
            $Index.Value++
            $elifBody = Invoke-JinjaParseBlock -Tokens $Tokens -Index $Index -StopAt @('elif', 'else', 'endif')
            [void]$elifBranches.Add(@{ Condition = $elifCond; Body = $elifBody })
        }
        else {
            break
        }
    }

    return @{
        Type          = 'if'
        Condition     = $Condition
        IfBody        = $ifBody
        ElifBranches  = $elifBranches.ToArray()
        ElseBody      = $elseBody
    }
}

function Invoke-JinjaParseFor {
    <#
    .SYNOPSIS
        Parses a for/endfor construct into a 'for' AST node.
    .DESCRIPTION
        Called after the opening  {% for item in list %}  token has been consumed.
    .PARAMETER Tokens
        The flat token list.
    .PARAMETER Index
        A [ref] integer cursor.
    .PARAMETER Header
        The full block value from the opening for token (e.g. "for x in items").
    .OUTPUTS
        hashtable  — AST node of type 'for'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[hashtable]]$Tokens,

        [Parameter(Mandatory = $true)]
        [ref]$Index,

        [Parameter(Mandatory = $true)]
        [string]$Header
    )

    if (-not ($Header -match '^for\s+(\w+)\s+in\s+(.+)$')) {
        Write-Warning "PSJinja: Invalid for-loop syntax: $Header"
        return @{ Type = 'for'; ItemVar = ''; ListExpr = ''; Body = @{ Type = 'template'; Children = @() } }
    }

    $itemVar  = $Matches[1]
    $listExpr = $Matches[2].Trim()

    $body = Invoke-JinjaParseBlock -Tokens $Tokens -Index $Index -StopAt @('endfor')

    if ($Index.Value -lt $Tokens.Count -and
        $Tokens[$Index.Value].Type -eq 'BLOCK' -and
        ($Tokens[$Index.Value].Value -split '\s+')[0].ToLower() -eq 'endfor') {
        $Index.Value++
    }

    return @{
        Type     = 'for'
        ItemVar  = $itemVar
        ListExpr = $listExpr
        Body     = $body
    }
}

#endregion

#region --- Evaluator (AST → string) ---

function Invoke-JinjaNode {
    <#
    .SYNOPSIS
        Recursively evaluates an AST node against a data context.
    .DESCRIPTION
        Dispatches on the node Type field and returns the rendered string
        fragment for that node.
    .PARAMETER Node
        The AST node hashtable to evaluate.
    .PARAMETER Context
        The current data context hashtable.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Node,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    switch ($Node.Type) {
        'template' {
            $sb = [System.Text.StringBuilder]::new()
            foreach ($child in $Node.Children) {
                [void]$sb.Append((Invoke-JinjaNode -Node $child -Context $Context))
            }
            return $sb.ToString()
        }

        'text' {
            return $Node.Value
        }

        'var' {
            $val = Get-JinjaValue -Expr $Node.Expr -Context $Context
            if ($null -eq $val) { return '' } else { return $val.ToString() }
        }

        'if' {
            if (Test-JinjaCondition -Condition $Node.Condition -Context $Context) {
                return Invoke-JinjaNode -Node $Node.IfBody -Context $Context
            }
            foreach ($branch in $Node.ElifBranches) {
                if (Test-JinjaCondition -Condition $branch.Condition -Context $Context) {
                    return Invoke-JinjaNode -Node $branch.Body -Context $Context
                }
            }
            if ($null -ne $Node.ElseBody) {
                return Invoke-JinjaNode -Node $Node.ElseBody -Context $Context
            }
            return ''
        }

        'for' {
            if ([string]::IsNullOrEmpty($Node.ListExpr)) { return '' }
            $listVal = Get-JinjaValue -Expr $Node.ListExpr -Context $Context
            if ($null -eq $listVal) { return '' }
            $items = @($listVal)
            $count = $items.Count
            if ($count -eq 0) { return '' }

            $sb = [System.Text.StringBuilder]::new()
            for ($i = 0; $i -lt $count; $i++) {
                $loopContext               = [hashtable]$Context.Clone()
                $loopContext[$Node.ItemVar] = $items[$i]
                $loopContext['loop']        = @{
                    index  = $i + 1
                    index0 = $i
                    first  = ($i -eq 0)
                    last   = ($i -eq $count - 1)
                    length = $count
                }
                [void]$sb.Append((Invoke-JinjaNode -Node $Node.Body -Context $loopContext))
            }
            return $sb.ToString()
        }

        'set' {
            $Context[$Node.VarName] = Get-JinjaValue -Expr $Node.ValueExpr -Context $Context
            return ''
        }

        default {
            return ''
        }
    }
}

#endregion

#region --- Public API ---

function Invoke-Jinja {
    <#
    .SYNOPSIS
        Renders a Jinja2-style template string with a provided data context.

    .DESCRIPTION
        Invoke-Jinja accepts a template string containing Jinja2-style
        delimiters and a data context, and returns the fully rendered string.

        Supported syntax:
          Variables   : {{ variable }}  {{ obj.prop }}  {{ arr[0] }}
          Filters     : {{ name | upper }}  {{ list | join(', ') }}
          If / elif / else / endif
          For / endfor  (with loop.index, loop.first, loop.last, loop.length)
          Set         : {% set x = value %}
          Comments    : {# this is ignored #}

    .PARAMETER Template
        The Jinja2-style template string to render.

    .PARAMETER Data
        A hashtable or PSCustomObject containing the variables available
        inside the template.  May be $null or omitted for templates that
        contain no variable references.

    .EXAMPLE
        Invoke-Jinja -Template 'Hello, {{ Name }}!' -Data @{ Name = 'World' }
        # Returns: Hello, World!

    .EXAMPLE
        $tmpl = '{% if admin %}Welcome, admin.{% else %}Access denied.{% endif %}'
        Invoke-Jinja -Template $tmpl -Data @{ admin = $true }
        # Returns: Welcome, admin.

    .EXAMPLE
        $tmpl = '{% for item in items %}{{ item }} {% endfor %}'
        Invoke-Jinja -Template $tmpl -Data @{ items = @('a','b','c') }
        # Returns: a b c

    .INPUTS
        System.String

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Template,

        [Parameter(Mandatory = $false, Position = 1)]
        [AllowNull()]
        [object]$Data
    )

    process {
        if ([string]::IsNullOrEmpty($Template)) {
            return $Template
        }

        # Normalize data to a hashtable for uniform key access
        if ($null -eq $Data) {
            $context = [hashtable]@{}
        }
        elseif ($Data -is [hashtable]) {
            $context = $Data
        }
        elseif ($Data -is [System.Management.Automation.PSCustomObject]) {
            $context = [hashtable]@{}
            foreach ($prop in $Data.PSObject.Properties) {
                $context[$prop.Name] = $prop.Value
            }
        }
        else {
            $context = [hashtable]@{}
        }

        try {
            $tokens   = ConvertTo-JinjaTokenList -Template $Template
            $idx      = 0
            $ast      = Invoke-JinjaParseBlock -Tokens $tokens -Index ([ref]$idx) -StopAt @()
            return Invoke-JinjaNode -Node $ast -Context $context
        }
        catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception,
                    'JinjaRenderError',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $Template
                )
            )
        }
    }
}

#endregion

Export-ModuleMember -Function 'Invoke-Jinja'

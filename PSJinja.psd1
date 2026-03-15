@{
    RootModule        = 'PSJinja.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '80792f00-03af-46c4-a1dd-c797b0d3c52e'
    Author            = 'PSJinja Contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) PSJinja Contributors. All rights reserved.'
    Description       = 'A PowerShell implementation of a Jinja2-style template engine.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-Jinja')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Jinja2', 'Templates', 'Rendering', 'DSL')
            LicenseUri = ''
            ProjectUri = 'https://github.com/esrklncc793/PSJinja'
        }
    }
}

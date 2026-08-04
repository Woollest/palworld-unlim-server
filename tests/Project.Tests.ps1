$ProjectRoot = Split-Path -Parent $PSScriptRoot

Describe 'Palworld Server repository' {
    It 'contains the required public entry points' {
        foreach ($Path in @('compose.yaml', 'README.md', 'LICENSE', 'config/PalWorldSettings.ini.example', 'scripts/test-project.ps1', '.github/workflows/ci.yml')) {
            if (-not (Test-Path (Join-Path $ProjectRoot $Path))) { throw "Missing: $Path" }
        }
    }

    It 'parses every PowerShell script' {
        $Files = @(Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.ps1' -File; Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'scripts') -Filter '*.ps1' -File; Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests') -Filter '*.ps1' -File)
        foreach ($File in $Files) {
            [void][scriptblock]::Create((Get-Content -LiteralPath $File.FullName -Raw))
        }
    }

    It 'keeps the REST API on localhost' {
        $Compose = Get-Content -LiteralPath (Join-Path $ProjectRoot 'compose.yaml') -Raw
        if ($Compose -notmatch '127\.0\.0\.1:\$\{PALWORLD_REST_PORT:-8212\}:8212/tcp') { throw 'REST API is not bound to localhost.' }
    }
}

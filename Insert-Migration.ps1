#Requires -Version 5.1
<#
.SYNOPSIS
    Wraps clipboard SQL into an update.scripts insert and applies it on the test server.

.DESCRIPTION
    1. Reads the SQL currently on the clipboard.
    2. Asks for the migration name (descr).
    3. Shows the composed INSERT and asks for confirmation.
    4. Executes it against the hardcoded test DB and prints the psql response.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Test-server connection (libpq keyword/value format).
$conn = "host=10.10.57.242 port=5432 dbname=abdm_portal user=kartavyhev password=aXZptB#FU1q7"

function Get-ClipboardSql {
    $text = Get-Clipboard -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Clipboard is empty. Copy the migration SQL first, then run this script."
    }
    return $text.Trim()
}

function Get-DollarQuoteTag {
    param([Parameter(Mandatory)][string]$Body)

    foreach ($name in @('sql', 'mig', 'body', 'pg', 'wrap')) {
        $tag = "`$$name`$"
        if ($Body.IndexOf($tag) -lt 0) {
            return $tag
        }
    }

    do {
        $suffix = -join ((1..8) | ForEach-Object { [char](Get-Random -Minimum 97 -Maximum 123) })
        $tag = "`$q$suffix`$"
    } while ($Body.IndexOf($tag) -ge 0)

    return $tag
}

function ConvertTo-SqlLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace("'", "''")
}

function Parse-LibpqConn {
    param([Parameter(Mandatory)][string]$ConnString)

    $map = @{}
    foreach ($part in ($ConnString -split '\s+')) {
        if ($part -notmatch '^(?<key>[^=]+)=(?<value>.*)$') {
            continue
        }
        $map[$Matches.key] = $Matches.value
    }

    foreach ($required in @('host', 'port', 'dbname', 'user', 'password')) {
        if (-not $map.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($map[$required])) {
            throw "Connection string is missing '$required'."
        }
    }

    return $map
}

function New-MigrationInsertSql {
    param(
        [Parameter(Mandatory)][string]$SqlBody,
        [Parameter(Mandatory)][string]$MigrationName
    )

    $tag = Get-DollarQuoteTag -Body $SqlBody
    $safeName = ConvertTo-SqlLiteral -Value $MigrationName

    return @"
INSERT INTO update.scripts(dateadd, descr, pg_body) VALUES
(CURRENT_TIMESTAMP, '$safeName',${tag}
$SqlBody
${tag});
"@
}

function Invoke-PsqlFile {
    param(
        [Parameter(Mandatory)][hashtable]$Conn,
        [Parameter(Mandatory)][string]$SqlFile
    )

    $psql = Get-Command psql.exe -ErrorAction SilentlyContinue
    if (-not $psql) {
        $guess = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($guess) {
            $psqlPath = $guess.FullName
        }
        else {
            throw "psql.exe was not found. Install PostgreSQL client tools or add psql to PATH."
        }
    }
    else {
        $psqlPath = $psql.Source
    }

    $previousPassword = $env:PGPASSWORD
    $env:PGPASSWORD = $Conn.password

    # psql prints "INSERT 0 1" to stdout. If that stays on the success stream,
    # $exitCode becomes that text (or a mix of text + 0), and the success check fails.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $exitCode = 1
    try {
        & $psqlPath `
            --host=$($Conn.host) `
            --port=$($Conn.port) `
            --dbname=$($Conn.dbname) `
            --username=$($Conn.user) `
            --set=ON_ERROR_STOP=1 `
            --echo-errors `
            --no-psqlrc `
            --file=$SqlFile | Out-Host
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousEap
        if ($null -eq $previousPassword) {
            Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        }
        else {
            $env:PGPASSWORD = $previousPassword
        }
    }

    return [int]$exitCode
}

try {
    $sqlBody = Get-ClipboardSql
    $connMap = Parse-LibpqConn -ConnString $conn

    Write-Host ""
    Write-Host "Clipboard SQL:" -ForegroundColor Cyan
    Write-Host $sqlBody
    Write-Host ""

    $migrationName = Read-Host "Enter migration name (descr), e.g. Q006601"
    if ([string]::IsNullOrWhiteSpace($migrationName)) {
        throw "Migration name cannot be empty."
    }
    $migrationName = $migrationName.Trim()

    $insertSql = New-MigrationInsertSql -SqlBody $sqlBody -MigrationName $migrationName

    Write-Host ""
    Write-Host "You are about to execute this INSERT on $($connMap.host)/$($connMap.dbname):" -ForegroundColor Yellow
    Write-Host $insertSql
    Write-Host ""

    $confirm = Read-Host "Proceed? [y/N]"
    if ($confirm -notin @('y', 'Y', 'yes', 'YES')) {
        Write-Host "Cancelled." -ForegroundColor DarkGray
        exit 0
    }

    $tempFile = Join-Path $env:TEMP ("insert-migration-{0}.sql" -f [guid]::NewGuid().ToString('N'))
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($tempFile, $insertSql, $utf8NoBom)

        Write-Host ""
        Write-Host "psql response:" -ForegroundColor Cyan
        $exitCode = Invoke-PsqlFile -Conn $connMap -SqlFile $tempFile

        Write-Host ""
        if ($exitCode -eq 0) {
            Write-Host "Done. psql exit code: $exitCode" -ForegroundColor Green
        }
        else {
            Write-Host "Failed. psql exit code: $exitCode" -ForegroundColor Red
            exit $exitCode
        }
    }
    finally {
        Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

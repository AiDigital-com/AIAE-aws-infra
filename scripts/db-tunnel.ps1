<#
.SYNOPSIS
  Open an SSM tunnel to a PROD PostgreSQL database through the jump instance (Windows).

.DESCRIPTION
  Opens 127.0.0.1:<port> -> <database>:5432 and keeps it open until Ctrl+C.
  It does not connect to the database: point psql, DataGrip, IntelliJ or
  pgAdmin at the printed host/port. Closing the script closes the tunnel and
  its SSM session.

  Sign in to AWS first (README.md, "PROD database access").

.EXAMPLE
  .\scripts\db-tunnel.ps1 operational-hub
.EXAMPLE
  .\scripts\db-tunnel.ps1 operational-hub -Role admin -CopyPassword
.EXAMPLE
  .\scripts\db-tunnel.ps1 pacing -Port 25432 -AwsProfile aiae-prod-db
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('operational-hub', 'onboarding', 'pacing')]
  [string]$Database,

  # Which credentials to print.
  # readonly (default): user `readonly`, SELECT only (AIAE-DB-ReadOnly or AIAE-DB-Admin permission set).
  # admin: the RDS master user, full rights (AIAE-DB-Admin permission set or AWS admin).
  [ValidateSet('readonly', 'admin')]
  [string]$Role = 'readonly',

  # Same as -Role admin.
  [switch]$Admin,

  # Same as -Role readonly.
  [switch]$ReadOnly,

  # Also copy the printed password to the clipboard.
  [switch]$CopyPassword,

  # Local port (default: 15432 operational-hub, 15433 onboarding, 15434 pacing).
  [int]$Port = 0,

  # AWS CLI profile (default: $env:AWS_PROFILE).
  [string]$AwsProfile
)

$ErrorActionPreference = 'Stop'

$targets = @{
  'operational-hub' = @{ Rds = 'aiae-operational-hub-prod-postgres'; Secret = 'AIAE-PRD/operational-hub/db-readonly'; Port = 15432 }
  'onboarding'      = @{ Rds = 'aiae-onboarding-prod-postgres';      Secret = 'AIAE-PRD/aiae-onboarding/db-readonly';  Port = 15433 }
  'pacing'          = @{ Rds = 'aiae-paicing-prod-postgres';         Secret = 'AIAE-PRD/aiae-paicing/db-readonly';     Port = 15434 }
}
$t = $targets[$Database]
if ($Port -eq 0) { $Port = $t.Port }

function Fail([string]$Message) { Write-Host "error: $Message" -ForegroundColor Red; exit 1 }

if ($Admin -and $ReadOnly) { Fail 'use either -Admin or -ReadOnly' }
if ($Admin) { $Role = 'admin' }
if ($ReadOnly) { $Role = 'readonly' }

if ($AwsProfile) { $env:AWS_PROFILE = $AwsProfile }
if (-not $env:AWS_REGION) { $env:AWS_REGION = 'us-east-1' }
$JumpName = 'aiae-operational-hub-prod-database-access'

# --- Tools --------------------------------------------------------------------
foreach ($d in 'C:\Program Files\Amazon\SessionManagerPlugin\bin', 'C:\Program Files\Amazon\AWSCLIV2') {
  if ((Test-Path $d) -and ($env:Path -notlike "*$d*")) { $env:Path += ";$d" }
}
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Fail 'AWS CLI v2 not found' }
if (-not (Get-Command session-manager-plugin -ErrorAction SilentlyContinue)) {
  Fail 'Session Manager plugin not found (winget install Amazon.SessionManagerPlugin)'
}

# Native commands: capture stdout, fail on non-zero exit.
function Invoke-Aws([string[]]$Arguments, [string]$OnError) {
  $out = & aws @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) { Fail $OnError }
  return ($out | Out-String).Trim()
}

# --- AWS identity -------------------------------------------------------------
$identity = Invoke-Aws @('sts', 'get-caller-identity', '--query', 'Arn', '--output', 'text') `
  "not signed in to AWS. Run 'aws sso login --profile <profile>' or 'aws login --profile <profile>' (and set `$env:AWS_PROFILE or pass -AwsProfile)"
Write-Host "AWS identity: $identity"

# --- Resolve database and jump instance ----------------------------------------
$db = Invoke-Aws @('rds', 'describe-db-instances', '--db-instance-identifier', $t.Rds,
  '--query', 'DBInstances[0].{h:Endpoint.Address,n:DBName,s:MasterUserSecret.SecretArn}', '--output', 'json') `
  "cannot describe $($t.Rds) (does your role allow rds:DescribeDBInstances?)" | ConvertFrom-Json

$jumpId = Invoke-Aws @('ec2', 'describe-instances',
  '--filters', "Name=tag:Name,Values=$JumpName", 'Name=instance-state-name,Values=running',
  '--query', 'Reservations[0].Instances[0].InstanceId', '--output', 'text') 'cannot look up the jump instance'
if (-not $jumpId -or $jumpId -eq 'None') { Fail "jump instance $JumpName not found or not running" }

# --- Credentials ----------------------------------------------------------------
if ($Role -eq 'admin') {
  $secretId = $db.s
  $deniedHint = 'cannot read the admin credentials: needs the AIAE-DB-Admin permission set (or AWS admin); use -Role readonly otherwise'
} else {
  $secretId = $t.Secret
  $deniedHint = "cannot read the readonly credentials from ${secretId}: needs the AIAE-DB-ReadOnly or AIAE-DB-Admin permission set"
}
$secret = Invoke-Aws @('secretsmanager', 'get-secret-value', '--secret-id', $secretId, '--query', 'SecretString', '--output', 'text') `
  $deniedHint | ConvertFrom-Json
$dbUser = $secret.username

# --- Tunnel ---------------------------------------------------------------------
$probe = New-Object System.Net.Sockets.TcpClient
$inUse = $false
try { $probe.Connect('127.0.0.1', $Port); $inUse = $true } catch { } finally { $probe.Dispose() }
if ($inUse) { Fail "local port $Port is already in use (another tunnel?). Use -Port <n>." }

$work = Join-Path ([IO.Path]::GetTempPath()) ("db-tunnel-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$log = Join-Path $work 'ssm.log'
$errLog = Join-Path $work 'ssm.err'

Write-Host "Opening tunnel: 127.0.0.1:$Port -> $($db.h):5432 via $jumpId"
$tunnel = Start-Process -FilePath (Get-Command aws).Source -PassThru -WindowStyle Hidden `
  -RedirectStandardOutput $log -RedirectStandardError $errLog `
  -ArgumentList @('ssm', 'start-session', '--target', $jumpId,
    '--document-name', 'AWS-StartPortForwardingSessionToRemoteHost',
    '--parameters', "host=$($db.h),portNumber=5432,localPortNumber=$Port")

$sessionId = $null
try {
  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    if ((Test-Path $log) -and (Select-String -Path $log -Pattern 'Waiting for connections' -Quiet)) { $ready = $true; break }
    if ($tunnel.HasExited) { break }
    Start-Sleep -Seconds 1
  }
  if (-not $ready) {
    Get-Content $log, $errLog -ErrorAction SilentlyContinue | Write-Host
    Fail 'tunnel did not become ready'
  }
  $m = Select-String -Path $log -Pattern 'SessionId: ([^ .]+)' | Select-Object -First 1
  if ($m) { $sessionId = $m.Matches[0].Groups[1].Value }

  # --- Connection details -----------------------------------------------------
  Write-Host ''
  Write-Host "Tunnel is open ($Database, role: $Role). Connect your client with:"
  Write-Host '  Host:     127.0.0.1'
  Write-Host "  Port:     $Port"
  Write-Host "  Database: $($db.n)"
  Write-Host "  User:     $dbUser"
  Write-Host '  SSL mode: require'
  Write-Host "  Password: $($secret.password)"
  if ($CopyPassword) {
    Set-Clipboard -Value $secret.password
    Write-Host '            (also copied to clipboard)'
  }
  $secret = $null
  Write-Host ''
  Write-Host "  psql `"host=127.0.0.1 port=$Port dbname=$($db.n) user=$dbUser sslmode=require`""
  if ($Role -eq 'admin') {
    Write-Host ''
    Write-Host 'WARNING: admin credentials are the master user: writes are allowed. Prefer -Role readonly for reading.' -ForegroundColor Yellow
  }
  Write-Host ''
  Write-Host 'Press Ctrl+C to close the tunnel.'
  while (-not $tunnel.HasExited) { Start-Sleep -Seconds 1 }
  Write-Host 'The tunnel process exited.'
} finally {
  # aws.exe starts session-manager-plugin.exe as a child; stop both.
  if (-not $tunnel.HasExited) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$($tunnel.Id)" -ErrorAction SilentlyContinue |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue
  }
  if ($sessionId) { & aws ssm terminate-session --session-id $sessionId 2>$null | Out-Null }
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
  Write-Host 'Tunnel closed.'
}

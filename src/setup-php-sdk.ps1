param (
    # PHP version to build for (e.g: 7.4, 8.0)
    [Parameter(Mandatory = $true)] [ValidatePattern("[5-8]\.[0-9]")] [System.String] $PhpVersion,
    [Parameter(Mandatory = $false)] [ValidatePattern("^(ts|nts)$")] [System.String] $ThreadSafety,
    [Parameter(Mandatory = $false)] [ValidatePattern("^v(c|s)\d\d$")] [System.String] $VC,
    [Parameter(Mandatory = $false)] [ValidatePattern("^x(64|86)$")] [System.String] $Arch,
    [Parameter(Mandatory = $false)] [System.String] $InstallDir,
    [Parameter(Mandatory = $false)] [System.String] $CacheDir
)

function Test-ZipArchive {
    <#
        .SYNOPSIS
            Returns $true when $Path is a complete, readable ZIP archive.

            Reading the entry list forces the End of Central Directory record
            to be parsed, which is exactly the part that is missing when a
            download is truncated ("End of Central Directory record could not
            be found").
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [System.String] $Path
    )

    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) {
        return $false
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $null = $zip.Entries.Count
        } finally {
            $zip.Dispose()
        }
        return $true
    } catch {
        return $false
    }
}

function Save-RemoteArchive {
    <#
        .SYNOPSIS
            Download a ZIP archive with retries and integrity validation.

            Invoke-WebRequest on a flaky connection can return without error
            yet leave a truncated file on disk; the subsequent Expand-Archive
            then fails. Validate every download and retry with backoff,
            discarding any partial/corrupt file before each attempt.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [System.String] $Url,
        [Parameter(Mandatory = $true)] [System.String] $OutFile,
        [Parameter(Mandatory = $false)] [System.Int32]  $MaxAttempts = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        # Always start from a clean slate so a previous partial file is never reused.
        if (Test-Path $OutFile) {
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        }

        try {
            Invoke-WebRequest $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop

            if (Test-ZipArchive $OutFile) {
                return
            }

            Write-Warning "Downloaded archive failed integrity check (attempt ${attempt}/${MaxAttempts}): ${Url}"
        } catch {
            Write-Warning "Download attempt ${attempt}/${MaxAttempts} failed for ${Url}: $_"
        }

        if (Test-Path $OutFile) {
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        }

        if ($attempt -lt $MaxAttempts) {
            $delay = [Math]::Min(30, [Math]::Pow(2, $attempt))
            Start-Sleep -Seconds $delay
        }
    }

    throw "Failed to download a valid archive from ${Url} after ${MaxAttempts} attempts."
}

function Install-SDK {
    <#
        .SYNOPSIS
            Install PHP SDK binary tools from sources.
    #>

    [CmdletBinding()]
    param (
        # PHP version for detect compatible SDK version
        [Parameter(Mandatory = $true)] [System.String] $version,
        [Parameter(Mandatory = $false)] [System.String] $installDir,
        [Parameter(Mandatory = $false)] [System.String] $cacheDir
    )

    process {
        # The PHP SDK 2.2+ is compatible with PHP 7.2 and above.
        # The PHP SDK 2.1 is required to build PHP 7.1 or 7.0.
        $SdkVersion = if ($PhpVersion -lt "7.2") {"2.1.10"} else {"2.3.0"}

        $PhpSdkZip = "php-sdk-${SdkVersion}.zip"
        $RemoteUrl = "https://github.com/php/php-sdk-binary-tools/archive/refs/tags/${PhpSdkZip}"

        $temp = if (!$cacheDir) {
            New-TemporaryFile | Rename-Item -NewName {$_.Name + ".zip"} -PassThru
        } else {
            "${cacheDir}\${PhpSdkZip}"
        }

        if (-not (Test-ZipArchive $temp)) {
            Write-Output "Downloading PHP SDK binary tools v${SdkVersion}"
            Save-RemoteArchive -Url $RemoteUrl -OutFile $temp
        }

        if (-not (Test-Path "$installDir\php-sdk")) {
            Expand-Archive $temp -DestinationPath $installDir
            Rename-Item (Resolve-Path "${installDir}\php-sdk-binary-tools-php-sdk-${SdkVersion}") "php-sdk"
        }

        Write-Output "PHP SDK v${SdkVersion} installed to ${installDir}\php-sdk"
    }
}

function Install-DevPack {
    <#
        .SYNOPSIS
            Intstall PHP Developer pack from sources.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [System.String] $version,
        [Parameter(Mandatory = $true)] [System.String] $ts,
        [Parameter(Mandatory = $true)] [System.String] $msvc,
        [Parameter(Mandatory = $true)] [System.String] $arch,
        [Parameter(Mandatory = $true)] [System.String] $installDir,
        [Parameter(Mandatory = $false)] [System.String] $cacheDir
    )

    process {
        $baseUrl = "https://downloads.php.net/~windows/releases"
        $tsPrefix = if ($ts -eq 'ts') {'Win32'} else {'nts-Win32'}

        try {
            $releases = Invoke-WebRequest "${baseUrl}/releases.json" -UseBasicParsing -ErrorAction Stop | ConvertFrom-Json

            if (-not $releases.$PhpVersion) {
                # Download from archive using detected PHP version
                $phpVer = & php -r 'echo PHP_VERSION;'
                $baseUrl = "${baseUrl}/archives"
            } else {
                $phpVer = $releases.$PhpVersion.version
            }
        } catch {
            Write-Warning "Failed to fetch releases.json: $_"
            Write-Output "Attempting to use detected PHP version from installed PHP"

            # Try to detect PHP version from installed php
            try {
                $phpVer = & php -r 'echo PHP_VERSION;'
                $baseUrl = "${baseUrl}/archives"
            } catch {
                # If PHP is not installed, construct version from major.minor
                Write-Warning "PHP not found in PATH, using provided version"
                # This will require the full version to be specified or fail
                throw "Cannot determine PHP patch version. Please ensure PHP is installed or releases.json is accessible."
            }
        }

        $devPackName = "php-devel-pack-${phpVer}-${tsPrefix}-${msvc}-${arch}.zip"
        $RemoteUrl = "${baseUrl}/${devPackName}"

        $temp = if (!$cacheDir) {
            New-TemporaryFile | Rename-Item -NewName {$_.Name + ".zip"} -PassThru
        } else {
            "${cacheDir}\${devPackName}"
        }

        if (-not (Test-ZipArchive $temp)) {
            Write-Output "Downloading PHP Developer Pack for PHP v${phpVer} from ${RemoteUrl}"
            Save-RemoteArchive -Url $RemoteUrl -OutFile $temp
        }

        if (-not (Test-Path "$installDir\php-devpack")) {
            Expand-Archive $temp -DestinationPath $installDir
            Rename-Item (Resolve-Path "${installDir}\php-${phpVer}-devel-${msvc}-${arch}") "php-devpack"
        }

        Write-Output "PHP Developer Pack php-${phpVer}-devel-${msvc}-${arch} installed to ${installDir}\php-devpack"
    }
}

Write-Output "::group::Installing PHP SDK binary tools"
Install-SDK -version $PhpVersion -cacheDir $CacheDir -installDir $InstallDir
Write-Output "::endgroup::"

Write-Output "::group::Installing PHP Developer Pack"
Install-DevPack -version $PhpVersion -ts $ThreadSafety -msvc $VC -arch $Arch `
    -cacheDir $CacheDir -installDir $InstallDir
Write-Output "::endgroup::"

Write-Output "::group::Add PHP SDK and PHP Developer Pack to system PATH"
Add-Content $Env:GITHUB_PATH "${InstallDir}\php-sdk\bin"
Add-Content $Env:GITHUB_PATH "${InstallDir}\php-sdk\msys2\usr\bin"
Add-Content $Env:GITHUB_PATH "${InstallDir}\php-devpack"
Write-Output "${InstallDir}\php-sdk\bin"
Write-Output "${InstallDir}\php-sdk\msys2\usr\bin"
Write-Output "${InstallDir}\php-devpack"
Write-Output "::endgroup::"

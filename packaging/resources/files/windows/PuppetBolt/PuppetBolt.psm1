$fso = New-Object -ComObject Scripting.FileSystemObject

$env:BOLT_BASEDIR = (Get-ItemProperty -Path "HKLM:\Software\Puppet Labs\Bolt").RememberedInstallDir
# Windows API GetShortPathName requires inline C#, so use COM instead
$env:BOLT_BASEDIR = $fso.GetFolder($env:BOLT_BASEDIR).ShortPath
$env:RUBY_DIR = $env:BOLT_BASEDIR
# Set SSL variables to ensure trusted locations are used
$env:SSL_CERT_FILE = "$($env:BOLT_BASEDIR)\ssl\cert.pem"
$env:SSL_CERT_DIR = "$($env:BOLT_BASEDIR)\ssl\certs"

function bolt {
    &$env:RUBY_DIR\bin\ruby -S -- $env:RUBY_DIR\bin\bolt ($args -replace '"', '"""')
}

Export-ModuleMember -Function bolt -Variable *

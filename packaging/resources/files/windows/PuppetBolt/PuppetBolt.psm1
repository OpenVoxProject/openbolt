$fso = New-Object -ComObject Scripting.FileSystemObject

$script:BOLT_BASEDIR = (Get-ItemProperty -Path "HKLM:\Software\Puppet Labs\Bolt").RememberedInstallDir
# Windows API GetShortPathName requires inline C#, so use COM instead
$script:BOLT_BASEDIR = $fso.GetFolder($env:BOLT_BASEDIR).ShortPath
$script:RUBY_DIR = $script:BOLT_BASEDIR

function bolt {
    # Set SSL variables to ensure trusted locations are used
    $env:SSL_CERT_FILE = "$($script:BOLT_BASEDIR)\ssl\cert.pem"
    $env:SSL_CERT_DIR = "$($script:BOLT_BASEDIR)\ssl\certs"

    &$script:RUBY_DIR\bin\ruby -S -- $script:RUBY_DIR\bin\bolt ($args -replace '"', '"""')
}

function bolt-inventory-pdb {
    # Set SSL variables to ensure trusted locations are used
    $env:SSL_CERT_FILE = "$($script:BOLT_BASEDIR)\ssl\cert.pem"
    $env:SSL_CERT_DIR = "$($script:BOLT_BASEDIR)\ssl\certs"

    &$script:RUBY_DIR\bin\ruby -S -- $script:RUBY_DIR\bin\bolt-inventory-pdb ($args -replace '"', '"""')
}

Export-ModuleMember -Function bolt -Variable *
Export-ModuleMember -Function bolt-inventory-pdb -Variable *

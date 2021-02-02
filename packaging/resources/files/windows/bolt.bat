@ECHO OFF
REM This is the parent directory of the directory containing this script (resolves to :install_root/Bolt)
SET BOLT_BASEDIR=%~dp0..
REM Avoid the nasty \..\ littering the paths.
SET BOLT_BASEDIR=%BOLT_BASEDIR:\bin\..=%

SET BOLT_DIR=%BOLT_BASEDIR%\puppet

REM Add bolt's bindirs to the PATH
SET PATH=%BOLT_DIR%\bin;%BOLT_BASEDIR%\bin;%PATH%

REM Set the RUBY LOAD_PATH using the RUBYLIB environment variable
SET RUBYLIB=%BOLT_DIR%\lib;%RUBYLIB%

REM Translate all slashes to / style to avoid issue #11930
SET RUBYLIB=%RUBYLIB:\=/%

REM Now return to the caller.

REM Set SSL variables to ensure trusted locations are used
SET SSL_CERT_FILE=%BOLT_DIR%\ssl\cert.pem
SET SSL_CERT_DIR=%BOLT_DIR%\ssl\certs
SET OPENSSL_CONF=%BOLT_DIR%\ssl\openssl.cnf

ruby -S -- bolt %*

@ECHO OFF
REM This is the parent directory of the directory containing this script (resolves to :install_root/Bolt)
SET BOLT_BASEDIR=%~dp0..
REM Avoid the nasty \..\ littering the paths.
SET BOLT_BASEDIR=%BOLT_BASEDIR:\bin\..=%

REM Add bolt's bindirs to the PATH
SET PATH=%BOLT_BASEDIR%\bin;%PATH%

REM Set the RUBY LOAD_PATH using the RUBYLIB environment variable
SET RUBYLIB=%BOLT_BASEDIR%\lib;%RUBYLIB%

REM Translate all slashes to / style to avoid issue #11930
SET RUBYLIB=%RUBYLIB:\=/%

REM Set SSL variables to ensure trusted locations are used
SET SSL_CERT_FILE=%BOLT_BASEDIR%\ssl\cert.pem
SET SSL_CERT_DIR=%BOLT_BASEDIR%\ssl\certs
SET OPENSSL_CONF=%BOLT_BASEDIR%\ssl\openssl.cnf
SET OPENSSL_CONF_INCLUDE=%BOLT_BASEDIR%\ssl
SET OPENSSL_MODULES=%BOLT_BASEDIR%\lib\ossl-modules
SET OPENSSL_ENGINES=%BOLT_BASEDIR%\lib\engines-3

ruby -S -- bolt %*

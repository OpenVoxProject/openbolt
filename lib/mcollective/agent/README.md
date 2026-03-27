# Bundled Choria Agent DDLs

This directory contains DDL (Data Definition Language) files for Choria
agents used by the Choria transport. MCollective's RPC client requires
a DDL file for every agent it calls, and it searches `$LOAD_PATH` for
`mcollective/agent/<name>.ddl`. Since OpenBolt's `lib/` is on
`$LOAD_PATH`, placing DDLs here makes them findable automatically.

## shell.ddl

Copied from [choria-plugins/shell-agent](https://github.com/choria-plugins/shell-agent).
The `rpcutil` and `bolt_tasks` DDLs ship with the `choria-mcorpc-support`
gem, but the shell agent DDL does not. Without this bundled copy, users
would need to manually install it into their Choria config's libdir.

If a user has their own copy of the DDL in their Choria libdir, their
version takes precedence because `loadconfig` prepends user libdirs to
`$LOAD_PATH` before the gem's `lib/` directory.

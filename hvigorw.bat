@echo off
rem ----------------------------------------------------------------------------
rem  Hvigor startup script, version 1.0.0
rem
rem  Required ENV vars:
rem -------------------
rem    NODE_HOME - location of a Node home dir with bin/node
rem
rem  Optional ENV vars:
rem -------------------
rem    HVIGOR_HOME - location of Hvigor home dir with bin/hvigor
rem ----------------------------------------------------------------------------

setlocal

set "PRG=%~dp0"
set "APP_HOME=%PRG%"

if defined NODE_HOME (
    set "NODE_EXE=%NODE_HOME%\bin\node.exe"
) else (
    set "NODE_EXE=node"
)

set "HVIGOR_HOME=%APP_HOME%.hvigor"

"%NODE_EXE%" "%HVIGOR_HOME%\hvigor\hvigor.js" %*

endlocal

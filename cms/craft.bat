@ECHO OFF

REM -------------------------------------------------------------
REM  Craft command line bootstrap script for Windows
REM -------------------------------------------------------------

@SETLOCAL

SET CRAFT_PATH=%~dp0

IF "%PHP_COMMAND%" == "" SET PHP_COMMAND=php.exe

"%PHP_COMMAND%" "%CRAFT_PATH%craft" %*

@ENDLOCAL

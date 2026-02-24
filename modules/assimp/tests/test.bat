@echo off
setlocal
set PATH=%PATH%;..\lib\win
jai -quiet test.jai +Autorun && del test.exe test.pdb

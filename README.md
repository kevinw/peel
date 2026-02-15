# peel

Minimal games and graphics prototyping framework built on SGPU.

To build an app:

```
jai build.jai - src/apps/<app_name>.jai
```

To build and run an app with args in src/apps/<app_name>.jai:

```
jai build.jai - src/apps/<app_name>.jai -run -run_args "-runarg1 -runarg2"
```

Important test runners in our dependency Jai-Shader-Transpiler:

```
cd modules/Jai-Shader-Transpiler && jai -quiet build.jai - -run_tests
```

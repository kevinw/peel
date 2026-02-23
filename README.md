# peel

![Screenshots of apps](screenshots/screenshot_grid.jpg)

Minimal games and graphics prototyping framework built on SGPU.

## Important submodules:

- modules/sgpu: custom thin gpu abstraction over vulkan/metal in modules/sgpu
- modules/Jai-Shader-Transpiler: converts Jai to GLSL or Metal at compile-time by writing SPIRV text and invoking SPIRV-Cross

## Command-line

To build an app:

```
jai build.jai - src/apps/<app_name>.jai
```

To build and run an app with args in src/apps/<app_name>.jai:

```
jai build.jai - src/apps/<app_name>.jai -run -run_args "-runarg1 -runarg2"
```

(You can omit -run_args if you don't need them.)

Important test runners in our dependency Jai-Shader-Transpiler to stress-test the entire transpiler pipeline:

```
jai -quiet modules/Jai-Shader-Transpiler/build.jai - -run_tests
```

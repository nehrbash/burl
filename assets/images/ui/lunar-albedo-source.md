`lunar-albedo.jpg` is the 2048×1024 color map from
[NASA's CGI Moon Kit](https://svs.gsfc.nasa.gov/4720): NASA's Scientific
Visualization Studio, Ernie Wright (USRA), Noah Petro (NASA/GSFC), and the
LRO/LROC instrument team. The map is centered on 0° longitude.

`LunarMoon.qml` maps it onto a sphere in `lunar-moon.frag` and lights that sphere
using Open-Meteo's `daily.moon_phase`, fetched with the weather forecast.
Missing phase data hides the moon. Phase is shown north-up, independent of local
horizon orientation.

Compile the shader from `files/burl`:

```sh
qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o assets/shaders/lunar-moon.frag.qsb assets/shaders/lunar-moon.frag
```

# Aseprite Lottie Export

This an [Aseprite](https://www.aseprite.org/) extension to export sprites to the [lottie](https://lottiefiles.com/) file format. Aseprite is an "animated sprite editor and pixel art tool." Lottie is a file format for animated vector graphics based on [JSON](https://en.wikipedia.org/wiki/JSON).

There is no import functionality, and there none will be added.

Lottie is similar to [SVG](https://en.wikipedia.org/wiki/SVG). For this reason, this export works in a manner similar to Aseprite's built-in SVG export for still images, or to the animated SVG export from my other repository, [AsepriteAddons](https://github.com/behreajj/asepriteaddons).

Each frame selected for export is held in a lottie shape layer. The frame contains the flattened composite of all the source sprite's layers. Each unique color within that composite is a lottie shape group. Within each unique color's shape group are rectangle shapes representing pixels with that color.

Due to this structure, exported sprites can yield massive lottie files. It is recommended to only use this export for small sprites -- in terms of dimensions, unique colors and/or frames.

Lottie supports raster images and image layers, but this exporter does not currently support the featue. See the modification section below for where to find the Lottie docs.

## Download

To download this script, click on the green Code button above, then select Download Zip. You can also click on the `lottieExport.lua` file. Beware that some browsers will append a `.txt` file format extension to script files on download. Aseprite will not recognize the script until this is removed and the original `.lua` extension is used. There can also be issues with copying and pasting. Be sure to click on the Raw file button. Do not copy the formatted code.

## Installation

To install this script, open Aseprite. In the menu bar, go to `File > Scripts > Open Scripts Folder`. Move the Lua script(s) into the folder that opens. Return to Aseprite; go to `File > Scripts > Rescan Scripts Folder`. The script should now be listed under `File > Scripts`. Select `lottieExport.lua` to launch the dialog.

If an error message in Aseprite's console appears, check if the script folder is on a file path that includes characters beyond [UTF-8](https://en.wikipedia.org/wiki/UTF-8), such as 'é' (e acute) or 'ö' (o umlaut).

## Usage

A hot key can be assigned to a script by going to `Edit > Keyboard Shortcuts`. The search input box in the top left of the shortcuts dialog can be used to locate the script by its file name.

Once open, holding down the `Alt` or `Option` key and pressing the underlined letter on a button will activate that button via keypress. For example, `Alt+C` will cancel the dialog.

## Modification

If you would like to modify this script, I recommend referring to the documentation for the Lottie file format, which can be found [here](https://lottiefiles.github.io/lottie-docs/). Aseprite's scripting API documentation can be found [here](https://github.com/aseprite/api). If you use Visual Studio Code, I recommend the [Lua Language Server](https://github.com/LuaLS/lua-language-server) extension along with an [Aseprite type definition](https://github.com/behreajj/aseprite-type-definition). Also helpful are a background familiarity with JSON, Lua and the conventions of vector graphics, such as those established by the SVG file format.
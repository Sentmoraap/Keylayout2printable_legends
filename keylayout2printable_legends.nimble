# Package

version       = "0.1.0"
author        = "Lilian Gimenez"
description   = "Generate keyboard legends png to print for relegendables from a macOS keyboard layout xml file"
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["keylayout2printable_legends"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.2"
requires "pixie >= 5.0.6"
requires "normalize"

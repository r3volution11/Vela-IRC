# Third-Party Notices

Vela is licensed under the [Mozilla Public License 2.0](LICENSE). It incorporates or is inspired by the following third-party works, which keep their own licenses.

## Libraries

| Component | License | Source |
|---|---|---|
| GRDB.swift | MIT | https://github.com/groue/GRDB.swift |
| SQLite (the copy that ships with macOS, used through GRDB) | Public domain | https://www.sqlite.org/copyright.html |
| ZIPFoundation | MIT | https://github.com/weichsel/ZIPFoundation |

## Themes

Several built-in themes port palettes from popular open-source editor themes. Others are original designs inspired by existing ones. Full attribution, with license details for each theme, is in [docs/THEME-CREDITS.md](docs/THEME-CREDITS.md).

- The **Oceanic, Darker, Palenight, Ocean, Deepforest, Volcano, Lighter and Sandy Beach** themes are original Vela themes *inspired by* the classic variants of the Material Theme, created by Mattia Astorino. Vela is not affiliated with or endorsed by Material Theme or Vira Software.
- The **Vela Graphite, Vela Paper and Vela Mist** themes are original designs.

## Data

The adult-site filter's built-in domain list (`Packages/VelaKit/Sources/VelaMedia/Resources/adult-domains.txt`) is derived from the `pornography-hosts` file in [Sinfonietta/hostfiles](https://github.com/Sinfonietta/hostfiles). `scripts/update-adult-domains.sh` regenerates it, and the file's header records the upstream commit it was built from. It is used under the MIT license:

```text
The MIT License (MIT)

Copyright (c) 2016 Sinfonietta

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Protocol references

Vela's IRC implementation follows the [Modern IRC Client Protocol](https://modern.ircdocs.horse) and the [IRCv3 specifications](https://ircv3.net/irc/).

## Screenshot media

The screenshots in `docs/screenshots/` and `website/public/screenshots/` come from Vela's demo mode (`Packages/VelaKit/Sources/VelaCore/DemoContent.swift`), which shows real media from the web, scaled down and sometimes cropped or blurred:

| Media | Credit | License |
|---|---|---|
| *Big Buck Bunny* | © copyright 2008, Blender Foundation / www.bigbuckbunny.org (https://peach.blender.org/about/); the YouTube copy is the 2013 4K 60 fps edition, changes by Janus B. Kristensen (CC BY) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| Crab Nebula | NASA, ESA, J. Hester and A. Loll (Arizona State University), https://commons.wikimedia.org/wiki/File:Crab_Nebula.jpg | Public domain |
| Rotating earth animated.gif | NASA Goddard Space Flight Center (Reto Stöckli, Robert Simmon), GIF by Jahobr, https://commons.wikimedia.org/wiki/File:Rotating_earth_animated.gif | Public domain |
| Aurora borealis over Eielson Air Force Base, Alaska | U.S. Air Force photo by Senior Airman Joshua Strang, https://commons.wikimedia.org/wiki/File:Aurora_borealis_over_Eielson_Air_Force_Base,_Alaska.jpg | Public domain |
| RCW 38 star cluster (eso2503a) | ESO/VVVX survey, https://www.eso.org/public/images/eso2503a/ | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Rocket launch GIF ("Space Night GIF by NASA") | NASA, via GIPHY, https://giphy.com/gifs/nasa-space-rocket-launch-x4vlKY5ocArL3SeVVU | Public domain |
| Earth and the space station GIF | NASA, via Tenor, https://tenor.com/view/nasa-nasa-gifs-earth-space-station-space-gif-9368490 | Public domain |

The Swift.org and IRCv3 link cards show those sites' icons. Swift and the Swift logo are trademarks of Apple Inc.; the IRCv3 logo belongs to the IRCv3 Working Group. The full credits are at https://velairc.app/help/license.

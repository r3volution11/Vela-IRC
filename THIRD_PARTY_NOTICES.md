# Third-Party Notices

Vela is licensed under the [Mozilla Public License 2.0](LICENSE). It incorporates or is inspired by the following third-party works, which keep their own licenses.

## Libraries

| Component | License | Source |
|---|---|---|
| GRDB.swift | MIT | https://github.com/groue/GRDB.swift |
| SQLite (the copy that ships with macOS, used through GRDB) | Public domain | https://www.sqlite.org/copyright.html |
| ZIPFoundation | MIT | https://github.com/weichsel/ZIPFoundation |
| Sparkle (the updater, shipped as Sparkle.framework in Vela.app) | MIT, with the licenses of the code it includes ([below](#sparkle)) | https://github.com/sparkle-project/Sparkle |
| Savage (the welcome screen's drawing, on screen and as SVG) | MIT | https://github.com/r3volution11/Savage |

### Sparkle

Vela.app includes Sparkle.framework, the updater, unmodified. Its license, with those of the code Sparkle includes (bsdiff, sais-lite, ed25519 and others), is reproduced here from Sparkle's `LICENSE`:

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=================
EXTERNAL LICENSES
=================

bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:

Copyright 2003-2005 Colin Percival
All rights reserved

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

--

sais.c and sais.h, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:

The sais-lite copyright is as follows:

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--

Portable C implementation of Ed25519, from https://github.com/orlp/ed25519

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be misrepresented as
   being the original software.

3. This notice may not be removed or altered from any source distribution.

--

SUSignatureVerifier.m:

Copyright (c) 2011 Mark Hamlin.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

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

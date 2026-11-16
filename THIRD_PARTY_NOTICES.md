# Third-Party Notices

Vela is licensed under the [Mozilla Public License 2.0](LICENSE). It incorporates or is inspired by the following third-party works, which keep their own licenses.

## Libraries

| Component | License | Source |
|---|---|---|
| GRDB.swift | MIT | https://github.com/groue/GRDB.swift |
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

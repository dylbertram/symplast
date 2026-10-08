# Third-party notices

Symplast is an independent front-end. It is **not affiliated with or endorsed
by Mutagen or Docker, Inc.**

## Mutagen

Symplast drives synchronization through the [Mutagen](https://mutagen.io)
command-line interface. Mutagen is **not** distributed as part of the bodyless
build: users install it themselves. The self-contained build (`BUNDLE_MUTAGEN=1`)
embeds a Mutagen binary in the app bundle.

Mutagen's core is licensed under the MIT License:

> MIT License
>
> Copyright (c) 2016-present Docker, Inc.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

### Release binaries and the SSPL

From Mutagen v0.17 onward, Mutagen's **official release binaries** also contain
code made available under the [Server Side Public License](https://www.mongodb.com/licensing/server-side-public-license)
(SSPL) — for example the xxHash and Zstandard fast paths, `fanotify` watching,
and the API client libraries. Mutagen's own guidance is that projects vendoring
the official release binaries must be aware of this.

**Symplast's bundled release pipeline does not use those official binaries.**
It builds checksum-pinned Mutagen source with
`go run scripts/build.go --mode=release --sspl=false`. This disables SSPL
enhancements in **both the CLI and every remote agent**, retaining MIT and
other non-copyleft-licensed code. The build verifies tags in every executable
and checks the compiled legal output; downloaded SSPL binaries are rejected.
The only source patch omits the obsolete Windows ARM32 agent target removed
from Go 1.26; all other upstream release targets remain included. The exact
compatibility patch is shipped as `Mutagen-BUILD-PATCH.diff` with the notices.
The app-only variant distributes no Mutagen code and does not change the
licensing of the user's separately installed Mutagen.

Upstream references:

- Source: <https://github.com/mutagen-io/mutagen>
- License: <https://github.com/mutagen-io/mutagen/blob/master/LICENSE>
- SSPL directory: <https://github.com/mutagen-io/mutagen/tree/master/sspl>

Release builds include the full license notices emitted by the bundled
non-SSPL `mutagen legal` command in
`Symplast.app/Contents/Resources/Mutagen-Licenses/Mutagen-Legal.txt`.
The adjacent `Mutagen-SOURCE.txt` and GitHub release notes identify the exact
Mutagen version, its source archive/hash, Go toolchain, build flags, and dependency versions.
Those source links are provided alongside the binary downloads at no charge.
Redistributors remain responsible for preserving notices and keeping the
corresponding source available under the applicable licenses.

## Trademarks

"Mutagen" and the Mutagen logo are trademarks of Docker, Inc. Symplast uses the
Mutagen name only to describe the dependency it works with. Symplast ships its
own name and logo and does not use Mutagen's mark as its identity.

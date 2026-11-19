# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# dmgbuild settings for Vela's disk image; scripts/make-dmg.sh runs it with
#   -D app=<Vela.app> -D background=<background.tiff> -D layout=<layout.json>
# dmgbuild writes the window's layout (.DS_Store) itself, so no Finder
# scripting is involved and it works the same on any Mac.
#
# Two settings are left alone on purpose: hide_extensions (it sets Finder info
# on the signed app, and codesign --verify --strict then fails), and the path
# and status bars beyond what's turned off here (they're Finder-wide settings
# a disk image can't change).

import json
import os.path

# `defines` is provided by dmgbuild.
app = defines["app"]  # noqa: F821
layout = json.load(open(defines["layout"]))  # noqa: F821

format = "UDZO"
filesystem = "HFS+"
files = [(app, "Vela.app")]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")  # the mounted volume's icon

background = defines["background"]  # noqa: F821
# The frame, title bar included (28 points), around the background.
window_rect = ((200, 160), (layout["width"], layout["height"] + 28))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
label_pos = "bottom"
icon_size = layout["iconSize"]
text_size = layout["textSize"]
icon_locations = {
    "Vela.app": tuple(layout["app"]),
    "Applications": tuple(layout["applications"]),
}

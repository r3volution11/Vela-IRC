// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef VELA_TEST_SUPPORT_H
#define VELA_TEST_SUPPORT_H

#include <stdbool.h>

/// Whether this test run is silent: Vela's beeps (`Beep`) were turned off as
/// the test bundle loaded, and AppKit's still are. False when
/// VELA_TEST_SOUNDS=1 keeps the sounds on.
bool VelaTestRunIsSilent(void);

#endif

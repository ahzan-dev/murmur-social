"""Boot-time token validation gate.

Extracted from `pages/layout.jac` so the layout stays a PLAIN, synchronous
module. The router imports the layout eagerly at cold start -- `_entry.js` does
`const RootLayout = layouts["/"]`, dereferencing it before anything renders. If
that eagerly-evaluated module also carries an `sv import` server stub and an
`async can with entry` effect, its compile can lose a first-load race against
the client runtime and `layout.js` momentarily "does not provide an export
named 'layout'". Ordinary child components (LeftNav, RightSidebar, HomeFeed)
have the exact same async+server shape and never hit this, because they mount
during render, not at router init. So this gate lives here, as one of them.

Behaviour is unchanged from the old inline check: render a blank full-height
background until the stored token is proven (or dropped as stale), then render
the children -- so pages and rails mount into a truthful auth state and never
fire a burst of 401s on the way in. Anonymous visitors (no token) skip the
check entirely, keeping the "readable signed out" promise intact.
"""

import from "@jac/runtime" { jacIsLoggedIn, jacLogout }
sv import from ..services.social { get_me }
import from ..lib.utils { cn }


def:pub AuthGate(children: any = None) -> JsxElement {
    # `checked` gates the shell for exactly one boot: children do not mount
    # until we know whether the stored token is real. Starts False so the very
    # first render is the check, not a burst of 401s.
    has checked: bool = False;

    async can with entry {
        if jacIsLoggedIn() {
            try {
                await get_me();   # the token exists -- prove it still works
            } except Exception {
                jacLogout();      # stale/foreign token -> drop it, go anonymous
            }
        }
        checked = True;           # either way, the shell can mount now
    }

    return <div className={cn("min-h-svh", ("bg-background" if not checked else None))}>
        {(children if checked else None)}
    </div>;
}

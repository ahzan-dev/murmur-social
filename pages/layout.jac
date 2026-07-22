"""Root layout -- the three-column shell every route mounts inside.

    < 768px    MobileBar + feed
    >= 768px   icon rail + feed
    >= 1100px  rail with labels + feed + right sidebar

The centre column is the only thing that scrolls with the page; the two rails
are `sticky top-0 h-svh`, which is what makes them behave like x.com's.

There is no AuthGuard and no `(auth)` route group, and that is the point:
every page here is readable signed out. Auth is not a wall around the app, it
is a condition on WRITING to it -- enforced server-side, where a plain `def`
needs a JWT (services/social.sv.jac), and surfaced client-side as
`<SignInDialog />`, mounted once here so any button in any page can raise it
without navigating away.

BOOT-TIME TOKEN CHECK. `jacIsLoggedIn()` only checks that a `jac_token` STRING
exists in localStorage -- it never validates it. On a shared origin (every
`jac start` app is http://localhost:8000) a token left by a DIFFERENT Jac app
is still in the bucket, so every component believes it is signed in, calls a
`def` like `get_me`, and 401s. The runtime self-heals that only on the WALKER
path; the FUNCTION path (`get_me`, `discover_people`) just throws and leaves the
dead token in place, so the app stays stuck "logged in" and broken.

So before we mount the shell we validate the stored token exactly once: call
`get_me`, and if it fails, `jacLogout()` drops the dead token. Children then
mount into a truthful auth state -- signed in if the token was real, cleanly
anonymous if it was stale. Anonymous visitors skip the check entirely (no token,
nothing to validate), so the "readable signed out" promise is untouched.
"""

cl import from "@jac/runtime" { Outlet, jacIsLoggedIn, jacLogout }
sv import from ..services.social { get_me }
cl import from ..components.LeftNav { LeftNav }
cl import from ..components.RightSidebar { RightSidebar }
cl import from ..components.MobileBar { MobileBar }
cl import from ..components.AuthDialog { SignInDialog }

cl {
    def:pub layout() -> JsxElement {
        # `checked` gates the shell for exactly one boot: children do not mount
        # until we know whether the stored token is real. Starts False so the
        # very first render is the check, not a burst of 401s.
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

        if not checked {
            # One tick, before paint settles. Same background as the shell, so
            # there is nothing to see -- not a spinner, just no flash of 401s.
            return <div className="min-h-svh bg-background" />;
        }

        return <div className="min-h-svh">
            <MobileBar />
            <div className="mx-auto flex w-full max-w-[1300px] justify-center">
                <LeftNav />
                <main className="min-w-0 w-full max-w-[600px] flex-1 border-l border-r border-border pb-16">
                    <Outlet />
                </main>
                <RightSidebar />
            </div>
            <SignInDialog />
        </div>;
    }
}

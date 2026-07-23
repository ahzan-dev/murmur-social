"""The three-column shell every route mounts inside.

    < 768px    MobileBar + feed
    >= 768px   icon rail + feed
    >= 1100px  rail with labels + feed + right sidebar

The centre column is the only thing that scrolls with the page; the two rails
are `sticky top-0 h-svh`, which is what makes them behave like x.com's.

Rendered by the MANUAL router in main.jac as the element of the parent
`<Route>`, so whichever child route matches appears at `<Outlet />`. There is
no AuthGuard and no auth wall: every route is readable signed out. Auth is a
condition on WRITING, enforced server-side (a plain `def` needs a JWT) and
surfaced client-side as `<SignInDialog />`, mounted once here so any button in
any page can raise it without navigating away.

The one-boot stored-token check lives in `<AuthGate>`, an ordinary child that
renders nothing until the token is proven (or dropped as stale). See
components/AuthGate.cl.jac.
"""

import from "@jac/runtime" { Outlet }
import from .LeftNav { LeftNav }
import from .RightSidebar { RightSidebar }
import from .MobileBar { MobileBar }
import from .AuthDialog { SignInDialog }
import from .AuthGate { AuthGate }


def:pub SocialLayout() -> JsxElement {
    return <AuthGate>
        <MobileBar />
        <div className="mx-auto flex w-full max-w-[1300px] justify-center">
            <LeftNav />
            <main className="min-w-0 w-full max-w-[600px] flex-1 border-l border-r border-border pb-16">
                <Outlet />
            </main>
            <RightSidebar />
        </div>
        <SignInDialog />
    </AuthGate>;
}

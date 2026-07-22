"""Sign-in / sign-up, as a dialog.

The auth model of this app, stated in one component: you can read everything
without an account, and the moment you try to *do* something we ask who you
are -- without navigating away and without throwing away what you were doing.

That last part is why this is a dialog and not a `/login` route. `requireSignIn()`
fires a window event from anywhere in the tree (the Post button, a Follow
button, a like) and this component -- mounted once, in `pages/layout.jac` --
opens over the top. The feed underneath keeps its scroll position and its
state. Compare a redirect to /login, which loses both.

SIGN-UP IS THE ONBOARDING. There is no /welcome route and no wizard: the
three awaited steps at the bottom of `submit` are the whole flow --

    jacSignup  -> creates the account (NO session yet)
    jacLogin   -> establishes the session
    setup_profile -> the first authenticated call, which is what puts a
                     Profile on the new user's OWN root

Skip an `await` on any of those and the next line runs unauthenticated: a
401 that only shows up on a real first registration. See `jac guide jac-cl-auth`.

There are no demo credentials. Maya and the others are content -- you read
them and follow them, you do not log in as them.
"""

import from react { useEffect }
import from "@jac/runtime" { jacLogin, jacSignup }
sv import from ..services.social { ProfileView, SetupProfile }
import from .ui.dialog { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription }
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.field { Field, FieldLabel }
import from ..lib.utils { cn }

glob _SIGNIN_EVENT: str = "murmur:signin";

# `window` again, typed `any`. The ambient `_Window` stub declares
# addEventListener/removeEventListener but NOT dispatchEvent, so the listener
# side below type-checks against the real `window` while the dispatch side has
# to go through an untyped alias. Nothing dynamic is happening -- this is one
# gap in the DOM stubs, not a pattern to copy.
glob _win: any = window;

"""Ask for a sign-in from anywhere, with no prop-drilling and no navigation.

A window event rather than a React context because the callers are leaves
scattered all over the tree -- a like button four rows deep in the feed, the
Post button in the rail -- and every one of them wants exactly one thing:
"open the dialog". A plain `Event` carries no payload, which is all we need:
this is a signal, not a message."""
def:pub requireSignIn() -> None {
    _win.dispatchEvent(new(Event, _SIGNIN_EVENT));
}

def:pub SignInDialog() -> JsxElement {
    has shown: bool = False;
    has mode: str = "signup";
    has full_name: str = "";
    has email: str = "";
    has password: str = "";
    has error: str = "";
    has busy: bool = False;

    # A manual useEffect, not `can with entry`: entry and exit compile to two
    # SEPARATE closures, so a listener added in `entry` is invisible to `exit`
    # and never gets removed. Acquire-and-release belongs in one effect whose
    # body returns the cleanup.
    useEffect(lambda {
        handler = lambda(e: any) {
            error = "";
            shown = True;
        };
        window.addEventListener(_SIGNIN_EVENT, handler);
        return lambda { window.removeEventListener(_SIGNIN_EVENT, handler); };
    }, []);

    async def submit -> None {
        # Pre-declare everything that holds an `await` result: `x = await f()`
        # can compile to a `let` scoped tighter than the check below it, which
        # then throws ReferenceError at runtime with no compile error.
        signup_result: dict | None = None;
        login_ok: bool = False;
        profile: ProfileView | None = None;

        error = "";
        if len(email.strip()) == 0 or len(password) == 0 {
            error = "Enter an email and a password.";
            return;
        }
        if mode == "signup" and len(password) < 8 {
            error = "Use at least 8 characters for the password.";
            return;
        }

        busy = True;

        if mode == "signup" {
            try {
                signup_result = await jacSignup(email.strip(), password);
            } except Exception {
                signup_result = None;
            }
            # jacSignup returns a DICT, and an always-truthy one -- so
            # `if not signup_result` can never catch a failure. Read the key.
            if signup_result is None or not signup_result["success"] {
                busy = False;
                error = "That email is already registered. Try signing in instead.";
                return;
            }
        }

        try {
            login_ok = await jacLogin(email.strip(), password);
        } except Exception {
            login_ok = False;
        }
        if not login_ok {
            busy = False;
            error = "Those credentials did not match an account.";
            return;
        }

        # The first authenticated call. Idempotent server-side, so running it
        # on every sign-in costs nothing and means an account can never end up
        # without a profile.
        #
        # The locals MUST be named exactly like the server parameters -- for a
        # function RPC the caller's variable name becomes the JSON key.
        username = full_name.strip() if len(full_name.strip()) > 0 else email.strip();
        display_name = full_name.strip();
        try {
            res = await root spawn SetupProfile(username=username, display_name=display_name);
            got = res.reports[0] if res and res.reports and len(res.reports) > 0 else None;
            profile = (got as ProfileView) if got is not None else None;
        } except Exception {
            profile = None;
        }
        busy = False;

        if profile is None {
            error = "Signed in, but your profile could not be created.";
            return;
        }

        shown = False;
        # Every panel on the page is keyed to who you are -- the feed, the
        # counts, the follow buttons all just changed meaning. Reloading is the
        # honest (and shortest) way to re-read them all.
        window.location.reload();
    }

    def handle_submit(e: FormEvent) {
        e.preventDefault();
        submit();
    }

    def handle_open(next_: bool) {
        shown = next_;
    }

    def handle_name(e: ChangeEvent) { full_name = e.target.value; }

    def handle_email(e: ChangeEvent) { email = e.target.value; }

    def handle_password(e: ChangeEvent) { password = e.target.value; }

    def handle_mode(e: MouseEvent) {
        error = "";
        mode = "signin" if mode == "signup" else "signup";
    }

    signing_up = mode == "signup";

    return <Dialog open={shown} onOpenChange={handle_open}>
        <DialogContent className="sm:max-w-md">
            <DialogHeader>
                <DialogTitle className="text-2xl">
                    {"Join Murmur" if signing_up else "Sign in to Murmur"}
                </DialogTitle>
                <DialogDescription>
                    {"Reading is free. Posting, following and liking need an account — every follow you make is an edge on your own graph." if signing_up else "Welcome back."}
                </DialogDescription>
            </DialogHeader>

            <form className="flex flex-col gap-4" onSubmit={handle_submit}>
                {if signing_up {
                    <Field>
                        <FieldLabel htmlFor="signin-name">Name</FieldLabel>
                        <Input
                            id="signin-name"
                            autoComplete="name"
                            placeholder="Ada Lovelace"
                            value={full_name}
                            onChange={handle_name}
                        />
                    </Field>
                }}

                <Field>
                    <FieldLabel htmlFor="signin-email">Email</FieldLabel>
                    <Input
                        id="signin-email"
                        type="email"
                        autoComplete="email"
                        placeholder="you@example.com"
                        value={email}
                        onChange={handle_email}
                    />
                </Field>

                <Field>
                    <FieldLabel htmlFor="signin-password">Password</FieldLabel>
                    <Input
                        id="signin-password"
                        type="password"
                        autoComplete={"new-password" if signing_up else "current-password"}
                        value={password}
                        onChange={handle_password}
                    />
                </Field>

                {if error {
                    <p className="text-sm text-destructive" role="alert">{error}</p>
                }}

                <Button type="submit" className="w-full" disabled={busy}>
                    {("Creating account..." if busy else "Create account") if signing_up else ("Signing in..." if busy else "Sign in")}
                </Button>
            </form>

            <p className="text-center text-sm text-muted-foreground">
                {"Already have an account?" if signing_up else "New here?"}{" "}
                <button
                    type="button"
                    onClick={handle_mode}
                    className={cn(
                        "font-medium text-foreground underline-offset-4 hover:underline",
                        "focus-visible:outline-none focus-visible:underline"
                    )}
                >
                    {"Sign in" if signing_up else "Create one"}
                </button>
            </p>
        </DialogContent>
    </Dialog>;
}

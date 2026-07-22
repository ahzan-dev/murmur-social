"""The nav footer: who you are, or a way to become someone.

Two states, and no third. Signed in, `get_me()` answers from the caller's own
root -- it needs a JWT, so the name shown here cannot be anybody but yours.
Signed out, there is no identity to display and no list of people to pick from,
so the control is simply an invitation to sign up.

That is the whole reason this is four lines of state and not a picker: with
auth, "who am I" is not a choice the client gets to make.
"""

import from "@jac/runtime" { Link, jacIsLoggedIn, jacLogout }
sv import from ..services.social { ProfileView, get_me }
import from .AuthDialog { requireSignIn }
import from .ui.dropdown_menu {
    DropdownMenu,
    DropdownMenuTrigger,
    DropdownMenuContent,
    DropdownMenuSeparator,
    DropdownMenuItem
}
import from .ui.avatar { Avatar, AvatarFallback }
import from .ui.button { Button }
import from ..lib.utils { cn }
import from ..lib.format { initials }

def:pub DotsIcon() -> JsxElement {
    return <svg viewBox="0 0 24 24" className="size-4 shrink-0" fill="currentColor" aria-hidden="true">
        <circle cx="5" cy="12" r="2" />
        <circle cx="12" cy="12" r="2" />
        <circle cx="19" cy="12" r="2" />
    </svg>;
}

def:pub AccountMenu(compact: bool = False) -> JsxElement {
    has me: ProfileView | None = None;

    # Guard the EFFECT, not just the render: a mount effect fires regardless of
    # what the component returns, so an unguarded `get_me()` would 401 on every
    # anonymous page load.
    async can with entry {
        if jacIsLoggedIn() {
            me = await get_me();
        }
    }

    def handle_signin(e: MouseEvent) {
        requireSignIn();
    }

    def handle_logout(e: any) {
        jacLogout();                 # synchronous -- never await it
        window.location.reload();
    }

    if me is None {
        return <Button
            onClick={handle_signin}
            size={"sm" if compact else "default"}
            className={cn("shrink-0", "w-full" if not compact else "")}
        >Sign in</Button>;
    }

    return <DropdownMenu>
        <DropdownMenuTrigger asChild={True}>
            <button
                type="button"
                aria-label="Account"
                className={cn(
                    "flex items-center gap-2 rounded-full transition-colors hover:bg-muted",
                    "pt-1 pb-1 pl-1 pr-1" if compact else "w-full pt-2 pb-2 pl-2 pr-2 min-[1100px]:pr-3"
                )}
            >
                <Avatar size="sm">
                    <AvatarFallback>{initials(me.display_name)}</AvatarFallback>
                </Avatar>
                {if not compact {
                    <div className="hidden min-w-0 flex-1 text-left min-[1100px]:block">
                        <p className="truncate text-sm font-semibold text-foreground">{me.display_name}</p>
                        <p className="truncate text-xs text-muted-foreground">{"@" + me.username}</p>
                    </div>
                }}
                {if not compact {
                    <span className="hidden text-muted-foreground min-[1100px]:block"><DotsIcon /></span>
                }}
            </button>
        </DropdownMenuTrigger>

        <DropdownMenuContent align="start" side={"bottom" if compact else "top"} className="w-56">
            <DropdownMenuItem asChild={True}>
                <Link to={f"/u/{me.username}"} className="cursor-pointer">
                    Your profile
                </Link>
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={handle_logout} className="cursor-pointer">
                Log out {"@" + me.username}
            </DropdownMenuItem>
        </DropdownMenuContent>
    </DropdownMenu>;
}

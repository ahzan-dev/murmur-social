"""Follow / unfollow. Each click creates or deletes exactly one Follows-edge.

Signed out, the click opens the sign-in dialog instead. Note what it does NOT
do: navigate to /login. You stay on the page, and the profile you were about to
follow is still under the dialog when you dismiss it.

`follow_user` / `unfollow_user` are authenticated (plain `def`), so the edge
they create always starts at the caller's OWN profile. There is no "follower"
parameter to pass, and therefore none to forge.
"""

import from "@jac/runtime" { jacIsLoggedIn }
sv import from ..services.social { ProfileView, FollowUser, UnfollowUser }
import from .AuthDialog { requireSignIn }
import from .ui.button { Button }

glob _win: any = window;

def:pub notifyFollowChanged() -> None {
    _win.dispatchEvent(new(Event, "murmur:follow-changed"));
}

def:pub FollowButton(
    profile: ProfileView,
    onChanged: Callable[[ProfileView], None],
    size: str = "sm"
) -> JsxElement {
    has busy: bool = False;

    async def handle_click -> None {
        if busy {
            return;
        }
        if not jacIsLoggedIn() {
            requireSignIn();
            return;
        }
        busy = True;
        updated: ProfileView | None = None;
        username = profile.username;
        if profile.is_following {
            resU = await root spawn UnfollowUser(username=username);
            gotU = resU.reports[0] if resU and resU.reports and len(resU.reports) > 0 else None;
            updated = (gotU as ProfileView) if gotU is not None else None;
        } else {
            resF = await root spawn FollowUser(username=username);
            gotF = resF.reports[0] if resF and resF.reports and len(resF.reports) > 0 else None;
            updated = (gotF as ProfileView) if gotF is not None else None;
        }
        busy = False;
        if updated is not None {
            onChanged(updated);
            notifyFollowChanged();
        }
    }

    if profile.is_me {
        return <span />;
    }

    return <Button
        size={size}
        variant={"outline" if profile.is_following else "default"}
        onClick={handle_click}
        disabled={busy}
    >
        {"Following" if profile.is_following else "Follow"}
    </Button>;
}

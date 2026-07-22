"""Write a post. Creating one attaches a Posted-edge from your Profile.

Signed out, the composer still renders -- greyed, with the real placeholder --
and clicking it opens the sign-in dialog. That is deliberate: showing the thing
you cannot do yet is a better invitation than hiding it, and it is what x.com
does. `create_post` is authenticated, so the Posted-edge can only ever start at
the caller's own Profile.
"""

import from "@jac/runtime" { jacIsLoggedIn }
sv import from ..services.social { PostView, CreatePost }
import from .AuthDialog { requireSignIn }
import from .ui.button { Button }
import from .ui.textarea { Textarea }
import from .ui.avatar { Avatar, AvatarFallback }
import from ..lib.format { initials }

glob _MAX_LEN: int = 280;

def:pub PostComposer(name: str, onPosted: Callable[[PostView], None]) -> JsxElement {
    has draft: str = "";
    has posting: bool = False;

    def handle_change(e: ChangeEvent) {
        draft = e.target.value;
    }

    def handle_focus(e: FocusEvent) {
        if not jacIsLoggedIn() {
            requireSignIn();
        }
    }

    async def handle_post -> None {
        if posting or len(draft.strip()) == 0 {
            return;
        }
        if not jacIsLoggedIn() {
            requireSignIn();
            return;
        }
        posting = True;
        fresh: PostView | None = None;
        content = draft.strip();
        res = await root spawn CreatePost(content=content);
        got = res.reports[0] if res and res.reports and len(res.reports) > 0 else None;
        fresh = (got as PostView) if got is not None else None;
        posting = False;
        if fresh is not None {
            draft = "";
            onPosted(fresh);
        }
    }

    signed_in = jacIsLoggedIn();
    remaining = _MAX_LEN - len(draft);
    can_post = len(draft.strip()) > 0 and remaining >= 0 and not posting;

    return <div className="flex gap-3 border-b border-border pt-4 pb-4 pl-4 pr-4">
        <Avatar className="shrink-0">
            <AvatarFallback>{initials(name) if signed_in else "?"}</AvatarFallback>
        </Avatar>

        <div className="min-w-0 flex-1">
            <Textarea
                id="composer"
                value={draft}
                onChange={handle_change}
                onFocus={handle_focus}
                readOnly={not signed_in}
                placeholder="What's happening?"
                rows={2}
                className="resize-none border-0 bg-transparent p-0 text-base shadow-none focus-visible:ring-0 dark:bg-transparent"
            />
            <div className="mt-3 flex items-center justify-end gap-3">
                {if len(draft) > 0 and signed_in {
                    <span className={"text-xs tabular-nums text-destructive" if remaining < 0 else "text-xs tabular-nums text-muted-foreground"}>
                        {str(remaining)}
                    </span>
                }}
                {if not signed_in {
                    <span className="mr-auto text-xs text-muted-foreground">Sign in to post</span>
                }}
                <Button size="sm" onClick={handle_post} disabled={signed_in and not can_post}>
                    {"Posting..." if posting else "Post"}
                </Button>
            </div>
        </div>
    </div>;
}

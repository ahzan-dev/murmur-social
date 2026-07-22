"""The home timeline -- two timelines, actually, and the difference between
them is the lesson.

    signed out ->  await public_timeline()     a SCAN. There is no "me", so
                                               there is no Follows-edge to hop.
                                               Every recent post, newest first.

    signed in  ->  root spawn load_feed()      a TRAVERSAL. One hop along MY
                                               follow-edges. The walker needs
                                               no argument: it spawns on my own
                                               root, so f"root" is already me.

Same screen, same PostCards. One walks a relationship; the other has none to
walk, so it reads everything. That is worth staring at for a second -- it is
the clearest statement in this template of what the graph actually buys.

Everything interesting happens server-side; see services/social.sv.jac.
"""

import from "@jac/runtime" { Link, jacIsLoggedIn }
sv import from ..services.social { PostView, ProfileView, get_me, load_feed, public_timeline }
import from .AuthDialog { requireSignIn }
import from .PostComposer { PostComposer }
import from .PostCard { PostCard }
import from .ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent }
import from .ui.button { Button }

def:pub FeedSkeleton() -> JsxElement {
    return <div className="flex flex-col gap-4 pt-6 pl-4 pr-4">
        {for i in [0, 1, 2] {
            <div key={str(i)} className="flex gap-3">
                <div className="size-8 shrink-0 animate-pulse rounded-full bg-muted" />
                <div className="flex-1 pt-1">
                    <div className="h-3 w-32 animate-pulse rounded bg-muted" />
                    <div className="mt-2 h-3 w-full animate-pulse rounded bg-muted" />
                    <div className="mt-1.5 h-3 w-2/3 animate-pulse rounded bg-muted" />
                </div>
            </div>
        }}
    </div>;
}

def:pub HomeFeed() -> JsxElement {
    has posts: list[PostView] = [];
    has me: ProfileView | None = None;
    has loading: bool = True;

    async def reload_feed -> None {
        if jacIsLoggedIn() {
            me = await get_me();
            result = root spawn load_feed();
            if result.reports and len(result.reports) > 0 {
                posts = result.reports[0];
            }
        } else {
            posts = await public_timeline();
        }
        loading = False;
    }

    async can with entry {
        await reload_feed();
    }

    # Refetch feed when a follow/unfollow happens. HomeFeed stays mounted
    # for the session so the listener lives until page navigation.
    can with entry {
        window.addEventListener("murmur:follow-changed", lambda(e: any) {
            reload_feed();
        });
    }

    def handle_posted(fresh: PostView) {
        posts = [fresh] + posts;
    }

    def handle_changed(updated: PostView) {
        posts = [updated if p.id == updated.id else p for p in posts];
    }

    def handle_join(e: MouseEvent) {
        requireSignIn();
    }

    signed_in = jacIsLoggedIn();

    return <div>
        <div className="sticky top-14 z-40 flex items-center justify-between gap-3 border-b border-border bg-background/80 pt-3 pb-3 pl-4 pr-4 backdrop-blur md:top-0">
            <h1 className="text-lg font-bold tracking-tight">{"Home" if signed_in else "Latest"}</h1>
            {if me is not None {
                <span className="truncate text-xs text-muted-foreground">
                    {"@" + me.username}
                </span>
            }}
            {if not signed_in {
                <span className="truncate text-xs text-muted-foreground">
                    Everything on the instance
                </span>
            }}
        </div>

        <PostComposer name={me.display_name if me is not None else ""} onPosted={handle_posted} />

        {if loading {
            <FeedSkeleton />
            skip;
        }}

        {if len(posts) == 0 and signed_in {
            <div className="pt-16 pb-16 pl-4 pr-4">
                <Empty>
                    <EmptyHeader>
                        <EmptyMedia variant="icon">
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                <circle cx="12" cy="12" r="10" />
                                <path d="M8 15h8M9 9h.01M15 9h.01" />
                            </svg>
                        </EmptyMedia>
                        <EmptyTitle>Your feed is empty</EmptyTitle>
                        <EmptyDescription>
                            Your feed is built from your follow-edges. Follow someone and their posts walk their way here.
                        </EmptyDescription>
                    </EmptyHeader>
                    <EmptyContent>
                        <Link to="/explore"><Button>Find people to follow</Button></Link>
                    </EmptyContent>
                </Empty>
            </div>
            skip;
        }}

        {if len(posts) == 0 {
            <div className="pt-16 pb-16 pl-4 pr-4">
                <Empty>
                    <EmptyHeader>
                        <EmptyTitle>Nothing here yet</EmptyTitle>
                        <EmptyDescription>
                            The seed builds eight people at first load. If this is empty, it did not run.
                        </EmptyDescription>
                    </EmptyHeader>
                </Empty>
            </div>
            skip;
        }}

        {for post in posts {
            <PostCard key={post.id} post={post} onChanged={handle_changed} />
        }}

        {if not signed_in {
            <div className="pt-8 pb-8 pl-4 pr-4 text-center">
                <p className="text-sm text-muted-foreground">
                    This is everyone{"'"}s posts. Sign up and your home feed becomes a one-hop walk of the people you follow.
                </p>
                <Button className="mt-3" onClick={handle_join}>Create account</Button>
            </div>
        }}
    </div>;
}

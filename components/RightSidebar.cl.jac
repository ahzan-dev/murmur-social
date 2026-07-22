"""The >= 1100px right column.

Nothing here is decoration -- both cards are the graph read back:

  "Who to follow"    = every profile with no Follows-edge from the caller
  "What's happening" = hashtags counted across every Posted-edge in the app

Both reads are `def:pub`, which is why this column is here at all for a
logged-out visitor: it is the app showing its contents, not a teaser. Signed
in, the SAME endpoints answer viewer-relative (`is_following` is now true for
the people you follow, so they drop out of the suggestions) -- because a `:pub`
endpoint called WITH a token still runs on that caller's own root.
"""

import from "@jac/runtime" { Link }
sv import from ..services.social { ProfileView, TrendView, discover_people, trending_tags }
import from .FollowButton { FollowButton }
import from .ui.card { Card, CardHeader, CardTitle, CardContent }
import from .ui.input { Input }
import from .ui.avatar { Avatar, AvatarFallback }
import from ..lib.format { initials }

def:pub SearchIcon() -> JsxElement {
    return <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <circle cx="11" cy="11" r="7" />
        <path d="m20 20-3.5-3.5" />
    </svg>;
}

def:pub SuggestionRow(person: ProfileView, onChanged: Callable[[ProfileView], None]) -> JsxElement {
    return <div className="flex items-center gap-3">
        <Link to={f"/u/{person.username}"} className="shrink-0">
            <Avatar size="sm">
                <AvatarFallback>{initials(person.display_name)}</AvatarFallback>
            </Avatar>
        </Link>
        <div className="min-w-0 flex-1">
            <Link
                to={f"/u/{person.username}"}
                className="block truncate text-sm font-semibold text-foreground hover:underline"
            >{person.display_name}</Link>
            <p className="truncate text-xs text-muted-foreground">{"@" + person.username}</p>
        </div>
        <FollowButton profile={person} onChanged={onChanged} size="xs" />
    </div>;
}

def:pub RightSidebar() -> JsxElement {
    has people: list[ProfileView] = [];
    has trends: list[TrendView] = [];
    has query: str = "";

    async can with entry {
        people = await discover_people();
        trends = await trending_tags();
    }

    def handle_query(e: ChangeEvent) {
        query = e.target.value;
    }

    def handle_changed(updated: ProfileView) {
        people = [updated if p.id == updated.id else p for p in people];
    }

    needle = query.strip().lower();
    matches = [
        p for p in people
        if not p.is_following
        and (len(needle) == 0 or needle in p.username.lower() or needle in p.display_name.lower())
    ];
    suggestions = matches[0:3];

    return <aside className="sticky top-0 hidden h-svh w-[350px] shrink-0 flex-col gap-4 overflow-y-auto pt-2 pb-6 pl-8 pr-4 min-[1100px]:flex">
        <div className="relative">
            <span className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-muted-foreground">
                <SearchIcon />
            </span>
            <Input
                value={query}
                onChange={handle_query}
                placeholder="Search people"
                aria-label="Search people"
                className="rounded-full bg-muted pl-9"
            />
        </div>

        <Card className="gap-0 pt-4 pb-2">
            <CardHeader className="pb-3">
                <CardTitle className="text-xl">Who to follow</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col gap-4 pb-4">
                {if len(suggestions) == 0 {
                    <p className="text-sm text-muted-foreground">
                        {"Nobody left — you follow everyone who matches." if len(needle) == 0 else "No match."}
                    </p>
                    skip;
                }}
                {for person in suggestions {
                    <SuggestionRow key={person.id} person={person} onChanged={handle_changed} />
                }}
            </CardContent>
        </Card>

        <Card className="gap-0 pt-4 pb-2">
            <CardHeader className="pb-3">
                <CardTitle className="text-xl">What{"'"}s happening</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col gap-3 pb-4">
                {if len(trends) == 0 {
                    <p className="text-sm text-muted-foreground">No hashtags posted yet.</p>
                    skip;
                }}
                {for trend in trends {
                    <div key={trend.tag}>
                        <p className="text-xs text-muted-foreground">Trending</p>
                        <p className="text-sm font-semibold text-foreground">{trend.tag}</p>
                        <p className="text-xs text-muted-foreground tabular-nums">
                            {str(trend.posts)} {"posts" if trend.posts != 1 else "post"}
                        </p>
                    </div>
                }}
            </CardContent>
        </Card>
    </aside>;
}

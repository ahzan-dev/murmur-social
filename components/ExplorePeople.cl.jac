"""Explore -- everyone else on the instance, with their edge-derived counts."""

import from "@jac/runtime" { Link }
sv import from ..services.social { ProfileView, discover_people }
import from .FollowButton { FollowButton }
import from .ui.avatar { Avatar, AvatarFallback }
import from .ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription }
import from ..lib.format { initials }

def:pub PersonRow(person: ProfileView, onChanged: Callable[[ProfileView], None]) -> JsxElement {
    return <div className="flex items-center gap-3 border-b border-border pt-4 pb-4 pl-4 pr-4 transition-colors hover:bg-muted/30">
        <Link to={f"/u/{person.username}"} className="shrink-0">
            <Avatar>
                <AvatarFallback>{initials(person.display_name)}</AvatarFallback>
            </Avatar>
        </Link>

        <div className="min-w-0 flex-1">
            <Link
                to={f"/u/{person.username}"}
                className="block truncate text-sm font-semibold text-foreground hover:underline"
            >{person.display_name}</Link>
            <p className="truncate text-sm text-muted-foreground">
                {person.bio if person.bio else "@" + person.username}
            </p>
            <p className="mt-0.5 text-xs text-muted-foreground tabular-nums">
                {str(person.followers)} followers {"·"} {str(person.posts)} posts
            </p>
        </div>

        <FollowButton profile={person} onChanged={onChanged} />
    </div>;
}

def:pub ExplorePeople() -> JsxElement {
    has people: list[ProfileView] = [];
    has loading: bool = True;

    async can with entry {
        people = await discover_people();
        loading = False;
    }

    def handle_changed(updated: ProfileView) {
        people = [updated if p.id == updated.id else p for p in people];
    }

    return <div>
        <div className="sticky top-14 z-40 border-b border-border bg-background/80 pt-3 pb-3 pl-4 pr-4 backdrop-blur md:top-0">
            <h1 className="text-lg font-bold tracking-tight">Explore</h1>
            <p className="text-sm text-muted-foreground">Follow someone to pull their posts into your feed.</p>
        </div>

        {if loading {
            <p className="pt-8 pb-8 text-center text-sm text-muted-foreground">Loading...</p>
            skip;
        }}

        {if len(people) == 0 {
            <div className="pt-16 pb-16 pl-4 pr-4">
                <Empty>
                    <EmptyHeader>
                        <EmptyMedia variant="icon">
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
                                <circle cx="9" cy="7" r="4" />
                                <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
                            </svg>
                        </EmptyMedia>
                        <EmptyTitle>Nobody else here yet</EmptyTitle>
                        <EmptyDescription>
                            The seed builds eight people at first load. If this is empty, the seed did not run.
                        </EmptyDescription>
                    </EmptyHeader>
                </Empty>
            </div>
            skip;
        }}

        {for person in people {
            <PersonRow key={person.id} person={person} onChanged={handle_changed} />
        }}
    </div>;
}

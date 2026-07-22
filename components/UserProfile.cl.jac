"""A profile page.

Every number on this page is an edge count, computed server-side in
`Profile.to_view` -- followers are incoming Follows-edges, following are
outgoing ones, posts are Posted-edges. Nothing is stored as a counter.
"""

sv import from ..services.social { ProfileView, PostView, ProfilePageView, LoadProfile }
import from .FollowButton { FollowButton }
import from .PostCard { PostCard }
import from .ui.avatar { Avatar, AvatarFallback }
import from .ui.separator { Separator }
import from ..lib.format { initials }

def:pub StatItem(value: int, label: str) -> JsxElement {
    return <div className="flex items-baseline gap-1.5">
        <span className="text-sm font-semibold tabular-nums text-foreground">{str(value)}</span>
        <span className="text-sm text-muted-foreground">{label}</span>
    </div>;
}

def:pub UserProfile(username: str) -> JsxElement {
    has profile: ProfileView | None = None;
    has posts: list[PostView] = [];
    has loading: bool = True;

    async can with entry {
        loading = True;
        # Spawn a walker, not the cached `get_profile`/`user_posts` functions:
        # walkers bypass the client's 60s reader cache, so a like or reply made
        # elsewhere is reflected the moment you land here -- no stale view, no
        # refresh needed. See `LoadProfile` in services/social.sv.jac.
        res = root spawn LoadProfile(username=username);
        got = res.reports[0] if res and res.reports and len(res.reports) > 0 else None;
        page = (got as ProfilePageView) if got is not None else None;
        if page is not None {
            profile = page.profile;
            posts = page.posts;
        }
        loading = False;
    }

    def handle_profile_changed(updated: ProfileView) {
        profile = updated;
    }

    def handle_post_changed(updated: PostView) {
        posts = [updated if p.id == updated.id else p for p in posts];
    }

    return <div>
        {if loading {
            <p className="pt-8 pb-8 text-center text-sm text-muted-foreground">Loading...</p>
            skip;
        }}

        {if profile is None {
            <div className="pt-16 pb-16 text-center">
                <h1 className="text-xl font-bold tracking-tight">{"@" + username}</h1>
                <p className="mt-2 text-sm text-muted-foreground">This account doesn{"'"}t exist.</p>
            </div>
            skip;
        }}

        {if profile is not None {
            <div className="pt-6 pb-4 pl-4 pr-4">
                <div className="flex items-start justify-between gap-4">
                    <Avatar size="lg">
                        <AvatarFallback className="text-base">{initials(profile.display_name)}</AvatarFallback>
                    </Avatar>
                    <FollowButton profile={profile} onChanged={handle_profile_changed} />
                </div>

                <h1 className="mt-3 text-xl font-bold tracking-tight">{profile.display_name}</h1>
                <p className="text-sm text-muted-foreground">{"@" + profile.username}</p>

                {if profile.bio {
                    <p className="mt-3 text-[0.9375rem] leading-relaxed text-foreground">{profile.bio}</p>
                }}

                <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-1">
                    <StatItem value={profile.following} label="Following" />
                    <StatItem value={profile.followers} label="Followers" />
                    <StatItem value={profile.posts} label="Posts" />
                </div>
            </div>

            <Separator />
        }}

        {if len(posts) == 0 {
            <p className="pt-12 pb-12 text-center text-sm text-muted-foreground">No posts yet.</p>
            skip;
        }}

        {for post in posts {
            <PostCard key={post.id} post={post} onChanged={handle_post_changed} />
        }}
    </div>;
}

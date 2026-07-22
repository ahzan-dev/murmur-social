"""Social graph backend.

The whole point of this file: the social graph IS the data model.

    a follow  ->  an edge   (Profile -:Follows:-> Profile)
    a like    ->  an edge   (Profile -:Likes:-> Post)
    the feed  ->  a walker traversing those edges

There is no database to set up, no `follows` join table, no `likes` table,
no `JOIN ... ON`. `root` persists. Read `load_feed` at the bottom -- it is
the whole feed feature, and it is 8 lines of traversal.

AUTH MODEL -- x.com's, in two sentences:

  * ANONYMOUS VISITORS BROWSE. The seeded instance lives on the shared root,
    and every read an anonymous caller needs (`public_timeline`, `get_profile`,
    `discover_people`, `trending_tags`, `user_posts`) is `def:pub`. You land on
    a populated timeline; there is no login wall.
  * INTERACTION REQUIRES SIGN-IN. Every write (`create_post`, `follow_user`,
    `unfollow_user`, `toggle_like`) and every viewer-relative read (`get_me`,
    `load_feed`) is a plain `def` / `walker` -- JWT required, running on the
    CALLER'S OWN ROOT. So `root` already IS the caller: `_my_profile()` is one
    hop and NOT ONE FUNCTION TAKES A user_id. Nothing to pass, nothing to spoof.

There are no demo credentials. The seeded people are content to read and
follow -- nobody logs in as them. To participate you sign up, and you get your
own Profile on your own root.

Read `jac guide jac-sv-auth` (the `def` / `def:pub` split) and
`jac guide jac-sv-multi-user` (`grant`, `allroots`, `root.shared`).
"""

import from datetime { datetime, timezone, timedelta }
import from threading { Lock }

# ---------------------------------------------------------------------------
# View models -- what crosses the wire.
#
# We never report raw nodes: a view is viewer-relative. `liked_by_me` and
# `is_following` mean something different for every caller, and they are
# computed by *counting edges* at read time (see the impl blocks below). For
# an anonymous caller they are all False -- there is no "me".
# ---------------------------------------------------------------------------

obj ProfileView {
    has id: str,
        username: str,
        display_name: str,
        bio: str,
        followers: int,
        following: int,
        posts: int,
        is_me: bool,
        is_following: bool;
}

obj PostView {
    has id: str,
        content: str,
        author_username: str,
        author_display: str,
        created_at: str,
        like_count: int,
        liked_by_me: bool,
        is_mine: bool,
        reply_count: int,
        reply_to_username: str;
}

obj TrendView {
    has tag: str,
        posts: int;
}

# A profile page is two reads -- the header and the post list. They ship
# together in one walker report (see `LoadProfile`) so the page is assembled
# from a single, always-fresh round trip.
obj ProfilePageView {
    has profile: ProfileView | None,
        posts: list[PostView];
}

# ---------------------------------------------------------------------------
# The nodes -- the only two things that carry state.
#
# Look at what is NOT here: Profile has no `following: list[str]`, and Post
# has no `likes: list[str]`. Those are the SQL-shaped answers. Every
# relationship in this app lives in an edge instead.
# ---------------------------------------------------------------------------

node Profile {
    has username: str = "";
    has display_name: str = "";
    has bio: str = "";
    has created_at: str = "";

    def to_view -> ProfileView;
}

node Post {
    has content: str = "";
    has author_username: str = "";
    has created_at: str = "";
    has reply_to: str = "";
    # The parent post's jid. A reply carries this so the parent's reply list
    # can be assembled by a FORWARD scan (see `_replies_of`) instead of reading
    # a `Reply` edge -- a reply to someone else's post lives on YOUR root, and
    # the edge into their post is not readable from their side (same cross-root
    # rule as likes/followers). "" for a top-level post.
    has reply_to_id: str = "";

    def to_view -> PostView;
}

# ---------------------------------------------------------------------------
# The edges -- the relationships.
#
# Declaring endpoint types (`: Profile --> Post`) is what makes every
# traversal over the edge return a *typed* node, with no per-read filter.
# ---------------------------------------------------------------------------

edge Follows: Profile --> Profile {
    has since: str = "";
}

edge Posted: Profile --> Post {}

edge Likes: Profile --> Post {}

# ---------------------------------------------------------------------------
# Helpers -- `_` prefix keeps them off the HTTP API entirely.
# ---------------------------------------------------------------------------

def _now -> str {
    return datetime.now(timezone.utc).isoformat();
}

def _ago(minutes: int) -> str {
    return (datetime.now(timezone.utc) - timedelta(minutes=minutes)).isoformat();
}

# ---------------------------------------------------------------------------
# Who is asking?
#
# THIS is what auth buys you. An authenticated endpoint (plain `def`, no
# `:pub`) runs on the CALLER'S OWN ROOT, so "me" is not a parameter, not a
# session lookup and not a global -- it is one hop off `root`. Nothing to
# pass, nothing to spoof, nothing to keep in sync.
#
# The one wrinkle is the anonymous case. On a `:pub` endpoint an anonymous
# caller's `root` IS `root.shared` -- and `root.shared` is exactly where the
# seed hangs, so a naive `[root -->[?:Profile]]` would hand every anonymous
# visitor Maya's identity. `jid(root) == jid(root.shared)` is the test for
# "nobody is signed in", and the honest answer then is None: an anonymous
# visitor reads the app, they are not a user of it.
# ---------------------------------------------------------------------------

def _is_anonymous -> bool {
    return jid(root) == jid(root.shared);
}

def _my_profile -> Profile | None {
    if _is_anonymous() {
        return None;
    }
    found = [root -->[?:Profile]];
    return found[0] if len(found) > 0 else None;
}

# ---------------------------------------------------------------------------
# Counting edges that point IN.
#
# Read this before touching the view projections below -- it is the one
# non-obvious rule in this file.
#
# A backward traversal (`[node <-:Edge:<-]`) only finds edges into a node that
# belongs to the CALLER. If the node belongs to another user it silently
# returns empty -- at every permission level, on every root, shared or not.
# The edge is fine and it persists; you just cannot read it from the target's
# side.
#
# Forward traversal has no such limit: `[their_profile ->:Posted:->]` works
# across users -- that is exactly what the feed walker does. So an in-count is
# assembled from the other end: scan the profiles, test their FORWARD edges.
#
# This costs O(profiles) per call, and `_all_profiles` itself costs O(users).
# Fine at starter scale -- but it is the first line to revisit if this app
# grows. A real instance keeps a materialized count.
# ---------------------------------------------------------------------------

"""Every profile on the instance: the seeded people (shared root) plus one per
signed-up user (their own root). `allroots()` is the fan-out; the dedupe is
because a node reachable through more than one root is surfaced once per path,
and a bare append would count it twice."""
def _all_profiles -> list[Profile] {
    found: dict[str, Profile] = {};
    for r in [root.shared] + allroots() {
        for p in [r -->[?:Profile]] {
            found[jid(p)] = p;
        }
    }
    return [p for p in found.values()];
}

def _find_profile(uname: str) -> Profile | None {
    for p in _all_profiles() {
        if p.username == uname {
            return p;
        }
    }
    return None;
}

def _followers_of(who: Profile) -> list[Profile] {
    return [p for p in _all_profiles() if len([edge p ->:Follows:-> who]) > 0];
}

def _likers_of(what: Post) -> list[Profile] {
    return [p for p in _all_profiles() if len([edge p ->:Likes:-> what]) > 0];
}

"""Every reply to a given post, gathered from the FORWARD side. A reply is one
of its author's own Posted posts whose `reply_to_id` names the parent -- so we
scan each profile's own posts, never the parent's `Reply` edges (which a
cross-user reply cannot write visibly)."""
def _replies_of(post_id: str) -> list[Post] {
    out: list[Post] = [];
    for p in _all_profiles() {
        for t in [p ->:Posted:->] {
            if t.reply_to_id == post_id {
                out.append(t);
            }
        }
    }
    return out;
}

# ---------------------------------------------------------------------------
# View projections -- every derived number is an edge count.
# ---------------------------------------------------------------------------

impl Profile.to_view -> ProfileView {
    me = _my_profile();

    # Followers and following are not columns -- they are edge counts.
    # `following` reads this profile's OWN outgoing edges, so a plain forward
    # traversal works. `followers` points IN, so it needs the helper above.
    followers = _followers_of(self);
    following = [self ->:Follows:->];

    am_following = False;
    viewing_self = False;
    if me is not None {
        am_following = len([edge me ->:Follows:-> self]) > 0;
        viewing_self = jid(me) == jid(self);
    }

    return ProfileView(
        id=jid(self),
        username=self.username,
        display_name=self.display_name,
        bio=self.bio,
        followers=len(followers),
        following=len(following),
        posts=len([self ->:Posted:->]),
        is_me=viewing_self,
        is_following=am_following
    );
}

impl Post.to_view -> PostView {
    me = _my_profile();

    # Who liked this post? Everyone one Likes-edge away, pointing in -- so it
    # is counted from the liker's side. See the note above `_all_profiles`.
    likers = _likers_of(self);

    liked = False;
    mine = False;
    if me is not None {
        my_id = jid(me);
        for liker in likers {
            if jid(liker) == my_id {
                liked = True;
            }
        }
        mine = self.author_username == me.username;
    }

    author = _find_profile(self.author_username);
    display = author.display_name if author is not None else self.author_username;

    return PostView(
        id=jid(self),
        content=self.content,
        author_username=self.author_username,
        author_display=display,
        created_at=self.created_at,
        like_count=len(likers),
        liked_by_me=liked,
        is_mine=mine,
        reply_count=len(_replies_of(jid(self))),
        reply_to_username=self.reply_to
    );
}

# ---------------------------------------------------------------------------
# Identity.
#
# `get_me` and `setup_profile` are plain `def`s: JWT required, running on the
# caller's own root. Neither takes a user_id, because neither could use one.
# ---------------------------------------------------------------------------

"""The signed-in caller's profile, or None if they have not made one yet.
401s for an anonymous caller -- the client only calls this when it holds a
token, and that 401 is also how a stale token gets cleared."""
def get_me -> ProfileView | None {
    _seed();
    p = _my_profile();
    return p.to_view() if p is not None else None;
}

"""Turn a fresh account into a participant: one Profile, on the caller's own
root. The sign-up form calls this immediately after `jacLogin`, so there is no
welcome wizard and no /welcome route -- signing up IS the onboarding.

Idempotent: called twice, the second call returns the existing profile.

`grant(..., level=ConnectPerm)` is the load-bearing line. Without it nobody
else can read this profile or attach a Follows-edge to it, so it would never
appear in anyone's explore list and nobody could ever follow it -- silently,
with no error. ConnectPerm and no more: other users attach edges to this
profile, they never write its fields."""
def setup_profile(username: str, display_name: str = "", bio: str = "") -> ProfileView | None {
    _seed();
    if _is_anonymous() {
        return None;
    }

    existing = [root -->[?:Profile]];
    if len(existing) > 0 {
        return existing[0].to_view();
    }

    handle = _unique_handle(_clean_handle(username));
    if len(handle) == 0 {
        return None;
    }

    shown = display_name.strip();
    fresh_profile = root ++> Profile(
        username=handle,
        display_name=shown if len(shown) > 0 else handle,
        bio=bio.strip(),
        created_at=_now()
    );
    grant(fresh_profile, level=ConnectPerm);
    return fresh_profile.to_view();
}

"""A handle is a-z, 0-9 and underscore. Anything else -- an email's `@domain`,
spaces, punctuation -- is dropped, so `Ada Lovelace` -> `adalovelace` and
`ada@example.com` -> `ada`."""
def _clean_handle(raw: str) -> str {
    base = raw.strip().lower().split("@")[0];
    kept = [c for c in base if c.isalnum() or c == "_"];
    return "".join(kept)[0:20];
}

"""Handles are unique across the instance, and profiles live on different
roots, so this is a scan rather than a UNIQUE constraint. A collision resolves
by suffix instead of erroring -- sign-up should never fail on a name."""
def _unique_handle(base: str) -> str {
    if len(base) == 0 {
        return "";
    }
    taken: dict[str, bool] = {};
    for p in _all_profiles() {
        taken[p.username] = True;
    }
    if not taken.get(base, False) {
        return base;
    }
    n = 2;
    while n < 1000 {
        candidate = f"{base}{n}";
        if not taken.get(candidate, False) {
            return candidate;
        }
        n = n + 1;
    }
    return "";
}

# ---------------------------------------------------------------------------
# Public reads -- everything an anonymous visitor needs in order to browse.
#
# `def:pub` == no JWT. Note what none of these is: "my" anything. A signed-in
# caller hitting them still gets viewer-relative views (their token means
# `root` is their root, so `_my_profile()` resolves), so ONE function serves
# both states -- which is the whole reason the login wall can go away.
# ---------------------------------------------------------------------------

"""The logged-OUT home timeline: the latest posts on the instance.

It cannot be "my feed" -- there is no me. So it is a scan, not a traversal:
`_all_profiles()` and each one's forward Posted-edges. Compare `load_feed`,
which is the signed-in version and hops Follows-edges instead. The two are
worth reading side by side: one walks a relationship, the other has none to
walk."""
def:pub public_timeline -> list[PostView] {
    _seed();
    out: list[PostView] = [];
    for p in _all_profiles() {
        for t in [p ->:Posted:->] {
            # A reply carries a Posted edge too (so it shows on its author's
            # profile), but it must NOT surface as a standalone item in the
            # timeline -- it belongs nested under its parent. `reply_to` is
            # empty only for top-level posts.
            if t.reply_to == "" {
                out.append(t.to_view());
            }
        }
    }
    out.sort(key=lambda (v: PostView) { v.created_at; }, reverse=True);
    return out[0:50];
}

def:pub get_profile(username: str) -> ProfileView | None {
    _seed();
    p = _find_profile(username);
    return p.to_view() if p is not None else None;
}

"""Everyone except the caller. An anonymous caller gets the whole instance."""
def:pub discover_people -> list[ProfileView] {
    _seed();
    me = _my_profile();
    out: list[ProfileView] = [];
    for p in _all_profiles() {
        if me is not None and jid(p) == jid(me) {
            continue;
        }
        out.append(p.to_view());
    }
    out.sort(key=lambda (v: ProfileView) { v.followers; }, reverse=True);
    return out;
}

def:pub user_posts(username: str) -> list[PostView] {
    _seed();
    p = _find_profile(username);
    if p is None {
        return [];
    }
    views = [t.to_view() for t in [p ->:Posted:->] if t.reply_to == ""];
    views.sort(key=lambda (v: PostView) { v.created_at; }, reverse=True);
    return views;
}

"""What's happening: hashtags parsed out of every post, counted. Real data --
the same forward `[p ->:Posted:->]` hop the feed walker takes."""
def:pub trending_tags -> list[TrendView] {
    _seed();
    counts: dict[str, int] = {};
    for p in _all_profiles() {
        for t in [p ->:Posted:->] {
            for word in t.content.split() {
                if word.startswith("#") and len(word) > 1 {
                    tag = word.strip(".,!?:;").lower();
                    if len(tag) > 1 {
                        counts[tag] = counts.get(tag, 0) + 1;
                    }
                }
            }
        }
    }
    out = [TrendView(tag=k, posts=v) for (k, v) in counts.items()];
    out.sort(key=lambda (v: TrendView) { v.posts; }, reverse=True);
    return out[0:4];
}

# ---------------------------------------------------------------------------
# Writes -- all authenticated, and not one of them takes a user_id.
#
# A plain `def` 401s without a JWT. That 401 is a feature: it is what the
# client turns into the sign-in dialog, and what clears a stale token.
# ---------------------------------------------------------------------------

def create_post(content: str) -> PostView | None {
    _seed();
    me = _my_profile();
    if me is None or len(content.strip()) == 0 {
        return None;
    }

    fresh = Post(
        content=content.strip(),
        author_username=me.username,
        created_at=_now()
    );

    # Authorship is an edge too. This is also what commits the node: a bare
    # `Post(...)` with no path from root is unreachable and does not persist.
    me +>:Posted:+> fresh;

    # ConnectPerm lets other users attach a Likes-edge. Note what we did NOT
    # need: WritePerm. Because a like is an edge and not a field on the post,
    # nobody else ever mutates this node. Modeling likes as `has likes: list`
    # would have forced us to hand out write access to the whole post.
    grant(fresh, level=ConnectPerm);
    return fresh.to_view();
}

def follow_user(username: str) -> ProfileView | None {
    _seed();
    me = _my_profile();
    target = _find_profile(username);
    if me is None or target is None or jid(me) == jid(target) {
        return None;
    }

    # This edge CROSSES ROOTS: my Profile is on my root, `target` is usually a
    # seeded person on the shared root (or another signed-up user, on theirs).
    # That is fine. ConnectPerm on the target is what allows the attach, and
    # the feed only ever reads this edge FORWARD, from my side.
    if len([edge me ->:Follows:-> target]) == 0 {
        me +>:Follows(since=_now()):+> target;   # <- the whole "follow" feature
    }
    return target.to_view();
}

def unfollow_user(username: str) -> ProfileView | None {
    _seed();
    me = _my_profile();
    target = _find_profile(username);
    if me is None or target is None {
        return None;
    }

    # Unfollow = delete the edge. Typed edges are deleted by querying the edge
    # objects and del-ing each; `del -->` only works on untyped connections.
    for e in [edge me ->:Follows:-> target] {
        del e;
    }
    return target.to_view();
}

def toggle_like(post_id: str) -> PostView | None {
    _seed();
    me = _my_profile();
    if me is None {
        return None;
    }

    # jobj() resolves any granted node by jid, from any root -- and it earns
    # its keep now that a post lives under its AUTHOR's root, somewhere
    # `[root -->]` cannot reach.
    target = jobj(post_id);
    if not isinstance(target, Post) {
        return None;
    }
    # Bind the narrowed value to a typed local. `jobj()` returns `object`, and
    # the isinstance-narrowing does not survive the edge queries below.
    post: Post = target;

    existing = [edge me ->:Likes:-> post];
    if len(existing) > 0 {
        for e in existing {
            del e;                       # unlike = delete the edge
        }
    } else {
        me +>:Likes:+> post;             # like   = create the edge
    }
    return post.to_view();
}

def create_reply(post_id: str, content: str) -> PostView | None {
    _seed();
    me = _my_profile();
    if me is None or len(content.strip()) == 0 {
        return None;
    }

    target = jobj(post_id);
    if not isinstance(target, Post) {
        return None;
    }
    parent: Post = target;

    fresh = Post(
        content=content.strip(),
        author_username=me.username,
        created_at=_now(),
        reply_to=parent.author_username,
        reply_to_id=jid(parent)
    );

    me +>:Posted:+> fresh;
    grant(fresh, level=ConnectPerm);
    return fresh.to_view();
}

def:pub get_replies(post_id: str) -> list[PostView] {
    _seed();
    target = jobj(post_id);
    if not isinstance(target, Post) {
        return [];
    }
    post: Post = target;
    replies = [r.to_view() for r in _replies_of(jid(post))];
    replies.sort(key=lambda (v: PostView) { v.created_at; }, reverse=False);
    return replies;
}

# ---------------------------------------------------------------------------
# THE FEED.
#
# This is the money shot -- the reason this app is a graph and not a schema.
#
# In SQL you would write:
#
#     SELECT p.* FROM posts p
#     JOIN follows f ON f.followee_id = p.author_id
#     WHERE f.follower_id = :me
#     UNION SELECT * FROM posts WHERE author_id = :me
#     ORDER BY created_at DESC;
#
# Here you don't query the relationships. You walk them.
#
# A plain `walker` (no `:pub`) needs a JWT and spawns on the CALLER'S OWN
# ROOT, which is why it takes no argument at all: `root` is already you.
# ---------------------------------------------------------------------------

walker load_feed {
    # Typed report channel. The `= []` default matters: without it `reports`
    # becomes a REQUIRED spawn argument and every call fails.
    has reports: list[list[PostView]] = [];

    # Accumulate across the traversal, report ONCE at the end.
    has collected: list[PostView] = [];

    can start with Root entry {
        _seed();

        # Whose feed? Mine. `root` is the caller's own root, so this is not a
        # lookup -- it is one hop, and it cannot return anybody else.
        found = _my_profile();
        if found is None {
            skip;                # no profile yet -> visit nothing, report []
        }
        me: Profile = found;

        # The feed, stated directly: my posts, plus the posts of everyone I
        # follow. `[me ->:Follows:->]` IS the query -- one hop along the
        # follow-edges. No join table, no `WHERE author_id IN (SELECT ...)`.
        # Those edges cross roots -- I follow people seeded on the shared root
        # -- and the hop does not care.
        visit [me];
        visit [me ->:Follows:->];
    }

    can gather with Profile entry {
        # Fires once per profile queued above (mine, then each followee).
        # `here` is that profile -- walk its Posted-edges and take the posts.
        # Skip replies (`reply_to` set): the home feed is top-level posts, the
        # same rule public_timeline uses.
        for post in [here ->:Posted:->] {
            if post.reply_to == "" {
                self.collected.append(post.to_view());
            }
        }

        # Deliberately NOT visiting [here ->:Follows:->] again. That would make
        # the feed transitive (friends-of-friends). One hop is the feed.
    }

    can finish with Root exit {
        # Exit abilities run after the whole traversal drains, so this is the
        # natural place for the single, sorted report.
        self.collected.sort(key=lambda (v: PostView) { v.created_at; }, reverse=True);
        report self.collected;
    }
}


# ---------------------------------------------------------------------------
# THE PROFILE READ -- a walker on purpose, for the SAME reason load_feed is.
#
# `get_profile` and `user_posts` are `def:pub` FUNCTIONS, and the client caches
# reader-function responses in memory for 60s. In dev the write->read
# invalidation manifest is empty, so a reply or like you just made is not
# reflected when you return to a profile until that cache ages out (only a full
# page refresh, which wipes the in-memory cache, shows it). The home feed never
# has this problem because `load_feed` is a WALKER, and walkers are classified
# as writers -- never cached, always fresh.
#
# So the profile reads through a walker too. `:pub` keeps it readable while
# signed out (an anonymous caller runs on `root.shared`; a caller WITH a token
# runs on their own root, so `is_me` / `liked_by_me` stay viewer-relative). One
# report carries both halves of the page.
# ---------------------------------------------------------------------------
walker:pub LoadProfile {
    has username: str = "";

    can go with Root entry {
        report ProfilePageView(
            profile=get_profile(self.username),
            posts=user_posts(self.username)
        );
    }
}


# ---------------------------------------------------------------------------
# THE SEED -- extracted to services/seed.jac for readability.
# ---------------------------------------------------------------------------

import from services.seed { _seed }


# ---------------------------------------------------------------------------
# Mutations are WALKERS, and that is not cosmetic.
#
# The client caches "reader" endpoint responses for 60s and only clears that
# cache when a WRITER runs. The compile-time classifier only labels `:pub`
# functions declared in the entry module, so a mutation living in this file is
# never classified and silently defaults to reader -- you post, it saves, and
# the timeline serves a stale copy until the cache expires.
#
# Walkers default to writer regardless of module, so routing every mutation
# through one keeps the feed honest. Each walker is a thin shell over the
# function below it: same auth (plain `walker` == JWT, runs on the caller's own
# root), same body, no logic duplicated.
#
# See https://docs.jaseci.org/tutorials/language/osp/ -- "switch to walkers
# when you need authentication, per-user data isolation, or multi-step graph
# traversal."
# ---------------------------------------------------------------------------

walker SetupProfile {
    has username: str = "";
    has display_name: str = "";
    has bio: str = "";

    can go with Root entry {
        made = setup_profile(self.username, self.display_name, self.bio);
        if made is not None {
            report made;
        }
    }
}

walker CreatePost {
    has content: str = "";

    can go with Root entry {
        made = create_post(self.content);
        if made is not None {
            report made;
        }
    }
}

walker CreateReply {
    has post_id: str = "";
    has content: str = "";

    can go with Root entry {
        made = create_reply(self.post_id, self.content);
        if made is not None {
            report made;
        }
    }
}

walker FollowUser {
    has username: str = "";

    can go with Root entry {
        updated = follow_user(self.username);
        if updated is not None {
            report updated;
        }
    }
}

walker UnfollowUser {
    has username: str = "";

    can go with Root entry {
        updated = unfollow_user(self.username);
        if updated is not None {
            report updated;
        }
    }
}

walker ToggleLike {
    has post_id: str = "";

    can go with Root entry {
        updated = toggle_like(self.post_id);
        if updated is not None {
            report updated;
        }
    }
}

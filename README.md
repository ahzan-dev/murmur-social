# Murmur

A small social app — post, follow, like, feed — where the social graph **is**
the data model.

In SQL, "show me posts from people I follow" is a join table and a query
optimizer. Here it is `++>` and a walker.

It opens the way x.com does when you are logged out: a **populated public
timeline**, in the full three-column layout, with no sign-in form in the way.
Read it, click through profiles, browse who to follow. The moment you try to
*do* something — post, follow, like — a sign-in dialog opens over the top.
There is no login wall, and there are no demo credentials.
See [Auth](#auth-browse-anonymously-sign-in-to-participate).

## The graph model

Two nodes carry state. Every relationship is an edge. This is the whole schema,
from [`services/social.sv.jac`](services/social.sv.jac):

```jac
edge Follows: Profile --> Profile {
    has since: str = "";
}

edge Posted: Profile --> Post {}

edge Likes: Profile --> Post {}
```

A follow is an edge. A like is an edge. Authorship is an edge.

Look at what is **not** on the nodes:

```jac
node Profile {
    has username: str = "";
    has bio: str = "";
    has created_at: str = "";
    ...
}
```

No `following: list[str]`. No `followers_count: int`. `Post` has no
`likes: list[str]`. Those are the SQL-shaped answers — a relationship flattened
into a column because the table couldn't hold it. Every number this app displays
is counted from edges at read time, in `Profile.to_view` / `Post.to_view`.

Declaring the endpoint types (`: Profile --> Post`) is what makes every traversal
over the edge return a *typed* node, with no per-read filter.

Modeling likes as edges buys something concrete. Look at `create_post`:

```jac
grant(fresh, level=ConnectPerm);
```

`ConnectPerm` lets another user attach a `Likes`-edge and nothing more. Nobody
else can write your post's fields — because a like never touches the post. Had
you modeled likes as `has likes: list[str]` on the node, every liker would have
needed **write access to the whole post**.

And unfollowing is not an `UPDATE`:

```jac
for e in [edge me ->:Follows:-> target] {
    del e;
}
```

## The feed is a walker

This is the payoff. In SQL you would write (the comment above the walker in the
source says the same):

```sql
SELECT p.* FROM posts p
JOIN follows f ON f.followee_id = p.author_id
WHERE f.follower_id = :me
UNION SELECT * FROM posts WHERE author_id = :me
ORDER BY created_at DESC;
```

Here you don't query the relationships. You walk them:

```jac
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
        visit [me];
        visit [me ->:Follows:->];
    }

    can gather with Profile entry {
        # Fires once per profile queued above (mine, then each followee).
        # `here` is that profile -- walk its Posted-edges and take the posts.
        for post in [here ->:Posted:->] {
            self.collected.append(post.to_view());
        }

        # Deliberately NOT visiting [here ->:Follows:->] again. That would make
        # the feed transitive (friends-of-friends). One hop is the feed.
    }

    can finish with Root exit {
        # Exit abilities run after the whole traversal drains, so this is the
        # natural place for the single, sorted report.
        self.collected.sort(key=lambda v: PostView : v.created_at, reverse=True);
        report self.collected;
    }
}
```

Two lines are the entire feed query:

```jac
visit [me];
visit [me ->:Follows:->];
```

`visit` queues nodes. `can gather with Profile entry` then fires once per queued
profile — yours, then each person you follow — and `here` is that profile. The
`JOIN` became a hop.

The walker **deliberately does not recurse.** `gather` never queues
`[here ->:Follows:->]` again. Add that one line and the feed becomes transitive:
friends-of-friends, then their friends, until you have walked the whole instance.
One hop is the feed. That decision is a line of traversal, not a rewritten query.

`can finish with Root exit` runs after the traversal drains — the natural place
for a single sorted `report`.

Note the walker takes **no argument**. It is a plain `walker` (not `walker:pub`),
so it needs a JWT and spawns on the caller's **own root** — `root` already *is*
you. There is no `user_id` to pass and none to forge.

The client side is one line, in
[`components/HomeFeed.cl.jac`](components/HomeFeed.cl.jac):

```jac
result = root spawn load_feed();
```

### Watch it work

Sign up, and your feed starts **empty** — you follow nobody, so there are no
`Follows`-edges to hop and the walker has nothing to gather but your own posts.
Go to Explore and follow `@maya`, and her posts appear in your feed. Unfollow
her and they leave again.

Nothing was re-queried, and no filter changed. The walker is byte-for-byte the
same; you added one edge to the graph and the traversal found it:

| you follow | feed |
|---|---|
| nobody | your posts only |
| `@maya` | + her 4 posts |
| `@maya`, `@devon` | + his 4 as well |

That edge **crosses roots** — your Profile is on your own root, Maya is seeded
on the shared one — and the hop does not care. That is what "the graph is the
query" buys you.

## `root` persists — there is no database to set up

There is no schema file, no migration, no connection string, no ORM. Nothing in
this repo configures storage — and you still get a real database. Jac persists
the graph for you: **SQLite in `.jac/data/` by default**, and one env var
(`MONGODB_URI`, or `[scale.database] mongodb_uri`) flips the same code to
MongoDB with a Redis L2 cache. Same model on both — see
`jac guide jac-sv-persistence`. You write:

```jac
fresh = root ++> Profile(username=username, bio=bio, created_at=_now());
```

…and it is there on the next request.

The corollary bites once, so learn it here: **a node with no path from `root`
does not persist.** In `create_post`, the `Posted`-edge is not just modeling
authorship — it is what commits the node:

```jac
fresh = Post(content=..., author_username=..., created_at=_now());

# Authorship is an edge too. This is also what commits the node: a bare
# `Post(...)` with no path from root is unreachable and does not persist.
me +>:Posted:+> fresh;
```

A bare `Post(...)` that you never connect is garbage.

## Auth: browse anonymously, sign in to participate

**Anonymous visitors can read the whole app.** There is no login wall, and no
`(auth)` route group. Every read an anonymous caller needs is `def:pub`:

```jac
def:pub public_timeline -> list[PostView] { ... }   # the logged-out home feed
def:pub get_profile(username: str) -> ProfileView | None { ... }
def:pub discover_people -> list[ProfileView] { ... }
def:pub trending_tags -> list[TrendView] { ... }
def:pub user_posts(username: str) -> list[PostView] { ... }
```

**Interaction requires an account.** Every write, and every read that only means
something relative to a viewer, is a plain `def` — JWT required:

```jac
def get_me -> ProfileView | None { ... }
def create_post(content: str) -> PostView | None { ... }
def follow_user(username: str) -> ProfileView | None { ... }
def toggle_like(post_id: str) -> PostView | None { ... }
walker load_feed { ... }
```

That split is the entire auth model. `jac guide jac-sv-auth` is authoritative:
only `:pub` skips the JWT; plain `def`, `:priv` and `:protect` are all equally
locked down.

### `root` is the caller — so nothing takes a `user_id`

A plain `def` runs on the **caller's own root**. That is not a convenience, it
is the security property: identity is *structural*, not a parameter you
remember to validate.

```jac
def _my_profile -> Profile | None {
    if _is_anonymous() {
        return None;
    }
    found = [root -->[?:Profile]];
    return found[0] if len(found) > 0 else None;
}
```

That is the whole "who is asking" implementation. Not one endpoint in this app
takes a `user_id`, because not one endpoint *could use* one. There is nothing to
pass and nothing to spoof.

The `_is_anonymous()` guard exists for one reason: on a `:pub` endpoint an
anonymous caller's `root` **is** `root.shared` — which is exactly where the seed
lives. Without the guard, `[root -->[?:Profile]]` would hand every anonymous
visitor Maya's identity. `jid(root) == jid(root.shared)` is the test for "nobody
is signed in", and the honest answer is then `None`: an anonymous visitor reads
the app, they are not a user of it.

### Signing up is the onboarding

There is no `/welcome` page and no wizard. The sign-up form in
[`components/AuthDialog.cl.jac`](components/AuthDialog.cl.jac) does three awaited
steps, and the order is fixed:

```jac
signup_result = await jacSignup(email, password);   # account. NO session yet.
login_ok      = await jacLogin(email, password);    # session.
profile       = await setup_profile(username, display_name);   # <- first authenticated call
```

`setup_profile` is the `root ++> Profile(...)` that gives the new user a profile
**on their own root**, plus its `grant()`. Skip an `await` on any of those three
and the next line runs unauthenticated — a 401 that only shows up on a real first
registration.

Interaction prompts sign-in **without navigating away**: `requireSignIn()` fires
a window event, and `<SignInDialog />` (mounted once in `pages/layout.jac`) opens
over the page. The feed underneath keeps its scroll and its state. A redirect to
`/login` would lose both.

### The seeded people are content, not accounts

**Nobody logs in as Maya.** There are no demo credentials in this template and
no "sign in as @maya" shortcut. The eight seeded people exist to be read and
followed. To participate, you sign up and get your own profile.

Which is why the seed lives on **`root.shared`**, the deployment's public
commons, and not on `root`:

```jac
fresh_profile = root.shared ++> Profile(...);
grant(fresh_profile, level=ConnectPerm);
```

`root` is whoever happened to make the first request. Hang the seed there and it
is one user's private data: every *other* visitor opens an empty app.
`root.shared` is reachable from every request context, so the seed is the
instance's content rather than somebody's.

And **`grant(node, level=ConnectPerm)` on every seeded Profile and Post is what
makes that content legible.** A node's owner is still whichever request triggered
the seed, so without the grant every other caller reads `NO_ACCESS`, and every
feed, every profile page and every count silently comes back empty — no error,
no warning, just nothing. `ConnectPerm` is the least that works: strangers attach
`Follows`- and `Likes`-edges to these nodes, they never write their fields.

This is the single most expensive line to forget in a multi-root Jac app.

- `jac guide jac-sv-auth` — `def` vs `def:pub` vs `def:protect`, JWT, the login flow.
- `jac guide jac-sv-multi-user` — `grant()`, `allroots()`, `root.shared`.
- The sibling **`fullstack-auth`** template — auth with a login wall, for when
  every page *should* be private.

### The seed

`_seed()` runs at the top of every endpoint and builds the instance once —
eight profiles, eighteen posts, an asymmetric follow graph, uneven likes. It is
idempotent twice over: an in-process flag, plus a graph check so a restart onto
a populated root doesn't duplicate anyone.

Every row becomes **real nodes and real edges**. There is no fixture layer and
no mock — the seed calls the same `++>` and `+>:Follows:+>` your own code
would. Delete `_seed()` and the app is simply empty.

**The people are invented.** Maya, Devon, Priya, Jonas, Tess, Ren, Cara and Sam
do not exist, and neither do their opinions about border radii.

## Set `JAC_JWT_SECRET` before you deploy

**Do this before the app is reachable by anyone else.** `jac.toml` has:

```toml
[scale.jwt]
secret = "${JAC_JWT_SECRET:-murmur-dev-secret-change-before-deploy}"
```

The fallback is fine on your laptop and **must not** survive to a deployment:

```bash
export JAC_JWT_SECRET="$(openssl rand -hex 32)"
```

Why this section exists at all: **a Jac app that configures no JWT secret uses
the same hardcoded default as every other Jac app** —
`supersecretkey_for_testing_only!`, which ships in the source of every Jac
install on earth. Two things follow, and both are real:

1. **Anyone can forge a token for any user.** The "secret" is public knowledge.
2. **Tokens leak between apps on the same origin.** The client stores its token
   under an un-namespaced `jac_token` key in `localStorage`, so a token minted by
   a *different* Jac app on the same origin — `localhost:8000` during development,
   or a shared preview host — **validates here**. It then fails with a `500
   "User not found"`, because that user only exists in the other app's identity
   store. And since the client only clears its token on a `401`, the app gets
   stuck in a broken "logged in" state that a reload does not fix.

Giving this app its own secret fixes both. The forged-token problem goes away,
and the cross-app token turns into a clean `401` — which the client handles
properly by dropping the stale token and showing the sign-in form.

## Counting edges that point in

This is the one non-obvious constraint in the codebase, and you will trip on it
if you don't read this. It is documented in the source above `_all_profiles`.

**A backward traversal `[node <-:Edge:<-]` silently returns empty when the node
belongs to a different user.** The edge is created fine and it persists — you
just cannot read it from the target's side. Only the request that created the
edge sees it.

The facts, all verified empirically:

- **It is not a permissions problem.** Verified at `ConnectPerm` *and*
  `WritePerm`. More access does not help.
- **`root.shared` does not fix it.** Verified: with both nodes in the shared
  commons, even the user who created the edge reads 0 on a later request.
- **Forward traversal has no such limit.** `[their_profile ->:Posted:->]` works
  across users. That is exactly why `load_feed` works while a naive
  `[me <-:Follows:<-]` follower count reads 0.

So in-counts are assembled from the other end: scan the profiles and test their
**forward** edges.

```jac
def _followers_of(who: Profile) -> list[Profile] {
    return [p for p in _all_profiles() if len([edge p ->:Follows:-> who]) > 0];
}

def _likers_of(what: Post) -> list[Profile] {
    return [p for p in _all_profiles() if len([edge p ->:Likes:-> what]) > 0];
}
```

So the rule for this codebase:

> **Never read an in-count with `<-:Edge:<-` across users. Go through
> `_followers_of` / `_likers_of`.**

Out-counts are fine as plain forward traversals — `Profile.to_view` reads
`following` and `posts` directly, because those edges are the profile's own:

```jac
followers = _followers_of(self);          # points IN  -> helper
following = [self ->:Follows:->];         # points OUT -> plain traversal
```

Because this app now has **many roots** — the shared one that holds the seed,
plus one per signed-up user — `_all_profiles()` is an `allroots()` fan-out,
deduped on `jid`:

```jac
def _all_profiles -> list[Profile] {
    found: dict[str, Profile] = {};
    for r in [root.shared] + allroots() {
        for p in [r -->[?:Profile]] {
            found[jid(p)] = p;
        }
    }
    return [p for p in found.values()];
}
```

The dedupe is not optional: a node reachable through more than one root is
surfaced once per path, so a bare append double-counts it. And note that
`_followers_of` / `_likers_of` **did not change at all** when auth arrived. That
is the point: the forward-scan *shape* is what matters, not which roots you
scanned to build the list.

**The cost, stated plainly:** this is O(profiles) per call, and `_all_profiles`
itself is O(users) — the same `allroots()` fan-out the official `global_feed()`
example does. That is fine at starter scale, but it is the first line to revisit
if this app grows: a real instance would maintain a materialized count or an
index node rather than scanning on every render.

## Run it

```bash
jac install
jac start --dev
```

Open <http://localhost:8000>. The timeline is already there, and you are not
asked to sign in to read it. Click Follow on anyone and the sign-in dialog opens
— create an account, and watch your (empty) feed fill up as you follow people.
That's the walker above, running live.

## Layout

```
main.jac                        entry: server import + cl { } app shell
jac.toml                        project, theme, JWT secret, microservices off
services/social.sv.jac          THE FILE: nodes, edges, endpoints, load_feed, seed

pages/layout.jac                three-column shell (rail / feed / sidebar) + SignInDialog
pages/index.jac                 /             home feed (public timeline when signed out)
pages/explore.jac               /explore      everyone else
pages/u/[username].jac          /u/:username  a profile

components/HomeFeed.cl.jac      public_timeline (a scan) OR load_feed (a traversal)
components/AuthDialog.cl.jac    requireSignIn() + the sign-in/sign-up dialog
components/AccountMenu.cl.jac   who you are, or a Sign in button
components/PostCard.cl.jac      the like button -> toggles a Likes-edge
components/FollowButton.cl.jac  follow/unfollow -> one Follows-edge
components/PostComposer.cl.jac  create_post -> a Posted-edge
components/ExplorePeople.cl.jac discover_people
components/UserProfile.cl.jac   profile page; every stat is an edge count
components/LeftNav.cl.jac       the rail: 72px icons, 275px with labels
components/RightSidebar.cl.jac  who-to-follow + trending, both read off the graph
components/MobileBar.cl.jac     the < 768px top bar
components/ui/                  jac-shadcn primitives (yours to edit)

lib/utils.cl.jac                cn()
lib/format.cl.jac               timeAgo(), initials()
styles/global.css               semantic tokens
```

There is deliberately no `(auth)` route group and no `AuthGuard`: every page is
readable signed out. Auth here is not a wall around the app, it is a condition on
writing to it — enforced server-side by the `def` / `def:pub` split, and surfaced
client-side as a dialog. (The sibling `fullstack-auth` template shows the other
shape, where an `(auth)` directory wraps every page in a guard automatically.)

### The layout

Three columns, modeled on x.com, driven by Tailwind breakpoints plus one
arbitrary `min-[1100px]:` stop:

| width | shape |
|---|---|
| `< 768px` | top bar + feed. No rail, no sidebar. |
| `>= 768px` | 72px icon rail + feed. |
| `>= 1100px` | 275px rail with labels + 600px feed + 350px sidebar. |

The rails are `sticky top-0 h-svh`; the centre column is the only thing that
scrolls with the page.

## Extending it

See [`AGENTS.md`](AGENTS.md) — it has a **Try next** list of concrete prompts,
plus the rules that keep this template honest and how to reach the reference
guides bundled with the compiler (`jac guide jac-node-edge-patterns` and
`jac guide jac-walker-patterns` are the two that matter here).

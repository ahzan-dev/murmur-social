# Working in this Jac project

This is a [Jac](https://www.jaseci.org/) project. Jac's syntax has evolved and
is easily confused with Python or JSX -- before writing or editing `.jac`
files, consult the reference guides bundled with the compiler.

## Reference guides

The `jac` CLI ships curated reference guides ("Agent Skills") -- the
authoritative spec for writing correct, idiomatic Jac:

- `jac guide` -- list every available guide
- `jac guide <name>` -- print a guide (e.g. `jac guide jac-types`)
- `jac guide --search <keyword>` -- find guides by topic
- `jac guide --json` -- machine-readable output for tooling

Start with `jac guide jac-core-cheatsheet` and `jac guide jac-types`.

**For this project specifically, read `jac guide jac-node-edge-patterns` and
`jac guide jac-walker-patterns` before touching `services/social.sv.jac`.** They
are the authoritative spec for edges, typed traversals, and walker abilities.
Also relevant here:

- `jac guide jac-sv-multi-user` -- `allroots()`, `grant()`, permission levels.
- `jac guide jac-sv-auth` -- `def` vs `def:pub` vs `def:priv`.
- `jac guide jac-sv-persistence` -- what commits a node, view models, `jobj()`.

## What this app is

A little X, with x.com's logged-out model: an anonymous visitor lands on a
**populated public timeline** in the full three-column layout — no login wall —
and the moment they try to post, follow or like, a **sign-in dialog** opens over
the page. Eight fictional people are seeded on the shared root as content to
read and follow. **Nobody logs in as them**: there are no demo credentials, and
signing up is how you get a profile.

The point of the whole template: **the social graph IS the data model.**
`services/social.sv.jac` declares two stateful nodes and three edges:

```jac
edge Follows: Profile --> Profile { has since: str = ""; }
edge Posted:  Profile --> Post {}
edge Likes:   Profile --> Post {}
```

A follow is an edge. A like is an edge. The feed is a walker that hops one step
along `Follows` and reads `Posted`. No join table, no migration, no database to
set up — `root` persists, and Jac stores it for you (SQLite in `.jac/data/` by
default, MongoDB via `MONGODB_URI`). See `jac guide jac-sv-persistence`.

The rules that keep this template honest:

- **Model relationships as edges, never as list-of-id fields.** If you find
  yourself adding `has following: list[str]` or `has likes: list[str]` to a
  node, you have taken a wrong turn — add an `edge` instead. This is not style:
  a like-as-edge needs only `ConnectPerm` on the post, while a like-as-field
  would force you to hand every liker `WritePerm` on the whole node.
- **Never read an in-count with a backward traversal across users.**
  `[node <-:Edge:<-]` silently returns empty when the node belongs to another
  user — at every permission level, on shared roots too. The edge exists and
  persists; you just cannot read it from the target's side. Forward traversal
  has no such limit. So counts that point IN go through the helpers in
  `services/social.sv.jac`: **`_followers_of(profile)` and `_likers_of(post)`**,
  which scan `_all_profiles()` and test each one's FORWARD edges. Counts that
  point OUT (`[me ->:Follows:->]`, `[me ->:Posted:->]`) are plain traversals.
  Read the comment block above `_all_profiles` before changing any view.
  `_all_profiles()` is an `allroots()` fan-out (shared root + one per signed-up
  user) deduped on `jid` — the dedupe is not optional, since a node reachable
  through more than one root is surfaced once per path. The helpers on top of it
  are the part that generalizes: they did not change at all when auth arrived.
- **Every derived number is an edge count, computed at read time** in
  `to_view()`. Do not add a counter field and try to keep it in sync.
- **The auth split is READ vs WRITE, not page vs page.** Reads an anonymous
  visitor needs are `def:pub`: `public_timeline`, `get_profile`,
  `discover_people`, `trending_tags`, `user_posts`. Writes and viewer-relative
  reads are plain `def` / `walker` (JWT required): `get_me`, `setup_profile`,
  `create_post`, `follow_user`, `unfollow_user`, `toggle_like`, `load_feed`.
  **Do not add a login wall** — no `(auth)` route group, no `AuthGuard`, no
  redirect to a `/login` page. An anonymous visitor must land on a populated
  timeline. Interaction prompts sign-in via `requireSignIn()` →
  `<SignInDialog />`, which opens over the page and loses nothing.
  `jac guide jac-sv-auth` is authoritative; only `:pub` skips the JWT.
- **No endpoint takes a `user_id`, ever.** A plain `def` runs on the caller's
  own root, so identity is structural: `_my_profile()` is `[root -->[?:Profile]]`
  and there is nothing to pass or forge. If you find yourself adding a `user_id`
  / `username` parameter to identify *the caller*, you have taken a wrong turn.
  (A `username` that names *someone else* — `get_profile`, `follow_user` — is
  fine: that is a target, not an identity.)
- **`_my_profile()` must keep its `_is_anonymous()` guard.** On a `:pub`
  endpoint an anonymous caller's `root` **is** `root.shared` — which is where
  the seed lives — so a bare `[root -->[?:Profile]]` would hand every anonymous
  visitor Maya's identity. `jid(root) == jid(root.shared)` is the test.
- **Never ship demo credentials.** No "sign in as @maya" shortcut, no seeded
  passwords. The seeded people are content to read and follow; participating
  means signing up. Sign-up is also the whole onboarding — `jacSignup` →
  `jacLogin` → `setup_profile`, all awaited, in the dialog. Do not add a
  `/welcome` page or an onboarding wizard.
- **The seed goes on `root.shared`, and every seeded node gets granted.**
  `root.shared ++> Profile(...)` then `grant(node, level=ConnectPerm)` — see
  `_build_seed`. `root` is whoever made the first request; hang the seed there
  and it becomes one user's private data. And a node's owner is still whoever
  triggered the seed, so **without the grant every other caller reads NO_ACCESS
  and every feed silently comes back empty** — no error, no warning. Same rule
  for anything users create for each other (`create_post`, `setup_profile`).
  ConnectPerm, not WritePerm: strangers attach edges, they never write fields.
- **Views cross the wire, never raw nodes.** `ProfileView` / `PostView` are
  viewer-relative (`is_me`, `liked_by_me`, `is_following`), so they must be built
  per caller — and they must degrade honestly to `False` for an anonymous one.
- **The seed is real nodes, not fixtures.** `_seed()` uses the same `++>` and
  `+>:Follows:+>` your code would, and is idempotent (in-process flag + graph
  check). Keep seed content fictional and unbranded, keep the follow graph
  asymmetric and the like counts uneven — a symmetric seed makes the follower
  counts on a profile page prove nothing.

## Styling rules

- Semantic tokens only: `bg-background`, `text-muted-foreground`, `bg-card`,
  `border-border`, `text-primary`, `text-destructive`. Never a raw Tailwind
  color like `text-green-400`, never a hex value.
- Single theme. There is deliberately no light/dark toggle.
- Concatenate classes with `cn()` from `lib/utils.cl.jac`, never with `+`.
- Physical padding (`pt-4 pb-4`), not shorthand (`py-4`).
- New colors go in `styles/global.css` as tokens (`:root` + `@theme inline`),
  not inline in a component. Do not run `jac retheme` — it regenerates
  `global.css` and wipes custom tokens.
- The layout is three columns at `>= 1100px`, an icon rail + feed at `>= 768px`,
  and feed-only under that. Those stops live in `pages/layout.jac`,
  `components/LeftNav.cl.jac` and `components/RightSidebar.cl.jac`. This
  template renders inside a resizable preview panel as narrow as 200px, so
  check any layout change at 200, 650 and 1450 before calling it done.

## Try next

Concrete next steps. Each is a self-contained prompt you can hand to an agent.

1. **"Add a profile editor."** `setup_profile` already writes `display_name` and
   `bio` on the caller's own root, but nothing in the UI ever changes them after
   sign-up — every seeded person has a bio and you have none. Add an
   `update_profile(display_name, bio)` (plain `def`, no user_id — `root` is
   already you) and an edit dialog on your own profile page, shown when
   `profile.is_me`. Note what you do NOT need: a re-`grant()`. The profile was
   granted at creation and you are only writing your own fields.
2. **"Add reposts."** Add `edge Reposted: Profile --> Post {}` and a
   `toggle_repost(post_id: str)` beside `toggle_like` — same shape: `jobj()` the
   post, create or `del` the edge. Then queue reposts in `load_feed.gather`
   alongside `[here ->:Posted:->]`. The repost count points IN, so add a
   `_reposters_of(post)` helper next to `_likers_of` — do not reach for
   `[post <-:Reposted:<-]`.
3. **"Add replies as a threaded edge."** Add `edge ReplyTo: Post --> Post {}` and
   have `create_post` take an optional `parent_id`. A thread is then a recursive
   walker: `visit [here ->:ReplyTo:->]` from a `Post` entry ability — the one
   place recursion is what you actually want, unlike `load_feed`. Reply counts
   point IN, so count them from the child side.
4. **"Add a notifications feed."** When `follow_user` / `toggle_like` creates an
   edge, also attach a `Notification` node under the *actor's* root and
   `grant()` it. Reading them is the same forward-side pattern as
   `_followers_of`: scan `_all_profiles()` and collect notifications aimed at
   me — a backward traversal from my profile will read empty.
5. **"Add hashtag search."** Parse `#tags` in `create_post` and connect a
   `Tag` node per hashtag with `edge Tagged: Post --> Tag {}`. Search is then a
   walker that finds the `Tag` and reads posts back — since that direction points
   IN to the tag, either keep tags under a shared root or collect from the post
   side via `_all_profiles()`.
6. **"Show mutual follows on a profile."** In `Profile.to_view`, intersect
   `[me ->:Follows:->]` with `_followers_of(self)` on `jid`. Both sides are
   already available — the point of the exercise is that a "mutuals" query is
   set intersection over two traversals, not a self-join.
7. **"Add a global/discover feed of every recent post."** A second walker that
   iterates `_all_profiles()` and reads each one's `[p ->:Posted:->]`, sorted by
   `created_at` — note how little it shares with `load_feed`: no `Follows` hop,
   so it is a scan, not a traversal. Same O(profiles) cost as `_followers_of`;
   fine at this scale, worth an index node later. `trending_tags` in
   `services/social.sv.jac` is already this shape — read it first.
8. **"Add follower-only posts."** Give `Post` a `has visibility: str` and filter
   in `load_feed.gather` by whether `here` follows the viewer — i.e. check
   `len([edge here ->:Follows:-> me]) > 0`, which is a forward traversal from
   the author and therefore actually readable.

## Validate your work

- `jac check <file>` -- type-check and lint. Compiler diagnostics link to the
  relevant guide; follow the `-> run 'jac guide ...'` hints.
- `jac run <file>` -- execute a Jac script.
- `jac start --dev main.jac` -- start a web-app or service in dev mode
  (hot-reload for client files; restart for server changes). Use this instead
  of `jac run` for apps.
- `jac browse <action>` -- QA a running app in a headless browser:
  `jac browse open localhost:8000`, then `snapshot` (accessibility tree with
  `@e1`-style refs), `click @e5`, `fill '#email' user@example.com`, `screenshot`, `close`.

_Generated by `jac create`._

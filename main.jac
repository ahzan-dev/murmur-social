"""Murmur -- a social app, rebuilt on the graph.

Composition root. Everything the client boots from lives here:

  1. the server import  -- registers every endpoint in services/social.sv.jac
  2. the global stylesheet
  3. `app()` -- the MANUAL router. `base_route_app = "app"` in jac.toml points
     the client at this component instead of the file-based `pages/` convention,
     so routes are declared explicitly with <Router>/<Routes>/<Route>. Every
     route nests inside <SocialLayout>, which renders the matched page at its
     <Outlet />.

The graph model is in  services/social.sv.jac  (read `load_feed` first).
The route targets are the real components in  components/.
"""

import from services.social {
    Profile,
    Post,
    ProfileView,
    PostView,
    TrendView,
    ProfilePageView,
    get_me,
    setup_profile,
    public_timeline,
    get_profile,
    discover_people,
    trending_tags,
    user_posts,
    create_post,
    follow_user,
    unfollow_user,
    toggle_like,
    create_reply,
    get_replies,
    load_feed,
    LoadProfile,
    SetupProfile,
    CreatePost,
    CreateReply,
    FollowUser,
    UnfollowUser,
    ToggleLike
}

import from services.seed { _seed }

cl import ".styles.global.css";
cl import from "@jac/runtime" { Router, Routes, Route, useParams }
cl import from .components.SocialLayout { SocialLayout }
cl import from .components.HomeFeed { HomeFeed }
cl import from .components.ExplorePeople { ExplorePeople }
cl import from .components.UserProfile { UserProfile }

cl {
    def:pub UserPage() -> JsxElement {
        params = useParams();
        # useParams() returns a plain JS object -- subscript access, and a
        # truthy check (a missing param is `undefined`, which `is not None` misses).
        username = params["username"];
        if not username {
            return <p className="pt-12 pb-12 text-center text-sm text-muted-foreground">Not found.</p>;
        }
        return <UserProfile username={username} />;
    }

    def:pub app() -> JsxElement {
        return <div className="min-h-svh bg-background text-foreground antialiased">
            <Router>
                <Routes>
                    <Route element={<SocialLayout />}>
                        <Route path="/" element={<HomeFeed />} />
                        <Route path="/explore" element={<ExplorePeople />} />
                        <Route path="/u/:username" element={<UserPage />} />
                    </Route>
                </Routes>
            </Router>
        </div>;
    }
}

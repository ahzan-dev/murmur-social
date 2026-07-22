"""Murmur -- a social app, rebuilt on the graph.

Composition root. Three things live here and nothing else:

  1. the server import  -- registers every endpoint in services/social.sv.jac
  2. the global stylesheet
  3. `app()`            -- the shell the router mounts its pages inside

The graph model is in  services/social.sv.jac  (read `load_feed` first).
The routes are in      pages/
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

cl {
    def:pub app(children: any = None) -> JsxElement {
        return <div className="min-h-svh bg-background text-foreground antialiased">
            {children}
        </div>;
    }
}

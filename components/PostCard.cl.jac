"""One post. The like button toggles a Likes-EDGE on the server.
Reply button expands an inline reply section with existing replies
and a composer for new replies.

Anyone can read a post. Liking and replying are writes, so they
require sign-in -- signed out, the heart/reply opens the sign-in
dialog instead of firing a request that would only come back 401.
"""

import from "@jac/runtime" { Link, jacIsLoggedIn }
sv import from ..services.social { PostView, ToggleLike, CreateReply, get_replies }
import from .AuthDialog { requireSignIn }
import from .ui.avatar { Avatar, AvatarFallback }
import from .ui.textarea { Textarea }
import from ..lib.utils { cn }
import from ..lib.format { timeAgo, initials }

def:pub HeartIcon(filled: bool = False) -> JsxElement {
    return <svg
        viewBox="0 0 24 24"
        className="size-4"
        fill={"currentColor" if filled else "none"}
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
    >
        <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
    </svg>;
}

def:pub ReplyIcon() -> JsxElement {
    return <svg
        viewBox="0 0 24 24"
        className="size-4"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
    >
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    </svg>;
}

def:pub PostCard(post: PostView, onChanged: Callable[[PostView], None]) -> JsxElement {
    has busy: bool = False;
    has show_replies: bool = False;
    has replies: list[PostView] = [];
    has replies_loaded: bool = False;
    has reply_text: str = "";
    has loading_replies: bool = False;
    has reply_busy: bool = False;

    async def handle_like -> None {
        if busy {
            return;
        }
        if not jacIsLoggedIn() {
            requireSignIn();
            return;
        }
        busy = True;
        updated: PostView | None = None;
        post_id = post.id;
        res = await root spawn ToggleLike(post_id=post_id);
        got = res.reports[0] if res and res.reports and len(res.reports) > 0 else None;
        updated = (got as PostView) if got is not None else None;
        busy = False;
        if updated is not None {
            onChanged(updated);
        }
    }

    async def fetch_replies -> None {
        loading_replies = True;
        post_id = post.id;
        server = await get_replies(post_id);
        server = server or [];
        # `get_replies` is a cached read. The client is meant to bust that cache
        # when a write walker (`CreateReply`) runs, but the effects manifest that
        # drives invalidation is empty in dev preview -- so right after posting, a
        # re-fetch can still return the pre-reply list. Merge instead of replace:
        # keep the server list, then re-add any reply we already hold that the
        # server hasn't echoed back yet (deduped by id). A just-sent reply never
        # blinks out on re-expand, and a fresh server list still wins.
        server_ids = [r.id for r in server];
        merged = server;
        for r in replies {
            if server_ids.indexOf(r.id) < 0 {
                merged = merged + [r];
            }
        }
        replies = merged;
        replies_loaded = True;
        loading_replies = False;
    }

    async def handle_toggle_replies -> None {
        if show_replies {
            show_replies = False;
            return;
        }
        show_replies = True;
        await fetch_replies();
    }

    async def handle_submit_reply -> None {
        if reply_busy {
            return;
        }
        if not jacIsLoggedIn() {
            requireSignIn();
            return;
        }
        trimmed = reply_text.strip();
        if len(trimmed) == 0 {
            return;
        }
        reply_busy = True;
        post_id = post.id;
        content = trimmed;
        res2 = await root spawn CreateReply(post_id=post_id, content=content);
        made = res2.reports[0] if res2 and res2.reports and len(res2.reports) > 0 else None;
        result = (made as PostView) if made is not None else None;
        reply_busy = False;
        if result is not None {
            replies = replies + [result];
            replies_loaded = True;
            reply_text = "";
        }
    }

    def handle_reply_input(e: ChangeEvent) -> None {
        reply_text = e.target.value;
    }

    # Once the thread has been loaded, the local `replies` list is the freshest
    # truth (it includes replies we just posted); the `post.reply_count` prop is
    # a render-time snapshot that never updates. Prefer the local count whenever
    # we have it, in both the expanded and collapsed states, so the number next
    # to the icon tracks a reply the moment it is sent.
    displayed_reply_count = len(replies) if replies_loaded else post.reply_count;

    return <article className="flex gap-3 border-b border-border pt-4 pb-4 pl-4 pr-4 transition-colors hover:bg-muted/30">
        <Link to={f"/u/{post.author_username}"} className="shrink-0">
            <Avatar>
                <AvatarFallback>{initials(post.author_display)}</AvatarFallback>
            </Avatar>
        </Link>

        <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-x-1.5 text-sm">
                <Link
                    to={f"/u/{post.author_username}"}
                    className="font-semibold text-foreground hover:underline"
                >{post.author_display}</Link>
                <span className="truncate text-muted-foreground">{"@" + post.author_username}</span>
                <span className="text-muted-foreground">{"·"}</span>
                <span className="shrink-0 text-muted-foreground">{timeAgo(post.created_at)}</span>
                {if post.is_mine {
                    <span className="ml-auto text-xs text-muted-foreground">you</span>
                }}
            </div>

            {if post.reply_to_username {
                <p className="mt-0.5 text-xs text-muted-foreground">
                    {"Replying to @" + post.reply_to_username}
                </p>
            }}

            <p className="mt-1 text-[0.9375rem] leading-relaxed whitespace-pre-wrap break-words text-foreground">
                {post.content}
            </p>

            <div className="mt-2 flex items-center gap-2">
                <button
                    type="button"
                    onClick={handle_like}
                    disabled={busy}
                    aria-pressed={post.liked_by_me}
                    aria-label={"Unlike" if post.liked_by_me else "Like"}
                    className={cn(
                        "group flex items-center gap-1.5 rounded-full pl-2 pr-2.5 pt-1 pb-1 text-xs transition-colors disabled:opacity-50",
                        "text-primary hover:bg-primary/10" if post.liked_by_me else "text-muted-foreground hover:bg-primary/10 hover:text-primary"
                    )}
                >
                    <HeartIcon filled={post.liked_by_me} />
                    <span className="tabular-nums">{str(post.like_count)}</span>
                </button>

                <button
                    type="button"
                    onClick={handle_toggle_replies}
                    aria-label="Replies"
                    className={cn(
                        "group flex items-center gap-1.5 rounded-full pl-2 pr-2.5 pt-1 pb-1 text-xs transition-colors",
                        "text-primary hover:bg-primary/10" if show_replies else "text-muted-foreground hover:bg-primary/10 hover:text-primary"
                    )}
                >
                    <ReplyIcon />
                    <span className="tabular-nums">{str(displayed_reply_count)}</span>
                </button>
            </div>

            {if show_replies {
                <div className="mt-3 border-t border-border pt-3 space-y-3">
                    {if loading_replies {
                        <p className="text-xs text-muted-foreground">Loading replies...</p>
                    }}

                    {if not loading_replies and len(replies) == 0 {
                        <p className="text-xs text-muted-foreground">No replies yet.</p>
                    }}

                    {for reply in replies {
                        <div key={reply.id} className="flex gap-2 text-sm">
                            <Link to={f"/u/{reply.author_username}"} className="shrink-0">
                                <Avatar className="size-6">
                                    <AvatarFallback className="text-[0.625rem]">{initials(reply.author_display)}</AvatarFallback>
                                </Avatar>
                            </Link>
                            <div className="min-w-0 flex-1">
                                <div className="flex flex-wrap items-center gap-x-1 text-xs">
                                    <Link
                                        to={f"/u/{reply.author_username}"}
                                        className="font-semibold text-foreground hover:underline"
                                    >{reply.author_display}</Link>
                                    <span className="text-muted-foreground">{"@" + reply.author_username}</span>
                                    <span className="text-muted-foreground">{"·"}</span>
                                    <span className="text-muted-foreground">{timeAgo(reply.created_at)}</span>
                                </div>
                                <p className="mt-0.5 text-[0.8125rem] leading-snug whitespace-pre-wrap break-words text-foreground">
                                    {reply.content}
                                </p>
                            </div>
                        </div>
                    }}

                    <div className="flex gap-2 items-start">
                        <Textarea
                            value={reply_text}
                            onChange={handle_reply_input}
                            placeholder="Write a reply..."
                            className="min-h-[2.5rem] resize-none text-sm flex-1"
                            rows={1}
                        />
                        <button
                            type="button"
                            onClick={handle_submit_reply}
                            disabled={reply_busy or len(reply_text.strip()) == 0}
                            className="shrink-0 rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
                        >{"Replying..." if reply_busy else "Reply"}</button>
                    </div>
                </div>
            }}
        </div>
    </article>;
}

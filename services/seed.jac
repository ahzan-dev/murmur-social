# ---------------------------------------------------------------------------
# THE SEED.
#
# Everything below is demo scaffolding, not the lesson. It builds a
# small fictional instance -- eight people, eighteen posts, an asymmetric
# follow graph, uneven likes -- so an anonymous visitor lands on a populated
# app instead of a sign-in form. Every row below becomes real nodes and real
# edges; there is no fixture layer and no mock. Delete f"_seed()" and the app
# is simply empty.
#
# The seed hangs off f"root.shared", NOT off f"root". That is the difference
# between "content the instance has" and "eight profiles only whoever happened
# to make the first request can see". See f"_build_seed".
#
# These people are invented, and NOBODY LOGS IN AS THEM. There are no demo
# credentials in this template: the seeded people are content to read and
# follow. To post, follow or like, you sign up and get your own profile on
# your own root.
# ---------------------------------------------------------------------------

import from datetime { datetime, timezone, timedelta }
import from threading { Lock }
import from services.social { Profile, Post, Posted, Follows, Likes, _ago }

obj _SeedPerson {
    has username: str,
        display_name: str,
        bio: str;
}

obj _SeedPost {
    has author: str,
        minutes: int,
        content: str,
        likes: list[str];
}

obj _SeedReply {
    has author: str,
        minutes: int,
        post_index: int,
        content: str;
}

glob _SEED_PEOPLE: list[_SeedPerson] = [
    _SeedPerson(
        username="maya",
        display_name="Maya Okonkwo",
        bio="Backend engineer. Distributed systems, and long walks to the kettle."
    ),
    _SeedPerson(
        username="devon",
        display_name="Devon Reyes",
        bio="Frontend by day, mechanical keyboards by night. Yes, it is too loud."
    ),
    _SeedPerson(
        username="priya",
        display_name="Priya Raman",
        bio="Infrastructure. I make the pagers quiet."
    ),
    _SeedPerson(
        username="jonas",
        display_name="Jonas Lindqvist",
        bio="Writing a database nobody asked for."
    ),
    _SeedPerson(
        username="tess",
        display_name="Tess Moreau",
        bio="Design systems. Recovering Figma maximalist."
    ),
    _SeedPerson(
        username="ren",
        display_name="Ren Takahashi",
        bio="ML engineer, which mostly means cleaning CSVs."
    ),
    _SeedPerson(
        username="cara",
        display_name="Cara Bianchi",
        bio="Security. Please rotate your keys."
    ),
    _SeedPerson(
        username="sam",
        display_name="Sam Whitfield",
        bio="Dev tools and CLIs. Ask me about my dotfiles. Please."
    )
];

# Deliberately NOT symmetric. maya follows jonas; jonas does not follow back.
# tess and cara follow maya; maya does not follow them. The asymmetry is what
# makes the follower counts on a profile page mean something -- and what makes
# YOUR feed change shape depending on which of them you follow after you sign
# up.
glob _SEED_FOLLOWS: dict[str, list[str]] = {
    "maya": ["devon", "priya", "jonas"],
    "devon": ["maya", "tess", "ren", "sam"],
    "priya": ["maya", "cara", "jonas"],
    "jonas": ["priya"],
    "tess": ["devon", "maya", "ren"],
    "ren": ["priya", "sam"],
    "cara": ["priya", "maya", "jonas", "tess"],
    "sam": ["devon"]
};

# f"minutes" ago -- 2 minutes to 5 days, so the relative timestamps in the feed
# read like a real timeline. f"likes" is uneven on purpose: counts of 0, 1, 2,
# 3, 4, 5, 6 and 7 all show up.
glob _SEED_POSTS: list[_SeedPost] = [
    _SeedPost(
        author="devon",
        minutes=2,
        content="the number of times i have written a useEffect and then deleted it in the same sitting is not a statistic i want published",
        likes=["maya", "tess", "sam", "ren", "priya", "cara", "jonas"]
    ),
    _SeedPost(
        author="priya",
        minutes=9,
        content="pager went off at 3am for a disk that was 81% full. eighty. one. percent. i have opinions about that threshold and i will be sharing them at standup.",
        likes=["maya", "jonas", "sam"]
    ),
    _SeedPost(
        author="maya",
        minutes=23,
        content="shipped the retry logic. it now fails in exactly the same way, just more politely.",
        likes=["devon"]
    ),
    _SeedPost(
        author="tess",
        minutes=41,
        content="spent two hours picking a border radius. the answer was 8px. the answer is always 8px.",
        likes=["devon", "ren"]
    ),
    _SeedPost(
        author="jonas",
        minutes=70,
        content="wrote my own B-tree this weekend. it works. it is slower than a dict. i have never been prouder. #buildinpublic",
        likes=["priya", "maya", "sam", "cara", "devon"]
    ),
    _SeedPost(
        author="ren",
        minutes=122,
        content="80% of this job is a CSV with a column called date_2_FINAL_v3. the model is the easy part.",
        likes=["devon", "sam"]
    ),
    _SeedPost(
        author="sam",
        minutes=210,
        content="new CLI rule: if your --help is longer than the screen, it is two tools. #devtools",
        likes=["devon", "ren", "maya"]
    ),
    _SeedPost(
        author="cara",
        minutes=300,
        content="found a prod API key in a screenshot in a thread from 2023. rotate your keys. rotate them today. #security",
        likes=["priya", "jonas", "maya", "tess", "devon", "sam"]
    ),
    _SeedPost(
        author="maya",
        minutes=420,
        content="hot take: most microservices problems are just a function that should have stayed in the same file",
        likes=["jonas", "priya", "cara", "devon"]
    ),
    _SeedPost(
        author="devon",
        minutes=660,
        content="css grid finally clicked for me today and i genuinely feel like i leveled up a character. #frontend",
        likes=["tess", "maya"]
    ),
    _SeedPost(
        author="priya",
        minutes=1140,
        content="deleted 4,000 lines of terraform. deploy time went down six minutes. best PR i have ever written and nobody will ever read it.",
        likes=["maya", "jonas", "sam", "cara", "ren"]
    ),
    _SeedPost(
        author="jonas",
        minutes=1620,
        content="modeling a feed as edges instead of a join table means the query is literally one hop. still adjusting to not writing SQL. #graphs",
        likes=["maya", "priya"]
    ),
    _SeedPost(
        author="tess",
        minutes=1980,
        content="if your design system has 14 shades of gray, you do not have a design system, you have a mood",
        likes=["devon", "cara", "maya"]
    ),
    _SeedPost(
        author="ren",
        minutes=2880,
        content="the meeting could have been a message. the message could have been a link. the link could have been nothing.",
        likes=[]
    ),
    _SeedPost(
        author="maya",
        minutes=3360,
        content="the graph is the schema. took me a week to stop reaching for a follows table. #graphs",
        likes=["jonas"]
    ),
    _SeedPost(
        author="sam",
        minutes=4560,
        content="rewrote my dotfiles from scratch. productivity: minus one week. joy: immeasurable.",
        likes=["devon", "ren", "tess", "maya"]
    ),
    _SeedPost(
        author="cara",
        minutes=5760,
        content="we will add auth later is the most expensive sentence in software",
        likes=["priya", "sam"]
    ),
    _SeedPost(
        author="devon",
        minutes=8100,
        content="i named a variable data2 today and i want you all to know i am not proud",
        likes=[]
    )
];

# Replies reference posts by their index in _SEED_POSTS above.
# Timestamps sit between the parent post and the present so they read naturally.
glob _SEED_REPLIES: list[_SeedReply] = [
    # Post 0 (devon, useEffect) -- 3 replies
    _SeedReply(
        author="maya",
        minutes=1,
        post_index=0,
        content="the real question is how many of those useEffects you replaced with a single ref"
    ),
    _SeedReply(
        author="sam",
        minutes=1,
        post_index=0,
        content="i feel seen and i do not like it"
    ),
    _SeedReply(
        author="tess",
        minutes=1,
        post_index=0,
        content="this is a personal attack on my entire week"
    ),
    # Post 1 (priya, pager at 3am) -- 2 replies
    _SeedReply(
        author="cara",
        minutes=7,
        post_index=1,
        content="81% is generous. ours fires at 75. i have lost the will to argue about it."
    ),
    _SeedReply(
        author="jonas",
        minutes=5,
        post_index=1,
        content="the threshold is always wrong. the only question is which direction."
    ),
    # Post 2 (maya, retry logic) -- 2 replies
    _SeedReply(
        author="devon",
        minutes=20,
        post_index=2,
        content="at least it logs the failure now. progress."
    ),
    _SeedReply(
        author="jonas",
        minutes=18,
        post_index=2,
        content="polite failure is still failure but it does feel better somehow"
    ),
    # Post 3 (tess, border radius) -- 1 reply
    _SeedReply(
        author="cara",
        minutes=35,
        post_index=3,
        content="8px is the answer to every design question. font size? 8px. margin? 8px. salary? 8px."
    ),
    # Post 4 (jonas, B-tree) -- 2 replies
    _SeedReply(
        author="maya",
        minutes=60,
        post_index=4,
        content="slower than a dict but you understand every byte of it. that is the whole point."
    ),
    _SeedReply(
        author="priya",
        minutes=55,
        post_index=4,
        content="next step: benchmark it against sqlite and pretend the numbers are close"
    ),
    # Post 5 (ren, CSV) -- 2 replies
    _SeedReply(
        author="maya",
        minutes=110,
        post_index=5,
        content="date_2_FINAL_v3 is a cry for help and we all just scroll past it"
    ),
    _SeedReply(
        author="sam",
        minutes=100,
        post_index=5,
        content="i once got a CSV where the date column was called misc_field_7. i still think about it."
    ),
    # Post 6 (sam, CLI rule) -- 1 reply
    _SeedReply(
        author="devon",
        minutes=200,
        post_index=6,
        content="counterpoint: if your --help fits on one screen nobody reads it either"
    ),
    # Post 7 (cara, API key in screenshot) -- 2 replies
    _SeedReply(
        author="sam",
        minutes=280,
        post_index=7,
        content="i once found a prod key in a conference slide deck. on youtube. with 4k views."
    ),
    _SeedReply(
        author="devon",
        minutes=270,
        post_index=7,
        content="rotating keys is the flossing of engineering. everyone agrees, nobody does it."
    ),
    # Post 8 (maya, microservices hot take) -- 1 reply
    _SeedReply(
        author="jonas",
        minutes=400,
        post_index=8,
        content="this is the post i will link in every architecture review from now on"
    ),
    # Post 9 (devon, css grid) -- 1 reply
    _SeedReply(
        author="tess",
        minutes=640,
        post_index=9,
        content="wait until you discover subgrid. it is the prestige."
    ),
    # Post 10 (priya, terraform) -- 2 replies
    _SeedReply(
        author="cara",
        minutes=1100,
        post_index=10,
        content="the best PRs are the ones where the diff is entirely red"
    ),
    _SeedReply(
        author="sam",
        minutes=1080,
        post_index=10,
        content="4000 lines of terraform is 4000 lines of someone else's problem now"
    ),
    # Post 12 (tess, 14 shades of gray) -- 1 reply
    _SeedReply(
        author="devon",
        minutes=1900,
        post_index=12,
        content="we had 17. i counted. nobody else noticed when i deleted three."
    ),
    # Post 13 (ren, meeting) -- 1 reply
    _SeedReply(
        author="priya",
        minutes=2800,
        post_index=13,
        content="the link could have been a 404 and nobody would have noticed"
    ),
    # Post 15 (sam, dotfiles) -- 1 reply
    _SeedReply(
        author="ren",
        minutes=4500,
        post_index=15,
        content="the joy is in the yak shave. the productivity was never the point."
    ),
    # Post 16 (cara, auth later) -- 2 replies
    _SeedReply(
        author="maya",
        minutes=5700,
        post_index=16,
        content="right next to 'we will write tests later' and 'we will document it later'"
    ),
    _SeedReply(
        author="jonas",
        minutes=5680,
        post_index=16,
        content="later is a place where finished software goes to die"
    )
];

glob _seeded: bool = False;
glob _seed_lock: Lock = Lock();

"""Build the demo instance once. Idempotent twice over: an in-process flag for
the common case, and a graph check so a restart onto a root that already has
profiles does not duplicate anyone. The lock is because the first page load
fires several endpoints at once and they would otherwise race.

Called at the top of every endpoint, and by the walker."""
def _seed -> None {
    if _seeded {
        return;
    }
    with _seed_lock {
        if _seeded {
            return;
        }
        if len([root.shared -->[?:Profile]]) == 0 {
            _build_seed();
        }
        _seeded = True;
    }
}

"""The seed lives on f"root.shared" -- the deployment's public commons -- and
NOT on f"root".

f"root" is whoever happened to make the first request. Hang the seed there and
it becomes one user's private data: every OTHER visitor, anonymous or signed
up, opens an empty app. f"root.shared" is reachable from every request context,
so the seed is the instance's content rather than somebody's.

f"grant(node, level=ConnectPerm)" on every Profile and every Post is what makes
that content legible. A node's owner is still whichever request triggered the
seed, so without the grant every other caller reads NO_ACCESS and every feed,
every profile page and every count silently comes back empty -- no error, no
warning, just nothing. ConnectPerm is the least that works: strangers attach
Follows- and Likes-edges to these nodes, they never write their fields.

The edges between seeded nodes need no grant of their own -- a forward
traversal checks read access on the TARGET NODE, which is granted."""
def _build_seed -> None {
    by_name: dict[str, Profile] = {};

    for person in _SEED_PEOPLE {
        fresh_profile = root.shared ++> Profile(
            username=person.username,
            display_name=person.display_name,
            bio=person.bio,
            created_at=_ago(60 * 24 * 400)
        );
        grant(fresh_profile, level=ConnectPerm);
        by_name[person.username] = fresh_profile;
    }

    for (name, targets) in _SEED_FOLLOWS.items() {
        follower = by_name[name];
        for handle in targets {
            followee = by_name[handle];
            follower +>:Follows(since=_ago(60 * 24 * 90)):+> followee;
        }
    }

    posts_by_index: list[Post] = [];
    for spec in _SEED_POSTS {
        author = by_name[spec.author];
        fresh_post = Post(
            content=spec.content,
            author_username=spec.author,
            created_at=_ago(spec.minutes)
        );
        author +>:Posted:+> fresh_post;
        grant(fresh_post, level=ConnectPerm);

        for handle in spec.likes {
            fan = by_name[handle];
            fan +>:Likes:+> fresh_post;
        }
        posts_by_index.append(fresh_post);
    }

    for reply_spec in _SEED_REPLIES {
        replier = by_name[reply_spec.author];
        parent = posts_by_index[reply_spec.post_index];
        reply_post = Post(
            content=reply_spec.content,
            author_username=reply_spec.author,
            created_at=_ago(reply_spec.minutes),
            reply_to=parent.author_username,
            reply_to_id=jid(parent)
        );
        replier +>:Posted:+> reply_post;
        grant(reply_post, level=ConnectPerm);
    }
}

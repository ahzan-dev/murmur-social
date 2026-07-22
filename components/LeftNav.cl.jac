"""The left rail.

Three widths, one component:

    < 768px    hidden entirely -- MobileBar takes over
    >= 768px   72px icon rail
    >= 1100px  275px, icons with labels and a full Post button

The breakpoints are Tailwind's own, plus one arbitrary `min-[1100px]:` stop.
Inside a preview iframe `window.innerWidth` IS the panel width, so they behave
exactly as they would in a browser window.
"""

import from "@jac/runtime" { Link, jacIsLoggedIn, useLocation, useNavigate }
sv import from ..services.social { ProfileView, get_me }
import from .AccountMenu { AccountMenu }
import from .AuthDialog { requireSignIn }
import from .ui.button { Button }
import from ..lib.utils { cn }

def:pub HomeIcon() -> JsxElement {
    return <svg viewBox="0 0 24 24" className="size-6 shrink-0" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M3 10.5 12 3l9 7.5" />
        <path d="M5 9.5V20a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V9.5" />
    </svg>;
}

def:pub ExploreIcon() -> JsxElement {
    return <svg viewBox="0 0 24 24" className="size-6 shrink-0" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <circle cx="11" cy="11" r="7" />
        <path d="m20 20-3.5-3.5" />
    </svg>;
}

def:pub ProfileIcon() -> JsxElement {
    return <svg viewBox="0 0 24 24" className="size-6 shrink-0" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <circle cx="12" cy="8" r="4" />
        <path d="M4 21v-1a6 6 0 0 1 6-6h4a6 6 0 0 1 6 6v1" />
    </svg>;
}

def:pub QuillIcon() -> JsxElement {
    return <svg viewBox="0 0 24 24" className="size-5 shrink-0" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M17 3a3 3 0 0 1 4 4L8 20l-5 1 1-5Z" />
        <path d="m14 6 4 4" />
    </svg>;
}

def:pub NavItem(href: str, label: str, icon: any, active: bool) -> JsxElement {
    return <Link
        to={href}
        className={cn(
            "flex items-center gap-4 rounded-full pt-3 pb-3 transition-colors hover:bg-muted",
            "justify-center min-[1100px]:justify-start min-[1100px]:pl-4 min-[1100px]:pr-6",
            "text-foreground" if active else "text-muted-foreground hover:text-foreground"
        )}
    >
        {icon}
        <span className={cn(
            "hidden text-xl min-[1100px]:inline",
            "font-bold" if active else "font-normal"
        )}>{label}</span>
    </Link>;
}

def:pub LeftNav() -> JsxElement {
    has me: ProfileView | None = None;

    location = useLocation();
    nav = useNavigate();
    path = location.pathname;

    # Guard the effect body, not just the render: mount effects fire whatever
    # the component returns, so an unguarded `get_me()` 401s for every
    # anonymous visitor.
    async can with entry {
        if jacIsLoggedIn() {
            me = await get_me();
        }
    }

    def handle_compose(e: MouseEvent) {
        if not jacIsLoggedIn() {
            requireSignIn();
            return;
        }
        nav("/");
        # getElementById is typed `object` here -- cast to reach .focus().
        box: any = document.getElementById("composer");
        if box {
            box.focus();
        }
    }

    # Signed out there is no "your profile" to link to, so the rail sends you
    # to the people you could be reading instead.
    my_href = f"/u/{me.username}" if me is not None else "/explore";

    return <aside className="sticky top-0 hidden h-svh w-[72px] shrink-0 flex-col justify-between pt-2 pb-4 pl-2 pr-2 md:flex min-[1100px]:w-[275px] min-[1100px]:pl-3 min-[1100px]:pr-6">
        <div className="flex flex-col gap-1">
            <Link
                to="/"
                className="flex items-center justify-center rounded-full pt-3 pb-3 text-xl font-bold tracking-tight min-[1100px]:justify-start min-[1100px]:pl-4"
            >
                <span className="hidden min-[1100px]:inline">Murmur</span>
                <span className="text-primary min-[1100px]:hidden">x</span>
            </Link>

            <NavItem href="/" label="Home" icon={<HomeIcon />} active={path == "/"} />
            <NavItem href="/explore" label="Explore" icon={<ExploreIcon />} active={path == "/explore"} />
            {if me is not None {
                <NavItem href={my_href} label="Profile" icon={<ProfileIcon />} active={path.startsWith("/u/")} />
            }}

            <Button
                onClick={handle_compose}
                className="mt-3 h-12 w-12 self-center rounded-full min-[1100px]:h-12 min-[1100px]:w-full min-[1100px]:self-stretch"
            >
                <span className="hidden text-base font-bold min-[1100px]:inline">Post</span>
                <span className="min-[1100px]:hidden"><QuillIcon /></span>
            </Button>
        </div>

        <AccountMenu />
    </aside>;
}

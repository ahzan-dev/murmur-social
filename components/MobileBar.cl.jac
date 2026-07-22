"""The < 768px nav. A 56px top bar instead of the rail -- at a 200px viewport
a sidebar of any width is a tax the feed cannot afford."""

import from "@jac/runtime" { Link, useLocation }
import from .LeftNav { HomeIcon, ExploreIcon }
import from .AccountMenu { AccountMenu }
import from ..lib.utils { cn }

def:pub BarLink(href: str, label: str, icon: any, active: bool) -> JsxElement {
    return <Link
        to={href}
        aria-label={label}
        className={cn(
            "flex size-9 items-center justify-center rounded-full transition-colors hover:bg-muted",
            "text-foreground" if active else "text-muted-foreground"
        )}
    >{icon}</Link>;
}

def:pub MobileBar() -> JsxElement {
    location = useLocation();
    path = location.pathname;

    return <header className="sticky top-0 z-50 flex h-14 items-center justify-between gap-2 border-b border-border bg-background/80 pl-3 pr-3 backdrop-blur md:hidden">
        <Link to="/" className="text-lg font-bold tracking-tight">
            Murmur
        </Link>
        <div className="flex items-center gap-1">
            <BarLink href="/" label="Home" icon={<HomeIcon />} active={path == "/"} />
            <BarLink href="/explore" label="Explore" icon={<ExploreIcon />} active={path == "/explore"} />
            <AccountMenu compact={True} />
        </div>
    </header>;
}

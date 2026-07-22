"""Small display helpers shared by the post and profile views."""

def:pub timeAgo(iso: str) -> str {
    if not iso {
        return "";
    }
    then_ = new(Date, iso);                                  # jac:ignore[W2001]
    secs = (new(Date).getTime() - then_.getTime()) / 1000;   # jac:ignore[W2001]
    if secs < 60 {
        return "now";
    }
    if secs < 3600 {
        return f"{int(secs / 60)}m";
    }
    if secs < 86400 {
        return f"{int(secs / 3600)}h";
    }
    if secs < 604800 {
        return f"{int(secs / 86400)}d";
    }
    return then_.toLocaleDateString();
}

"""Avatar text. There are no image URLs in this app on purpose -- initials
render offline, never 404, and never reach for someone else's CDN."""
def:pub initials(name: str) -> str {
    if not name {
        return "?";
    }
    parts = [p for p in name.split(" ") if len(p) > 0];
    if len(parts) == 0 {
        return "?";
    }
    if len(parts) == 1 {
        return parts[0][0:1].upper();
    }
    return (parts[0][0:1] + parts[1][0:1]).upper();
}

"""/u/:username -- a profile page."""

cl import from "@jac/runtime" { useParams }
cl import from ...components.UserProfile { UserProfile }

cl {
    def:pub page() -> JsxElement {
        params = useParams();
        # useParams() returns a plain JS object -- subscript access, and a
        # truthy check (a missing param is `undefined`, which `is not None` misses).
        username = params["username"];
        if not username {
            return <p className="pt-12 pb-12 text-center text-sm text-muted-foreground">Not found.</p>;
        }
        return <UserProfile username={username} />;
    }
}

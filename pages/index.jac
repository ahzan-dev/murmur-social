"""/ -- the home feed.

No guard, on purpose. Signed out you get the public timeline; signed in, the
same component swaps to the `load_feed` walker. The gate is on writing, not on
reading -- see components/HomeFeed.cl.jac."""

cl import from ..components.HomeFeed { HomeFeed }

cl {
    def:pub page() -> JsxElement {
        return <HomeFeed />;
    }
}

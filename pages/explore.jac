"""/explore"""

cl import from ..components.ExplorePeople { ExplorePeople }

cl {
    def:pub page() -> JsxElement {
        return <ExplorePeople />;
    }
}

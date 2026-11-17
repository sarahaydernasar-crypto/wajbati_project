"""Initial ingredients for the built-in demo menu; owners can edit them."""

DEFAULT_INGREDIENTS = {
    "شاي مهيل": (["شاي", "ماء", "هيل", "سكر"], ["سكر"]),
    "شاي": (["شاي", "ماء", "سكر"], ["سكر"]),
    "صمون كباب لحم": (["خبز", "لحم", "بصل", "طماطم"], ["بصل", "طماطم"]),
    "ببسي / عصير": ([], []),
}


def initial_ingredients(name: str) -> dict:
    ingredients, removable = DEFAULT_INGREDIENTS.get(name, ([], []))
    return {"ingredients": list(ingredients), "removable_ingredients": list(removable)}

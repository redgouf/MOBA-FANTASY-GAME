"""How the player holds and swings each weapon family.

OSRS sends a weapon's stance (ready / walk / run) and attack animations from
the server, so the cache can't tell us which item uses which. This table
covers the families the game uses; the ids are the client's own animations
(names in comments are its internal names).
"""

FAMILIES = {
    "unarmed": {"stand": 808, "walk": 819, "run": 824, "stab": 422, "slash": 422, "crush": 423, "block": 424},
    "sword": {"stand": 808, "walk": 819, "run": 824, "stab": 386, "slash": 390, "crush": 390, "block": 388},
    "dagger": {"stand": 808, "walk": 819, "run": 824, "stab": 376, "slash": 377, "crush": 377, "block": 378},
    "whip": {"stand": 808, "walk": 1660, "run": 1661, "stab": 1658, "slash": 1658, "crush": 1658, "block": 1659},
    "axe": {"stand": 808, "walk": 819, "run": 824, "stab": 395, "slash": 393, "crush": 396, "block": 397},
    "blunt": {"stand": 808, "walk": 819, "run": 824, "stab": 400, "slash": 401, "crush": 401, "block": 403},
    "staff": {"stand": 813, "walk": 1146, "run": 1210, "stab": 414, "slash": 414, "crush": 414, "block": 415},
    "bow": {"stand": 808, "walk": 819, "run": 824, "stab": 426, "slash": 426, "crush": 426, "block": 424},
    "crossbow": {"stand": 4591, "walk": 4226, "run": 4228, "stab": 4230, "slash": 4230, "crush": 4230, "block": 424},
    "godsword": {"stand": 7053, "walk": 7052, "run": 7043, "stab": 7045, "slash": 7045, "crush": 7054, "block": 7056},
    "maul": {"stand": 1662, "walk": 1663, "run": 1664, "stab": 1665, "slash": 1665, "crush": 1665, "block": 1666},
    "dharok": {"stand": 2065, "walk": 2064, "run": 11466, "stab": 2066, "slash": 2066, "crush": 2067, "block": 397},
    "claws": {"stand": 808, "walk": 819, "run": 824, "stab": 1067, "slash": 1067, "crush": 1067, "block": 424},
    "scythe": {"stand": 847, "walk": 819, "run": 824, "stab": 438, "slash": 437, "crush": 440, "block": 435},
    "spear": {"stand": 808, "walk": 819, "run": 824, "stab": 381, "slash": 380, "crush": 382, "block": 383},
    "blowpipe": {"stand": 808, "walk": 819, "run": 824, "stab": 5061, "slash": 5061, "crush": 5061, "block": 424},
    "bulwark": {"stand": 7508, "walk": 7510, "run": 7509, "stab": 7507, "slash": 7507, "crush": 7507, "block": 7512},
    "twohand": {"stand": 825, "walk": 826, "run": 824, "stab": 405, "slash": 407, "crush": 406, "block": 410},
}

# Item id -> family. Unlisted weapons are guessed from their name.
ITEMS = {
    4151: "whip", 12006: "whip", 1249: "spear", 4718: "dharok", 861: "bow", 12926: "blowpipe", 20997: "bow", 21015: "bulwark", 9084: "staff", 4587: "sword", 1333: "sword", 5698: "dagger",
    1215: "dagger", 4153: "maul", 13652: "claws", 11802: "godsword", 11804: "godsword", 11806: "godsword",
    11808: "godsword", 4675: "staff", 11791: "staff", 12904: "staff", 21902: "crossbow", 11785: "crossbow",
    6528: "maul", 13576: "blunt", 1377: "axe", 6739: "axe", 22325: "scythe", 4755: "blunt", 4747: "blunt",
    4726: "spear", 4734: "crossbow", 4710: "staff",
}

NAME_HINTS = [
    ("godsword", "godsword"), ("whip", "whip"), ("crossbow", "crossbow"), ("ballista", "crossbow"),
    ("shortbow", "bow"), ("longbow", "bow"), ("bow", "bow"), ("blowpipe", "blowpipe"), ("bulwark", "bulwark"), ("staff", "staff"),
    ("wand", "staff"), ("sceptre", "staff"), ("dagger", "dagger"), ("claws", "claws"), ("maul", "maul"),
    ("scimitar", "sword"), ("sword", "sword"), ("rapier", "sword"), ("2h", "twohand"), ("battleaxe", "axe"),
    ("axe", "axe"), ("hammer", "blunt"), ("mace", "blunt"), ("flail", "blunt"), ("spear", "spear"),
    ("hasta", "spear"), ("halberd", "spear"), ("scythe", "scythe"),
]


def family_of(item_id, name):
    if item_id in ITEMS:
        return ITEMS[item_id]
    n = (name or "").lower()
    for hint, fam in NAME_HINTS:
        if hint in n:
            return fam
    return "sword"


def anims_for(item_id, name):
    return dict(FAMILIES[family_of(item_id, name)])

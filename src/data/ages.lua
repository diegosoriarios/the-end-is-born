-- Ages of the cult. Ordered tiers; each one owns a slice of the customs as
-- its objectives (checklist entries tagged with `age`) and costs resources +
-- a servant sacrifice to leave (paid at the village heart). The last age is
-- the finale. `cost`/`sacrifice` = the price to advance FROM this age.
return {
  { id = "whispers", name = "Age of Whispers", desc = "A cult whispers in the dark.",
    cost = { wood = 60, stone = 30 }, sacrifice = 1 },
  { id = "blood", name = "Age of Blood", desc = "Blood feeds the covenant.",
    cost = { wood = 120, stone = 80 }, sacrifice = 1 },
  { id = "bones", name = "Age of Bones", desc = "The dead join the flock.",
    cost = { wood = 200, stone = 140 }, sacrifice = 1 },
  { id = "chosen", name = "Age of the Chosen", desc = "The vessel is prepared.",
    cost = { wood = 280, stone = 200 }, sacrifice = 1 },
  { id = "end", name = "Age of the End", desc = "Bring forth the Antichrist." },
}

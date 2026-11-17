local out = {}
local function list(obj, tag)
  if obj == nil then out[tag] = "nil" return end
  local names = {}
  local c = obj:get_class()
  local depth = 0
  while c ~= nil and depth < 6 do
    local cname = c:get_fname():to_string()
    local f = c:get_children()
    while f ~= nil do
      local n = f:get_fname():to_string()
      local l = n:lower()
      if l:find("reload") or l:find("ammo") or l:find("fire") or l:find("aim") or l:find("bullet") or l:find("clip") or l:find("shoot") or l:find("heal") then
        names[#names + 1] = cname .. "." .. n
      end
      f = f:get_next()
    end
    if cname == "Actor" or cname == "ActorComponent" or cname == "Pawn" then break end
    c = c:get_super_struct()
    depth = depth + 1
  end
  out[tag] = names
end
local wc = S.pawn.WeaponController
list(wc, "weapon_controller")
list(S.weapon_actor, "weapon")
list(S.pawn, "pawn")
return out

--[[
  uemath.lua - Unreal Engine math for UEVR Lua scripts (verified against UE source + tests)
  Conventions: UE world (X forward, Y right, Z up), rotators in degrees (Pitch, Yaw, Roll),
  quaternions as {x,y,z,w}, Hamilton product, qmul(a,b) = apply b then a (same as FQuat * FQuat).
  quat_from_rot / rot_from_quat are ports of FRotator::Quaternion / FQuat::Rotator.
  Roll +90 maps Y -> -Z (UE FRotationMatrix), yaw +90 maps X -> Y, pitch +90 maps X -> Z.

  Usage: paste into your script (UEVR has no require for data files) or load with
  load(fs.read("uemath.lua"))() from a loader.
]]

local DEG = 180.0 / math.pi
local RAD = math.pi / 180.0

local function quat_from_rot(pitch, yaw, roll)
    local hp, hy, hr = pitch * RAD * 0.5, yaw * RAD * 0.5, roll * RAD * 0.5
    local SP, CP = math.sin(hp), math.cos(hp)
    local SY, CY = math.sin(hy), math.cos(hy)
    local SR, CR = math.sin(hr), math.cos(hr)
    return {
        x =  CR * SP * SY - SR * CP * CY,
        y = -CR * SP * CY - SR * CP * SY,
        z =  CR * CP * SY - SR * SP * CY,
        w =  CR * CP * CY + SR * SP * SY,
    }
end

local function normalize_axis(a)
    a = a % 360.0
    if a > 180.0 then a = a - 360.0 end
    return a
end

local function rot_from_quat(q)
    local X, Y, Z, W = q.x, q.y, q.z, q.w
    local singularity = Z * X - W * Y
    local yawY = 2.0 * (W * Z + X * Y)
    local yawX = 1.0 - 2.0 * (Y * Y + Z * Z)
    local THRESH = 0.4999995
    local pitch, yaw, roll
    if singularity < -THRESH then
        pitch = -90.0
        yaw = math.atan(yawY, yawX) * DEG
        roll = normalize_axis(-yaw - (2.0 * math.atan(X, W) * DEG))
    elseif singularity > THRESH then
        pitch = 90.0
        yaw = math.atan(yawY, yawX) * DEG
        roll = normalize_axis(yaw - (2.0 * math.atan(X, W) * DEG))
    else
        local s = 2.0 * singularity
        if s > 1.0 then s = 1.0 elseif s < -1.0 then s = -1.0 end
        pitch = math.asin(s) * DEG
        yaw = math.atan(yawY, yawX) * DEG
        roll = math.atan(-2.0 * (W * X + Y * Z), 1.0 - 2.0 * (X * X + Y * Y)) * DEG
    end
    return pitch, yaw, roll
end

local function qmul(a, b)
    return {
        w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    }
end

local function qinv(q)
    local n = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
    if n < 1e-12 then return { x = 0, y = 0, z = 0, w = 1 } end
    return { x = -q.x / n, y = -q.y / n, z = -q.z / n, w = q.w / n }
end

local function qnorm(q)
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n < 1e-12 then return { x = 0, y = 0, z = 0, w = 1 } end
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end

local function qrot(q, v)
    local tx = 2.0 * (q.y * v.z - q.z * v.y)
    local ty = 2.0 * (q.z * v.x - q.x * v.z)
    local tz = 2.0 * (q.x * v.y - q.y * v.x)
    return {
        x = v.x + q.w * tx + (q.y * tz - q.z * ty),
        y = v.y + q.w * ty + (q.z * tx - q.x * tz),
        z = v.z + q.w * tz + (q.x * ty - q.y * tx),
    }
end

local function vadd(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end
local function vsub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
local function vscale(a, s) return { x = a.x * s, y = a.y * s, z = a.z * s } end
local function vdot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function vcross(a, b) return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x } end
local function vlen(a) return math.sqrt(vdot(a, a)) end
local function vnorm(a)
    local l = vlen(a)
    if l < 1e-9 then return { x = 1, y = 0, z = 0 } end
    return vscale(a, 1.0 / l)
end
local function vlerp(a, b, t) return vadd(a, vscale(vsub(b, a), t)) end

local function qangle_deg(a, b)
    local d = math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w)
    if d > 1.0 then d = 1.0 end
    return 2.0 * math.acos(d) * DEG
end

local function qnlerp(a, b, t)
    local d = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
    local s = (d < 0) and -1.0 or 1.0
    return qnorm({
        x = a.x + (s * b.x - a.x) * t, y = a.y + (s * b.y - a.y) * t,
        z = a.z + (s * b.z - a.z) * t, w = a.w + (s * b.w - a.w) * t,
    })
end

-- rotation that takes direction u to direction v (UE FQuat::FindBetweenNormals)
local function qbetween(u, v)
    u, v = vnorm(u), vnorm(v)
    local w = 1.0 + vdot(u, v)
    if w < 1e-6 then
        local axis = (math.abs(u.x) > math.abs(u.z)) and { x = -u.y, y = u.x, z = 0 } or { x = 0, y = -u.z, z = u.y }
        axis = vnorm(axis)
        return { x = axis.x, y = axis.y, z = axis.z, w = 0 }
    end
    local c = vcross(u, v)
    return qnorm({ x = c.x, y = c.y, z = c.z, w = w })
end

local function qyaw(deg) return quat_from_rot(0, deg, 0) end

-- rotation matrix (rows) -> quaternion; q rotates v as R*v
local function quat_from_rows(r0, r1, r2)
    local m00, m01, m02 = r0.x, r0.y, r0.z
    local m10, m11, m12 = r1.x, r1.y, r1.z
    local m20, m21, m22 = r2.x, r2.y, r2.z
    local tr = m00 + m11 + m22
    local x, y, z, w
    if tr > 0 then
        local s = math.sqrt(tr + 1.0) * 2.0
        w = 0.25 * s; x = (m21 - m12) / s; y = (m02 - m20) / s; z = (m10 - m01) / s
    elseif m00 > m11 and m00 > m22 then
        local s = math.sqrt(1.0 + m00 - m11 - m22) * 2.0
        w = (m21 - m12) / s; x = 0.25 * s; y = (m01 + m10) / s; z = (m02 + m20) / s
    elseif m11 > m22 then
        local s = math.sqrt(1.0 + m11 - m00 - m22) * 2.0
        w = (m02 - m20) / s; x = (m01 + m10) / s; y = 0.25 * s; z = (m12 + m21) / s
    else
        local s = math.sqrt(1.0 + m22 - m00 - m11) * 2.0
        w = (m10 - m01) / s; x = (m02 + m20) / s; y = (m12 + m21) / s; z = 0.25 * s
    end
    return qnorm({ x = x, y = y, z = z, w = w })
end

-- hand frame from finger bones: forward = wrist -> middle knuckle, up = pinky -> index (thumb side).
-- returns q such that (wrist world rot) = (controller rot) * q  puts the hand forward along the
-- controller's forward axis with the thumb up, i.e. a natural grip.
local function hand_grip_q(fwd_local, side_local)
    local f = vnorm(fwd_local)
    local s = vsub(side_local, vscale(f, vdot(side_local, f)))
    s = vnorm(s)
    local y = vcross(s, f)
    return quat_from_rows(f, y, s)
end

-- Two-bone IK solve (pure math, world space)
-- returns new elbow and wrist positions
---------------------------------------------------------------------------
local function solve_two_bone(S, E, W, T, hint_dir)
    local a = vlen(vsub(E, S))
    local b = vlen(vsub(W, E))
    local to_t = vsub(T, S)
    local d = vlen(to_t)
    local dir = vnorm(to_t)
    local max_d = (a + b) * 0.999
    local min_d = math.abs(a - b) + 0.01
    if d > max_d then d = max_d elseif d < min_d then d = min_d end
    local cos_a = (a * a + d * d - b * b) / (2.0 * a * d)
    if cos_a > 1.0 then cos_a = 1.0 elseif cos_a < -1.0 then cos_a = -1.0 end
    local sin_a = math.sqrt(1.0 - cos_a * cos_a)
    local perp = vsub(hint_dir, vscale(dir, vdot(hint_dir, dir)))
    if vlen(perp) < 1e-4 then perp = { x = 0, y = 0, z = -1 } end
    perp = vnorm(perp)
    local E2 = vadd(S, vadd(vscale(dir, a * cos_a), vscale(perp, a * sin_a)))
    local W2 = vadd(S, vscale(dir, d))
    return E2, W2
end

-- swing/twist + frames
local function qtwist(q, a)
    local d = q.x * a.x + q.y * a.y + q.z * a.z
    local t = { x = a.x * d, y = a.y * d, z = a.z * d, w = q.w }
    local n = math.sqrt(t.x * t.x + t.y * t.y + t.z * t.z + t.w * t.w)
    if n < 1e-9 then return { x = 0, y = 0, z = 0, w = 1 } end
    t = { x = t.x / n, y = t.y / n, z = t.z / n, w = t.w / n }
    if t.w < 0 then t = { x = -t.x, y = -t.y, z = -t.z, w = -t.w } end
    return t
end

local function qfrac(q, f)
    if q.w < 0 then q = { x = -q.x, y = -q.y, z = -q.z, w = -q.w } end
    local s = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z)
    if s < 1e-9 then return { x = 0, y = 0, z = 0, w = 1 } end
    local ang = 2.0 * math.atan(s, q.w)
    local h = ang * f * 0.5
    local k = math.sin(h) / s
    return { x = q.x * k, y = q.y * k, z = q.z * k, w = math.cos(h) }
end

local function frame_q(a_l, n_l, a_w, n_w)
    local la = vnorm(a_l)
    local ln = vnorm(vsub(n_l, vscale(la, vdot(n_l, la))))
    local lc = vcross(la, ln)
    local wa = vnorm(a_w)
    local wn = vnorm(vsub(n_w, vscale(wa, vdot(n_w, wa))))
    local wc = vcross(wa, wn)
    -- R = Wa*La^T + Wn*Ln^T + Wc*Lc^T
    local function row(i)
        local function g(v) return (i == 1 and v.x) or (i == 2 and v.y) or v.z end
        return {
            x = g(wa) * la.x + g(wn) * ln.x + g(wc) * lc.x,
            y = g(wa) * la.y + g(wn) * ln.y + g(wc) * lc.y,
            z = g(wa) * la.z + g(wn) * ln.z + g(wc) * lc.z,
        }
    end
    return quat_from_rows(row(1), row(2), row(3))
end

return {
    DEG = DEG, RAD = RAD,
    quat_from_rot = quat_from_rot, rot_from_quat = rot_from_quat, normalize_axis = normalize_axis,
    qmul = qmul, qinv = qinv, qnorm = qnorm, qrot = qrot, qangle_deg = qangle_deg, qnlerp = qnlerp,
    qbetween = qbetween, qyaw = qyaw, quat_from_rows = quat_from_rows, hand_grip_q = hand_grip_q,
    qtwist = qtwist, qfrac = qfrac, frame_q = frame_q, solve_two_bone = solve_two_bone,
    vadd = vadd, vsub = vsub, vscale = vscale, vdot = vdot, vcross = vcross, vlen = vlen, vnorm = vnorm, vlerp = vlerp,
}

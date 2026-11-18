# Scorn — UEVR 6DOF profile with full body and IK arms

[Русский](#русский) · [English](#english)

---

## Русский

Профиль [UEVR](https://uevr.io) для **Scorn** (Steam, UE 4.27). С ним игра становится полноценной VR-игрой с 6DOF:

- **Видимое тело**: оно поворачивается вместе со шлемом, голова скрыта.
- **Руки на контроллерах (IK)**: плечо, локоть и кисть следуют за контроллерами, а скрутка предплечья распределяется по костям, без эффекта «фантика».
- **Оружие в руке**: анимации вставки, перезарядки и отдачи сохраняются, пуля летит туда, куда смотрит ствол.
- **Паразит и «магазин» с патронами** остаются на теле и тянутся к руке во время перезарядки.
- **Snap-поворот на 45°** на правом стике. Плавный поворот и угол настраиваются.
- **Прицел**: без оружия — головой, с оружием — правым контроллером.
- **Штатная анимация при взаимодействии**: у пультов, с предметами и в скриптовых сценах телом и руками управляет анимация игры. IK, поворот тела за шлемом, поворот стиком и roomscale-перемещение UEVR на это время отключаются.

### Требования

- Scorn (Steam), версия для Windows.
- [UEVR](https://github.com/praydog/UEVR) — свежая nightly-сборка. Проверено на nightly-сборке UEVR от мая 2026 (revision `38c73f3`).
- VR-шлем через OpenXR (Quest Link / Air Link / Virtual Desktop) или SteamVR.

### Установка

**Вариант 1. Импорт в UEVR (проще всего)**
1. Скачайте `Scorn-Win64-Shipping.zip` со страницы [Releases](../../releases).
2. Запустите Scorn, затем `UEVRInjector.exe`, и выберите процесс `Scorn-Win64-Shipping`.
3. Нажмите **Import Config** и укажите скачанный zip.
4. Нажмите **Inject**.

**Вариант 2. Вручную**

Скопируйте содержимое папки [`profile/Scorn-Win64-Shipping`](profile/Scorn-Win64-Shipping) в
`%APPDATA%\UnrealVRMod\Scorn-Win64-Shipping\`. Должны получиться `config.txt`, `scripts\scorn_vr.lua`, `data\scorn_vr_core.lua` и остальные файлы.

> Если у вас уже был другой профиль Scorn, сначала удалите старую папку `Scorn-Win64-Shipping` целиком. Скрипты из чужих профилей (`scornfix`, `Get the damn gun to stay` и подобные) конфликтуют с этим модом.

### Управление

| Действие | Контроллер |
|---|---|
| Ходьба | левый стик |
| Поворот (snap 45°) | правый стик влево/вправо |
| Прицеливание / выстрел / перезарядка / смена оружия | как в игре с геймпадом (UEVR эмулирует Xbox-геймпад) |
| Меню UEVR | `Insert` на клавиатуре или L3+R3 |

Ось Y правого стика (наклон взгляда) в игре отключена: в VR наклон задают шлем и контроллер.

### Настройки

Меню UEVR → вкладка **Script UI** → **Scorn VR**:

- **Turning**: snap или плавный поворот, угол, стик, блокировка наклона стиком.
- **Body / arms**: режим (тело + IK / тело без IK / только оружие), поворот тела за головой, мёртвая зона поворота, скрытие головы, вторая рука на оружии, штатная анимация при взаимодействии (`Native animation during interactions`), направление ходьбы по взгляду (`Keep the game's camera on the view direction`).
- **Hand placement**: положение кисти относительно контроллера (углы и смещение) и направление локтя (`Elbow down bias`).

Настройки сохраняются в `%APPDATA%\UnrealVRMod\Scorn-Win64-Shipping\data\scorn_vr_config.json`.

### Если что-то не так

- **Нет тела или рук**: проверьте, что в `scripts` лежит только `scorn_vr.lua`. В меню UEVR, в разделе LuaLoader, нажмите **Reset scripts**.
- **Кисть сидит в руке не так, как хочется**: подстройте **Hand placement** в меню.
- **Шлем засыпает, и картинка в игре замирает**: включите в Meta Quest «Bypass Proximity Sensor Check» (Oculus Debug Tool) или отключите автосон в настройках шлема.
- **Сообщить об ошибке**: создайте [Issue](../../issues) и приложите файлы `scorn_vr_log.txt` и `scorn_vr_dump.json` из папки `data` профиля.

### Известные ограничения

- Проверены пистолет, дробовик, ближний бой, стрельба и перезарядка. С остальным оружием (гранатомёт, шокер и т. д.) возможны мелкие артефакты анимации.
- IK пересчитывает только руки.
- Во время взаимодействия голову (обзор) по-прежнему поворачивает шлем, а тело и руки остаются в позе из анимации игры.
- Рендер копии тела отстаёт на один кадр (ограничение `PoseableMeshComponent` в UE4). На глаз это обычно незаметно.

### Благодарности

- [praydog](https://github.com/praydog) — UEVR.
- **Tensai37** — оригинальный Standing-6DOF-профиль Scorn. На его основе сделаны `config.txt`, переключение прицела и синхронизация поворота.

---

## English

A [UEVR](https://uevr.io) profile for **Scorn** (Steam, UE 4.27) that turns the game into a full 6DOF VR game:

- **Visible full body**: it turns with the headset; the head is hidden.
- **IK arms on the motion controllers**: shoulder, elbow and wrist follow the controllers; forearm twist is distributed over the twist bones (no "candy wrapper").
- **Weapon in hand**: insert / reload / recoil animations still play, and bullets go where the barrel points.
- **The parasite and the ammo apparatus** stay on the body and reach for your hand while reloading.
- **45° snap turn** on the right stick. Smooth turn and the snap angle are configurable.
- **Aiming**: head without a weapon, right controller with a weapon.
- **Native interaction animations**: at consoles, with items and in scripted scenes the game's animation drives the body and arms. IK, body-follows-head, stick turning and UEVR roomscale movement are paused meanwhile.

### Requirements

- Scorn (Steam, Windows).
- A recent [UEVR](https://github.com/praydog/UEVR) nightly. Tested with the UEVR nightly from May 2026 (revision `38c73f3`).
- A VR headset via OpenXR (Quest Link / Air Link / Virtual Desktop) or SteamVR.

### Installation

**Option 1. UEVR import (easiest)**
1. Download `Scorn-Win64-Shipping.zip` from [Releases](../../releases).
2. Start Scorn, run `UEVRInjector.exe` and select the `Scorn-Win64-Shipping` process.
3. Click **Import Config** and choose the zip.
4. Click **Inject**.

**Option 2. Manual**

Copy the contents of [`profile/Scorn-Win64-Shipping`](profile/Scorn-Win64-Shipping) to
`%APPDATA%\UnrealVRMod\Scorn-Win64-Shipping\`.

> Remove any previous Scorn profile folder first. Scripts from other profiles (`scornfix`, `Get the damn gun to stay`, ...) conflict with this mod.

### Controls

| Action | Controller |
|---|---|
| Move | left stick |
| Turn (45° snap) | right stick left/right |
| Aim / fire / reload / switch weapon | same as the game's gamepad controls (UEVR emulates an Xbox pad) |
| UEVR menu | `Insert` key or L3+R3 |

Right stick up/down (look pitch) is blocked in gameplay: in VR the headset and the controller set the pitch.

### Settings

UEVR menu → **Script UI** tab → **Scorn VR**:

- **Turning**: snap/smooth turn, angle, stick, stick pitch block.
- **Body / arms**: mode (body + IK / body without IK / weapon only), body follows the head, turn deadzone, hide head, two-handed left hand, native animation during interactions (`Native animation during interactions`), walking follows the view (`Keep the game's camera on the view direction`).
- **Hand placement**: wrist offset and rotation relative to the controller, plus elbow direction (`Elbow down bias`).

Settings are saved to `%APPDATA%\UnrealVRMod\Scorn-Win64-Shipping\data\scorn_vr_config.json`.

### Troubleshooting

- **No body or arms**: make sure `scorn_vr.lua` is the only script in `scripts`. In the UEVR menu, open LuaLoader and click **Reset scripts**.
- **The hand doesn't sit right**: tweak **Hand placement**.
- **The image freezes when the headset sleeps**: enable "Bypass Proximity Sensor Check" in the Oculus Debug Tool, or disable auto-sleep.
- **Bug reports**: open an [Issue](../../issues) and attach `scorn_vr_log.txt` and `scorn_vr_dump.json` from the profile's `data` folder.

### Known limitations

- Tested: pistol, shotgun, melee, firing and reloading. Other weapons (grenade launcher, stun gun, ...) may show small animation artifacts.
- Only the arms use IK.
- During interactions the headset still turns the view; the body and arms stay in the game's animated pose.
- The body copy renders one frame behind (a UE4 `PoseableMeshComponent` limitation). It is usually not noticeable.

### Credits

- [praydog](https://github.com/praydog) — UEVR.
- **Tensai37** — the original Scorn Standing-6DOF profile. The base `config.txt`, aim switching and yaw sync come from it.

## How it works / development

See [dev/README.md](dev/README.md).

## Claude Code skill: making UEVR profiles for other games

The lessons from this project are packaged as a [Claude Code](https://claude.com/claude-code) skill:
[`.claude/skills/uevr-profile`](.claude/skills/uevr-profile/SKILL.md). It contains:
- verified UEVR Lua API facts;
- the full-body + IK architecture with a failure table;
- a live in-game debugging workflow (debug camera, simulated controllers, screenshots, eval);
- templates: a hot-reload loader, a core skeleton, UE math, a UEVR mock for offline tests.

**Use it:** open this repository in Claude Code (the skill is picked up automatically), or copy the folder to `~/.claude/skills/` to use it in any project.

Опыт этого проекта упакован в навык для Claude Code: [`.claude/skills/uevr-profile`](.claude/skills/uevr-profile/SKILL.md). Он помогает делать UEVR-профили для других UE-игр. Откройте репозиторий в Claude Code или скопируйте папку в `~/.claude/skills/`.

## License

[MIT](LICENSE)

# План оптимизации CooldawnBuffTracker

Аудит проведён по навыку `aac-addon-dev` (ArcheAge Classic, patch 293): сверка с `api.lua`
живого клиента, `references/runtime-and-sandbox.md`, `references/api-catalog.md`,
`references/ui-widgets-and-layout.md`, `references/events-and-combat.md`,
`references/x2ui-undocumented.md`, плюс прогон штатных верификаторов навыка.

Дата аудита: 2026-11-12. Базовая версия: 1.5.0 (`main`, 7fce312).

---

## 1. Диагноз в двух абзацах

Код рабочий, но это типичный «наросший» аддон: три почти одинаковых панели, скопированные
руками; горячий цикл перерисовывает весь UI 20 раз в секунду независимо от изменений; половина
модулей-обвязки не используется; данные (533 КБ таблицы иконок) лежат в коде и грузятся всегда;
наименования разъехались (`playerpet` / `mount` / `pet`, `buffData` = данные маунта).

Отдельно подтверждается подозрение про трекинг времени: **у цели таймер пересчитывается от
серверного `timeLeft` на каждом тике, а у игрока и маунта — только в момент первого обнаружения
баффа, дальше идёт локальный отсчёт от номинальной длительности**. Отсюда «у цели в реалтайме,
у игрока/маунта нет». Подробный разбор — раздел 3.

---

## 2. Как проверялось

Штатные инструменты навыка:

```
python3 <skill>/scripts/aac_check.py .     -> RESULT: FAIL — 2 errors, 23 warnings
python3 <skill>/scripts/aac_smoke.py .     -> RESULT: PASS — 6/6 phases, 16 ticks, 269 widgets, 18 events
                                              note: reload leak: второй OnLoad создал 133 виджета,
                                              OnUnload не освободил ни одного
```

Что это значит:

* `aac_check` нашёл 2 настоящие ошибки (обе — в мёртвом `util/check_button.lua`: голый глобал
  `default`) и 23 предупреждения: 4× вызов `api.Ability.GetBuffTooltip` через точку вместо
  двоеточия, глобальные утечки в `buff_helper.lua`/`main.lua`, самодельные события без префикса
  (`MOUNT_BUFF_TRACKER_*`), `SetZOrder` (метод есть только в одном аддоне корпуса — риск).
* `aac_smoke` проходит, но фиксирует утечку: `OnUnload` не освобождает ни одного виджета, каждый
  `/reload` добавляет 133 новых.

Объём: 16 Lua-файлов, 20 964 строки, из них 12 813 (61 %) — таблица `BuffList.ddsData`
(12 677 записей `id -> .dds`) в `buff_helper.lua`. Реального кода ~7,4 тыс. строк,
но из них ~1,3 тыс. — мёртвые. После этапа 1 удалены `canvas_factory.lua` (333) и
`util/check_button.lua` (214); после этапа 3 `main.lua` сократился с 2 153 до 2 037 строк за счёт
слияния конструкторов панелей. Итог: 14 файлов, 20 314 строк.

---

## 3. Главное: трекинг времени у цели vs игрока/маунта

### 3.1 Что происходит в коде

Единая точка расчёта — `setBuffStatus()` (`main.lua:193-253`). Если ей передали `remainingTime`
(мс), она пересчитывает момент старта баффа от серверного остатка:

```lua
-- main.lua:236-245
if remainingTime and remainingTime > 0 and buff.timeOfAction then
  local remainingSeconds = remainingTime / 1000
  buff.fixedTime = currentTime - (tonumber(buff.timeOfAction) - remainingSeconds)
else
  buff.fixedTime = currentTime
end
```

Опрос баффов (`main.lua:1430-1441`, дебаффы — `1476-1485`) передаёт `timeLeft` **только для цели**:

```lua
local isNewBuff = not buffDataTable[buff.buff_id] or (buffDataTable[buff.buff_id].status ~= "active")
local shouldUpdateTarget = unitType == "target" and buff.timeLeft and buff.timeLeft > 500
if isNewBuff or shouldUpdateTarget then
  local timeLeftParam = (unitType == "target") and buff.timeLeft or nil   -- <— вот разница
  setBuffStatus(buff.buff_id, "active", getCurrentTime(), unitType, timeLeftParam)
end
```

Дальше отображение считается одинаково:
остаток = `timeOfAction - (now - fixedTime)` (`main.lua:1146-1156`), статус — `checkBuffStatus()`
(`main.lua:255-273`), фаза «кулдаун» = `fixedTime + cooldown` (cooldown — введённое вручную КД
умения).

### 3.2 Последствия

| Ситуация | Цель (`target`) | Игрок / маунт (`player` / `playerpet`) |
|---|---|---|
| Бафф наложен при работающем аддоне | остаток точный (ре-синк каждые 50 мс) | остаток = номинал с момента обнаружения (ошибка ≤ 50 мс) |
| Бафф уже висел до логина / `/reload` / появления цели | точный остаток сразу | покажет полный номинал с момента загрузки — **врёт** |
| Реальная длительность ≠ `timeOfAction` в настройках | **не влияет**: показываемый остаток = `timeLeft` | врёт весь срок пропорционально ошибке |
| Бафф обновлён/переприменён (refresh) | подхватывает новый остаток | `fixedTime` не сдвигается, пока `status == "active"` — **не подхватывает** |
| Бафф снят/диспелнут досрочно | иконка остаётся «active» до номинального конца | то же — общий баг, см. 4.2 |
| Дебаффы | читаются (`UnitDeBuff`), с ре-синком | у игрока читаются без ре-синка; **у маунта не читаются вовсе** |

Оговорка: флаг `> 500 мс` — защита от «мерцания» в последние полсекунды; последние 0.5 с у цели
идут локальным отсчётом.

### 3.3 Правильный вариант

Данные для этого, по каталогу API, есть у всех: `UnitBuff(unit, i)` возвращает
`{buff_id, path, stack, timeLeft}` — одна и та же таблица для любого юнита из белого списка
(`player`, `playerpet*`, `target`, …), отдельного «только для цели» поля в API нет.

Целевая модель (один код для всех юнитов):

```lua
local remaining = buff.timeLeft                      -- мс, любой юнит
if remaining and remaining > 500 then
  fixedTime = now - (timeOfAction - remaining / 1000)  -- ре-синк от сервера
elseif isNew then
  fixedTime = now                                    -- запасной локальный отсчёт
end
```

Плюс закрыть дыру 4.1.2 (бафф исчез → сразу «кулдаун», отсчёт от `fixedTime`, а не от «сейчас»).

Перед внедрением — 5-минутная проверка в игре, что `timeLeft` непустой у `playerpet`
(скрипт-проба в приложении B). Если у маунта `timeLeft` окажется нулевым — оставить локальный
отсчёт только для него, но тогда честно задокументировать.

---

## 4. Баги (чинить в первую очередь)

### 4.1 P0 — влияют на поведение

1. **Асимметрия таймеров цель/игрок/маунт** — раздел 3.
2. **Досрочное снятие баффа не обрывает «active».** В ветке «баффа больше нет на юните»
   (`main.lua:1511-1546`) статус пересчитывается только по часам (`checkBuffStatus`), поэтому
   диспел/смерть/переприменение раньше срока оставляют зелёную иконку до номинального конца.
   Для цели это частично маскируется ре-синком, для игрока/маунта видно всегда.
3. **`OnUnload` не останавливает `UPDATE`.** `main.lua:1956` делает
   `api.On("UPDATE", function() end)` — это добавление пустого обработчика, а не отписка
   (`api.Off` в sandbox не существует). После выгрузки аддона `OnUpdate` продолжает опрашивать
   `api.Unit:*` 20 раз в секунду до перезагрузки UI. Нужен флаг `live` (канон навыка) —
   он же защитит от гонок при `/reload`.
4. **`api.Ability.GetBuffTooltip` вызывается через точку** (`buff_helper.lua:12733,12761,12805`,
   `buff_search_window.lua:60`). Метод объявлен через `:` — при вызове с точкой `self` получает
   `buffId`, реальные аргументы съезжают, тултип не возвращается. Итог: «Try to get actual buff
   name from game API» не работает никогда, имена — только из `customBuffs`, иконки — только из
   `ddsData`. Чинить на `api.Ability:GetBuffTooltip(id)` — после этого ОДИН вызов даёт и имя, и
   иконку (`.path`), и описание, для любого id (см. 7.1). Кэшировать результат по id.
5. **`api.SaveSettings()` внутри горячего пути.** `buffs_to_track.lua:8-31`
   (`loadTrackedBuffsFromSettings`) пишет файл настроек, если у юнита нет поля `trackedBuffs`;
   функция вызывается из `checkBuffs` каждые 50 мс. По правилам навыка сохранять настройки можно
   только по действию пользователя: запись из тика — это класс бага «сбросились настройки всех
   аддонов». Перенести инициализацию в `OnLoad`.
6. **Импорт конфига теряет дробные значения.** `util/import_export.lua:30-48`: все числа
   сериализуются как `string.format("%.0f", value)`, а `importConfigurationFromFile` гонит файл
   через `json.encode` → `json.decode` (`:500-515`). Кулдаун `16.2` станет `16`, длительность
   `0.1` — нулём. В `example config.txt` таких дробных значений шесть. Либо убрать JSON-прослойку
   для файлов (читать таблицу напрямую), либо сериализовать числа с `%.10g`.

### 4.2 P0 — тихие, но вредные

7. **`api._Library` без проверки.** `helpers.lua:221-227` (`createCheckbox`) дергает
   `api._Library.UI.CreateCheckButton`. `api._Library` существует только если установлен
   `addonlibrary`; функция сейчас не вызывается (мёртвая), но это мина. Удалить — и тогда
   зависимость `addonlibrary` в манифесте CAM становится ненужной.
8. **Два разных дефолта для неизвестного баффа.** `buff_helper.lua:12713-12719` возвращает
   `cooldown = 30, timeOfAction = 50`; `main.lua:170-176` и `212-218` — `30` и `3`. То есть
   «неизвестный» бафф по факту живёт 50 с. Свести к одной константе.
9. **Событие без отправителя.** `MOUNT_BUFF_TRACKER_EMPTY_LIST` слушается (`main.lua:2133`), но
   никто его не шлёт — мёртвый обработчик. Имена `MOUNT_BUFF_TRACKER_*` вводят в заблуждение
   (события общие для всех юнитов) — переименовать в `CBT_TRACKED_BUFFS_CHANGED` и т.п.

### 4.3 Утечки/профилировщик

10. `OnUnload` (`main.lua:1954-2015`) скрывает канвасы и снимает `OnDragStart/OnDragStop`, но не
    вызывает `api.Interface:Free` — смоук фиксирует «133 виджета за второй OnLoad, освобождено 0».
    `Free` тоже не освобождает `OnDragStop` (движковый баг) — снимать его самим, как сейчас, и
    после этого звать `Free`.
11. `MAX_GRID_ICONS = 40` (`main.lua:293`) создаётся на каждую панель всегда, даже если у
    пользователя два баффа: 40 иконок × ~10 дочерних объектов (оверлей, 4 рамки, два лейбла,
    фон таймера, сам слот) × 3 панели. Пул нужен по факту —
    `math.min(#trackedBuffs, cols*rows)`.

---

## 5. Производительность и архитектура

### 5.1 Горячий цикл (главная «неоптимальность»)

Сейчас `OnUpdate` (`main.lua:1610-1650`) при `updateInterval = 50` и `refreshUIInterval = 50`:

* 20 раз в секунду × 3 юнита: `UnitBuffCount` + `UnitBuff` по каждому слоту + для player/target
  ещё `UnitDeBuffCount` + `UnitDeBuff`. На каждом слоте — `BuffsToTrack.ShouldTrackBuff()`,
  который заново делает `api.GetSettings("CooldawnBuffTracker")` и линейный поиск по списку
  (`buffs_to_track.lua:126-139`, `:141-146`).
* 20 раз в секунду × 3 панели: `updateBuffIcons()` (`main.lua:886-1242`) полностью
  перераскладывает все иконки: `SetExtent`, `RemoveAllAnchors`+`AddAnchor`, `SetIconBackGround`,
  цвета оверлея и четырёх рамок, `SetFontSize`, позиции и текст обоих лейблов, `SetWidth/Height`
  канваса — ~25 вызовов движка на иконку, до 40 иконок на панель.

Оценка порядка: в простое это ~12-15 тыс. вызовов движка в секунду, при том что текст таймера
меняется не чаще 10 раз в секунду (десятые доли показываются только ниже 10 с). Навык
рекомендует: опрос баффов 200-500 мс, UI 100-250 мс, «dirty flag» на перерисовку.

Целевая схема:

* опрос баффов — 100 мс в бою / активных треках, 300-500 мс в простое (адаптивный тик, как в
  `nuzi-fishing`);
* перестроение геометрии (якоря/размеры/шрифты/цвета) — только при смене настроек, набора
  видимых иконок или размера панели;
* каждые 100 мс — только текст таймера, и только если строка изменилась;
* `ShouldTrackBuff` — один раз на тик: собрать set из `trackedBuffs` и сверять по ключу;
  инвалидировать по событию `CBT_TRACKED_BUFFS_CHANGED`.

### 5.2 Дублирование

* Три конструктора канвасов `createBuffCanvas` / `createPlayerBuffCanvas` /
  `createTargetBuffCanvas` (`main.lua:477-806`) отличаются только ключом настроек и типом юнита —
  ~330 строк, из которых 2/3 копипаста. Плюс четвёртая копия — `canvas_factory.lua` (не
  подключается ниоткуда).
* Блок «пересоздать/показать/обновить канвасы» продублирован в `OnSettingsSaved`
  (`main.lua:1899-1950`) и в обработчике `MOUNT_BUFF_TRACKER_UPDATE_BUFFS` (`main.lua:2078-2129`).
* Ветвление `if unitType == "target" … elseif unitType == "player" … else` — 24+21 вхождение в
  `main.lua`; нужна таблица юнитов.
* Обновление списков в настройках — три почти одинаковых блока пагинации (buff/search/preset).

### 5.3 Целевая структура

```
CooldawnBuffTracker/
  main.lua                  -- манифест + жизненный цикл (≤ 150 строк)
  core/units.lua            -- UNITS = { playerpet=…, player=…, target=… } (token, label, debuffs)
  core/tracker.lua          -- опрос баффов + модель времени (раздел 3.3), кэш цели
  core/panel.lua            -- одна панель: create/updateLayout/updateTimers/destroy
  core/settings.lua         -- дефолты, миграции, пресеты (без UI)
  core/icons.lua            -- ленивая таблица иконок + кэш тултипов
  ui/settings_page.lua      -- разбить initSettingsPage на группы
  ui/preset_window.lua
  ui/search_window.lua
  ui/import_export.lua
  ui/debugger.lua
```

Совместимость: ключи настроек (`playerpet`, `player`, `target`, `trackedBuffs`, `customBuffs`,
`presets`, `activePresetName`), имя папки и id `CooldawnBuffTracker` **не меняются** — иначе
потеряются настройки у всех пользователей и сломается манифест CAM. Опечатку «Cooldawn» в имени
аддона оставляем как есть, наружу она уже зафиксирована.

---

## 6. Мёртвый код и наименования

Удалить (проверено: нет вызовов):

| Файл/сущность | Строк | Комментарий |
|---|---|---|
| `canvas_factory.lua` | 333 | **удалён** (этап 1): четвёртая копия фабрики иконок, нигде не подключалась |
| `util/check_button.lua` | 214 | **удалён** (этап 1): копия модуля из addonlibrary, нигде не подключалась; был единственным источником 2 ошибок чекера |
| `api.lua` в корне аддона | 709 | устаревшая копия официального стаба API; `require("api")` её не использует — только путает |
| `BuffList.ALL_BUFFS` + `IsValidBuff` | ~40 | таблица пустая, валидатор не вызывается |
| `cachedMountBuffs`, `cachedPlayerBuffs`, `cachedBuffStatus` | ~10 | только записываются, не читаются |
| `activeBuffsOnUnit`, `statusChangeTime` | ~6 | только записываются |
| обработчик `MOUNT_BUFF_TRACKER_EMPTY_LIST` | ~20 | нет отправителя |
| `helpers.createCheckbox` | 6 | `api._Library` без проверки, не вызывается |

Наименования (единый словарь): внутренний ключ `playerpet` (токен игры) во всех местах,
человекочитаемое имя — «Mount» (в UI уже так); `buffData` → `tracker.state.mount`,
`playerBuffData` → `.player`, `targetBuffData` → `.target`; `buffCanvas` → `panels.mount`;
`updateTimer`/`refreshUITimer` с одинаковым интервалом — один тик с двумя фазами (scan/render).

Прочее по UI (правила навыка):

* `canvas:SetZOrder(100)` (`main.lua:492,606,720`) — метод есть в одном аддоне корпуса; заменить
  на `SetUILayer("hud")`.
* Рамки иконок — 4 цветных прямоугольника толщиной 2 UI-единицы: по заметкам корпуса
  (BetterBars, `UI_SCALING.md`) тонкие `CreateColorDrawable` при дробном UI-масштабе (0.85)
  растеризуются в 0-1 px и «пропадают» на части периметра. Либо ninepart-атлас
  (`TEXTURE_PATH.HUD`), либо идиома «заливка с отступом Px(1)» из навыка
  (`ui-widgets-and-layout.md`, §8).
* `GetOffset()` при перетаскивании — предпочтителен `GetEffectiveOffset()` с fallback на
  `GetOffset()`, если он вернул nil (официальный API-стаб называет `GetOffset` запасным).

---

## 7. Данные и упаковка

### 7.1 Иконки и имена: таблица не обязательна (проверено по клиенту)

В клиенте AAC (patch 293, `pak_aac/src`) есть два источника картинки баффа:

* **активный бафф** — `api.Unit:UnitBuff(unit, i)` возвращает `.path` (клиент сам рисует им
  иконку в бафф-винде: `x2ui/components/buffwindow.lua:232` — `F_SLOT.SetIconBackGround(button,
  buffInfo.path)`);
* **любой id, в том числе неактивный** — `api.Ability:GetBuffTooltip(id)` → в клиенте
  `X2Ability:GetBuffTooltip(buffId, itemLevel)` (`x2ui/addons/api.lua:1153-1155`), и его результат
  содержит `.path`, `.name`, `.description`. Доказательства использования вне боевых баффов:
  `x2ui/loginstage/character_create/character_create.lua:99-100`
  (`skillBtn:SetIconPath(buffInfo.path)` для рассовых баффов до входа в мир),
  `x2ui/characterinfo/appellation.lua:114`, `x2ui/questcontext/common.lua:419`,
  `x2ui/community/expedition/expedition_management_infomation_sub.lua:106,115`.

Вывод: 533-КБ таблица `ddsData` **не нужна как основной источник** — достаточно
`api.Ability:GetBuffTooltip(id)` (через двоеточие!) с кэшем `id -> {path, name}` и маленькой
fallback-картой для id, на которые тултип вернёт nil (серверные баффы, которых нет в клиентских
данных). При этом `.path` используется ровно так, как его отдаёт клиент — без ручной склейки
`"game/ui/icon/"` (корпус использует и `buff.path` напрямую: `LoseControl/main.lua:236`,
`better-archeage/buff_tracker.lua:136`).

Проверить в игре (5 минут): прогнать `api.Ability:GetBuffTooltip(id)` по всем id из
`trackedBuffs`/`customBuffs` и вывести `path/name` — приложение B, расширенное на тултип.

### 7.2 Что реально лежит в гейм-паке AAC

Пак AAC — `C:\AAClassic\game_pak` в ВМ 300 на `.147` (проверено: 44 885 643 776 байт,
3 ноября 2026 23:06, версия 293). Читается двумя путями:

* смонтировать диск ВМ тома только для чтения: `losetup -r -f --show
  /dev/zvol/rpool/data/vm-300-disk-0-part2` + `ntfs-3g -o ro` в `/mnt/ro300` (ВМ 300 держать
  выключенной; размонтировать после);
* или `tools/pak.py` из workspace навыка (`~/work/aa-addon-skill`) — ридер формата AAPak
  «WIBO» (AES-128-CBC, штатный ключ XLGames), FAT уже собран:
  `pak_aac/fat_aac.json` — **336 990 файлов**.

Состав пака (по FAT): 62 642 `.dds` (вся иконная графика, включая `game/ui/icon/`), 1 248 `.alb`
(клиентские Lua-скрипты), 59 140 `.mtl`, 42 730 `.chr`, 39 207 `.bai`, ~12 500 `.dat`, 6 297
`.xml`. **Таблицы `buff_id -> иконка/имя/длительность` в паке нет.** Единственный кандидат —
`game/db/compact.sqlite` (28 МБ): это **не SQLite** — заголовок не `SQLite format 3`, ключом пака
не расшифровывается (проверено), т.е. закрытый формат клиента.

### 7.3 Серверная AAEmu-база — справочник, но не AAC

В `~/work/aa-vneshki/db/ArcheAge_Server_Compact_r208088_v1.2.4.13_update_2026-01-23/` лежит
серверная `compact.sqlite3` (679 таблиц): `buffs` — 9 816 строк (`id, name, desc, icon_id,
duration, …`), `icons` — 8 186 (`id, filename`). Сверка с таблицей аддона: для стандартных id
(131, 330, 2405, 3523, 3636, 4994, 5178, 6148, 6413, 6747, 7650, 7651) **иконки совпадают 1:1**
и длительности осмысленны — то есть `ddsData` исторически и собран из такой базы. Но AAC-кастомные
id (`8000211`, `8000049`, `8000405`, `8000033`, `15067`) в этой базе отсутствуют (12 из 17
совпали). Как источник «свежих таблиц AAC» она не годится; как справочник — да.

### 7.4 Остальное

* `IsValidBuff`/`GetBuffInfo` просматривают `ALL_BUFFS` (пусто) и `customBuffs` линейно на каждый
  вызов — заменить на индекс `id -> buff` при загрузке настроек; `ALL_BUFFS` удалить.
* `json.encode/decode` (692 строки в `import_export.lua`) — можно схлопнуть до ~80 строк или
  заменить на `api.serialize` + прямой `File:Read` (см. 4.1.6). Это заодно уберёт потерю дробей.
* Манифест CAM (`classic-addon-manager/addons/CooldawnBuffTracker.yaml`): `dependencies:
  ['addonlibrary']` нужна только из-за мёртвой `helpers.createCheckbox` — после её удаления
  зависимость убрать (см. 6 и 9). Обновление у пользователей идёт через GitHub Release — при
  релизе ставить тег и публиковать release, а не только push.
* README: добавить раздел установки (папка в `Addon/` + строка в `addons.txt`) и короткий
  changelog; перенести `example config.txt` в `docs/`.
* Имя: `CooldawnBuffTracker` — опечатка (правильно **Cooldown**, «перезарядка»). Менять
  папку/id/репозиторий нельзя: это сломает `addons.txt` у пользователей, ключ настроек
  (`api.GetSettings` санитизирует имя папки), `require("CooldawnBuffTracker/…")` и манифест CAM.
  Правим только человекочитаемые подписи: `name` в `main.lua`, `alias` в CAM yaml, заголовок
  README — «Cooldown Buff Tracker».

---

## 8. План работ по этапам

Каждый этап заканчивается прогоном `aac_check.py` + `aac_smoke.py` и ручной проверкой в игре по
чек-листу. Ветка: `refactor/aac-skill-audit` (этот документ — её первый коммит).

**Этап 0 — базлайн (сделан).**
`aac_check`: FAIL 2E/23W; `aac_smoke`: PASS + утечка 133 виджетов. Зафиксировано здесь.

**Этап 1 — безопасные фиксы (1 сессия) — СДЕЛАНО в этой ветке.**
Сделано: удалены мёртвые `canvas_factory.lua` и `util/check_button.lua`, вырезана
`helpers.createCheckbox` (зависимость `addonlibrary` больше не нужна); `OnUpdate` гаснет флагом
`live` (вместо несуществующего `api.Off`); `OnUnload`/`Unload` вызывают `api.Interface:Free`;
`api.SaveSettings()` убран из горячего пути `buffs_to_track`; импорт конфига сохраняет дробные
числа (`%.10g`); `GetBuffTooltip` вызывается через двоеточие (иконки/имена из API заработали);
`SetZOrder` заменён на `SetUILayer("hud")`; `CreateItemIconButton` больше не подменяется
глобально; события переименованы в `ADDON_CBT_BUFFS_CHANGED` / `ADDON_CBT_BUFFS_EMPTY`.
Критерий: `aac_check` → PASS (0 errors; остаются 2 W240 на собственные события — ложные
срабатывания чекера, эмитятся в этом же аддоне), `aac_smoke` → PASS без примечания про reload
leak (0 warnings).

**Этап 2 — унификация таймеров (раздел 3.3) — СДЕЛАНО в этой ветке.**
Реализовано в `main.lua`: `timeLeft` ре-синкается для всех юнитов (player/playerpet/target),
исчезновение баффа (2 опроса подряд при читаемом юните) обрывает активную фазу и переводит в
«кулдаун», постоянные баффы (`timeLeft == nil`) не показывают таймер, кулдаун считается от
`fixedTime` (момент старта баффа).
Критерий приёмки в игре (один персонаж, бафф 3 с / КД 30 с):
  - взять цель, когда осталось 2 с → зелёная обводка, таймер кулдауна 29;
  - на 1 с бафф диспелят → обводка снимается, красный кулдаун 28 (не 29/30);
  - дать баффу истечь самому → на 3-й секунде кулдаун 27, на 30-й — ready;
  - бафф, висевший до `/reload`, показывает остаток, а не полный номинал;
  - дебаффы игрока и цели ведут себя так же; у маунта — то же для баффов.
Тест-скрипт математики: сценарий проверен offline (t=1 → 29.0, t=2 диспел → 28.0,
t=13 естественное окончание → 27.0, t=40 → ready); в игре осталось проверить интеграцию
с реальным `timeLeft`/диспелом.

**Этап 3 — панель и тик (5.1-5.2) — ЧАСТИЧНО СДЕЛАНО в этой ветке.**
Сделано: три конструктора канвасов сведены в один `createPanelCanvas(windowId, unitType)`;
рендер перестроен на подпись раскладки — геометрия, якоря, шрифты, текстура и подписи
обновляются только при изменении набора/настроек, иначе обновляются лишь цвет статуса
(при смене) и текст таймера (при изменении строки); скрытые иконки не трогаются лишний раз;
панели переведены на UI-слой `hud`.
Осталось: пул иконок по числу треков (сейчас на панель заранее создаётся MAX_GRID_ICONS = 40)
и слияние модулей в единый `core/` — делать после проверки в игре, чтобы не смешивать
поведенческие и структурные правки.
Критерий: `aac_check`/`aac_smoke` PASS (выполнено); в игре — визуально без изменений,
счётчик виджетов на панель ≤ 4 × #треков (после доработки пула).

**Этап 4 — страница настроек (5.3).**
`initSettingsPage` (1133 строки, 140 локалов — впритык к лимиту Lua 5.1 в 200) разбить на
функции-группы; убрать дублирующиеся блоки пагинации.
Критерий: `aac_check` PASS, открытие/закрытие настроек без утечек (смоук + визуально), все поля
работают.

**Этап 5 — данные и релиз (раздел 7) — ЧАСТИЧНО СДЕЛАНО в этой ветке.**
Сделано: `GetBuffIcon` сначала спрашивает `api.Ability:GetBuffTooltip` (кэш `id -> path` на
сессию), `ddsData` — только fallback; README дополнен установкой, разделом «How the timers
work» и changelog.
Осталось: манифест CAM (в репозитории `classic-addon-manager/addons` снять
`dependencies: ['addonlibrary']` — отдельный PR), тег + GitHub Release после проверки в игре.

Приоритет: 1 → 2 → 3; 4 и 5 можно параллелить.

---

## 9. Риски и ограничения

* Настройки пользователей — святое: ключи и id не переименовываем; миграции только «добавить
  недостающее» (`if s[k] == nil then`), `false`/`0` сохраняются.
* Пресеты и `customBuffs` живут в `addon_settings` через `api.SaveSettings()`; после 4.1.5
  запись только по действию пользователя (кнопка Save, конец drag, OnUnload).
* `SetZOrder`/`SetUILayer` и `GetEffectiveOffset` — сначала проверить на одном окне в игре
  (методы могут отсутствовать в конкретной сборке; вызывать с проверкой).
* `api.Ability:GetBuffTooltip` после фикса даёт `.name`, `.path` и `.description` для любого id
  (раздел 7.1). Таблица `ddsData` остаётся только fallback'ом для id, где тултип вернул nil
  (серверные баффы, которых нет в клиентских данных).
* Импорт старых конфигов: после 4.1.6 дробные значения начнут сохраняться корректно; ранее
  экспортированные файлы уже потеряли дроби — это не восстановить, но новые будут целыми.

---

## Приложение A. Точные ссылки на находки

```
main.lua:193-253          setBuffStatus — расчёт fixedTime (remainingTime → ре-синк)
main.lua:255-273          checkBuffStatus — статус только по часам (нет учёта снятия)
main.lua:1430-1441        передача timeLeft ТОЛЬКО для target (баффы)
main.lua:1476-1485        то же для дебаффов
main.lua:1511-1546        ветка «баффа больше нет»: статус не обрывается
main.lua:1610-1650        OnUpdate: 50 мс на scan и 50 мс на полный render
main.lua:1956             api.On("UPDATE", function() end) — не отписка
main.lua:2028-2052        monkey-patch глобального CreateItemIconButton
main.lua:2055, 2133       самодельные события MOUNT_BUFF_TRACKER_*
main.lua:293              MAX_GRID_ICONS = 40 на панель
main.lua:492,606,720      SetZOrder
main.lua:477-806          три копии конструктора канваса
buffs_to_track.lua:8-31   api.SaveSettings() из горячего пути
buff_helper.lua:6         ALL_BUFFS = {} (пустая)
buff_helper.lua:9-12686   ddsData: 12 677 записей, 533 КБ
buff_helper.lua:12713-19  дефолт cooldown=30 / timeOfAction=50
buff_helper.lua:12726-40  GetBuffTooltip через точку (не работает)
buff_helper.lua:12773     IsValidBuff — не вызывается
util/import_export.lua:30-48   "%.0f" для всех чисел
util/import_export.lua:500-515 файл → JSON → потеря дробей
helpers.lua:101-131       CANVAS.OnSettingsSaved — никто не назначает
helpers.lua:221-227       api._Library без проверки (мёртвая функция)
util/check_button.lua     мёртвый модуль, 2 ошибки чекера
canvas_factory.lua        мёртвый модуль, 333 строки
```

## Приложение B. Проба `timeLeft` у player/pet/target (5 минут в игре)

```lua
-- временный аддон-проба: печатает поля UnitBuff для трёх юнитов
local api = require("api")
local acc = 0
local addon = { name = "cbt_probe", author = "me", version = "0.1" }
function addon.OnLoad()
  api.On("UPDATE", function(dt)
    acc = acc + dt
    if acc < 2000 then return end
    acc = 0
    for _, u in ipairs({ "player", "playerpet", "target" }) do
      local n = api.Unit:UnitBuffCount(u) or 0
      for i = 1, n do
        local b = api.Unit:UnitBuff(u, i)
        if b and b.buff_id then
          api.Log:Info(string.format("%s id=%s timeLeft=%s stack=%s",
            u, tostring(b.buff_id), tostring(b.timeLeft), tostring(b.stack)))
        end
      end
    end
  end)
end
function addon.OnUnload() end
function addon.OnSettingToggle() end
return addon
```

Ожидание: `timeLeft` (мс) присутствует у всех трёх юнитов. Если у `playerpet` он `nil`/`0` —
ре-синк для маунта невозможен, оставляем локальный отсчёт и фиксируем это в README.

Вторая проба — иконки/имена без таблицы (для этапа 5). Запускается на персонаже с заполненными
`trackedBuffs` и печатает, что вернул тултип по каждому id:

```lua
local api = require("api")
local addon = { name = "cbt_probe_tip", author = "me", version = "0.1" }
local function run()
  local s = api.GetSettings("CooldawnBuffTracker") or {}
  local seen = {}
  for _, ut in ipairs({ "playerpet", "player", "target" }) do
    for _, id in ipairs((s[ut] and s[ut].trackedBuffs) or {}) do
      if not seen[id] then
        seen[id] = true
        local ok, info = pcall(function() return api.Ability:GetBuffTooltip(id) end)
        if ok and type(info) == "table" then
          api.Log:Info(string.format("id=%s name=%s path=%s",
            tostring(id), tostring(info.name), tostring(info.path)))
        elseif ok then
          api.Log:Info("id=" .. tostring(id) .. " -> nil (нужен fallback)")
        else
          api.Log:Err("id=" .. tostring(id) .. " -> " .. tostring(info))
        end
      end
    end
  end
end
function addon.OnLoad()
  -- дать клиенту догрузить данные и войти в мир
  api:DoIn(5000, function() run() end)
end
function addon.OnUnload() end
function addon.OnSettingToggle() end
return addon
```

Ожидание: у большинства id есть `path` и `name`. Для id, где вернулся nil, оставляем запись в
fallback-таблице (их и надо держать в `ddsData`).

## Приложение C. Базлайн-вывод верификаторов

```
aac_check.py  RESULT: FAIL — 2 errors, 23 warnings
  2× E120  util/check_button.lua:67-68  глобал `default`
  4× W231  api.Ability.GetBuffTooltip через точку
  1× W220  buff_helper.lua:12696 глобал `settings`
  1× W220  main.lua:2051 CreateItemIconButton переопределён
  2× W240  MOUNT_BUFF_TRACKER_* — нет такого события в API
  2× W200  SetZOrder (main.lua:493, canvas_factory.lua:193)
  + W200/W220 в util/check_button.lua (мёртвый файл)

aac_smoke.py  RESULT: PASS — 6/6 phases, 16 ticks, 269 widgets, 18 events
  note: reload leak — второй OnLoad создал 133 виджета, OnUnload не освободил ни одного
```

-- Локализация аддона (1.30.0).
-- L(text, ...) ищет перевод по АНГЛИЙСКОМУ исходному тексту; ключ без перевода
-- возвращает исходную английскую строку, поэтому пользовательские данные
-- (имена баффов, id, имена пресетов, пути) проходят через L() без изменений.
-- Если переданы аргументы, переведённый шаблон форматируется string.format.
local api = require("api")

local M = {}

local ADDON_ID = "CooldawnBuffTracker"
local DEFAULT = "en"

-- Пять языков: код, родное название (не переводится), английское имя.
local LANGS = {
    { code = "en", native = "English",  name = "English" },
    { code = "ru", native = "Русский",  name = "Russian" },
    { code = "zh", native = "中文",      name = "Chinese" },
    { code = "tr", native = "Türkçe",   name = "Turkish" },
    { code = "ko", native = "한국어",     name = "Korean" },
}
M.LANGS = LANGS
M.DEFAULT = DEFAULT

local CODES = {}
for _, lang in ipairs(LANGS) do CODES[#CODES + 1] = lang.code end

-- Словари: код -> { [английский текст] = перевод }.
-- Формат блока: одна пара на строку, «ключ<TAB>перевод» (ключ может
-- содержать «|», поэтому разделитель — табуляция).
local dict = {}

-- >>> DICT
dict.ru = [==[
 (active)	 (активен)
 (no target)	 (нет цели)
 (was %s)	 (было %s)
 + search '%s'	 + поиск '%s'
 | first error: %s	 | первая ошибка: %s
%d. buff ID: %s	%d. ID баффа: %s
%d. debuff ID: %s	%d. ID дебаффа: %s
%s (id %s) - %s, seen %s time(s).	%s (id %s) - %s, замечено раз: %s.
%s (id %s) on canvas %s.	%s (id %s) на канвасе %s.
%s - %s. Click to apply this icon.	%s - %s. Нажмите, чтобы применить иконку.
%s - buff ID: %s, unit: %s	%s - ID баффа: %s, юнит: %s
%s - seen %s time(s) in the combat log.	%s - встреч в боевом логе: %s.
%s args: %s	%s аргументы: %s
%s buff added for tracking: %s (%s)	%s: бафф добавлен в отслеживание: %s (%s)
%s buff removed from tracking: %s	%s: бафф снят с отслеживания: %s
%s tracked entries will be removed from this unit.	С этого юнита будет снято отслеживаемых записей: %s.
'%s': cooldown recorded for %s (unit %s)	'%s': КД записан для %s (юнит %s)
'%s': no source in the event	'%s': в событии нет источника
'%s': repeat trigger after %.1f s - ignored (window %s)	'%s': повторный триггер через %.1f с - пропущен (окно %s)
'%s': self cast -> Player/Mount panels: %s	'%s': самокаст -> панели Player/Mount: %s
'%s': self cast, but the buff is not tracked on Player/Mount	'%s': самокаст, но бафф не отслеживается на Player/Mount
'%s': source %s unknown, waiting for the first target	'%s': источник %s неизвестен, ждём первую цель
'%s': you are the current target -> recorded to Target	'%s': вы текущая цель -> записано в Target
(no target)	(нет цели)
(set at creation, cannot be changed)	(задаётся при создании, изменить нельзя)
* Mount	* Маунт
* Player	* Игрок
* Target	* Цель
+Flat	+Сек
+Flat: subtract N seconds, applied before the percentages.	+Flat: вычесть N секунд, применяется до процентов.
+Percent	+Проц
+Percent: subtract N %, applied after all flat reductions.	+Percent: вычесть N %, применяется после всех плоских сокращений.
Active	Активен
Active buffs for %s (%d):	Активные баффы %s (%d):
Active debuffs for %s (%d):	Активные дебаффы %s (%d):
Active preset: %s	Активный пресет: %s
Active preset: None	Активный пресет: нет
Add	Добавить
Add a canvas: copies this layout and places the copy below it.	Добавить канвас: копирует эту раскладку и ставит копию ниже.
Add a custom entry: pick the type first, the fields below follow it, then Add entry.	Добавить пользовательскую запись: сначала выберите тип, поля ниже подстроятся, затем Add entry.
Add custom entry:	Новая запись:
Add entry	Добавить запись
Add this entry to tracking on the current unit and canvas.	Добавить запись в отслеживание на текущем юните и канвасе.
Add this source as a modifier (condition On target, type Flat, value 0).	Добавить этот источник как модификатор (условие On target, тип Flat, значение 0).
Add to tracking on the current unit (creates a custom entry with a default CD/D when needed).	Добавить в отслеживание на текущем юните (при необходимости создаёт запись с CD/D по умолчанию).
Add: buff -> custom entry + tracking. Skill -> custom entry with Spell filled.	Add: бафф -> запись + отслеживание. Навык -> запись с заполненным Spell.
Added skill: %s	Добавлен навык: %s
Added to %s	Добавлено в %s
Added: %s	Добавлено: %s
Addon Options	Настройки аддона
Already tracked (%s)	Уже отслеживается (%s)
Already tracked: %s	Уже отслеживается: %s
Also fill the entry's Spell field with the picked buff name.	Также заполнить поле Spell записи именем выбранного баффа.
Always	Всегда
Always:	Всегда:
Apply icon, grid, position and timer values. Enter inside a field applies it too.	Применить значения иконок, сетки, позиции и таймера. Enter в поле тоже применяет.
Apply the modifiers below to this entry's cooldown (buff/debuff and skill, target only).	Применять модификаторы ниже к КД этой записи (бафф/дебафф и навык, только цель).
Aura (or entry) the modifier counts for; stacks are read from the target.	Аура (или запись), по которой считается модификатор; стаки читаются с цели.
Avoid TrackThatPlease	Не наезжать на TrackThatPlease
Base CD: %s s	Базовый КД: %s с
Base CD: -	Базовый КД: -
Base cooldown of the entry, seconds (the Cooldown field).	Базовый КД записи в секундах (поле Cooldown).
Buff debug mode disabled.	Режим отладки баффов выключен.
Buff debug mode enabled. Buff IDs will be displayed in chat.	Режим отладки баффов включён. ID баффов будут выводиться в чат.
Buff debug mode is disabled. Enable it in settings.	Режим отладки баффов выключен. Включите его в настройках.
Buff journal: every buff/debuff seen while Debug is ON, active and faded, newest first.	Журнал баффов: все баффы/дебаффы, увиденные при Debug: ON, активные и снятые, сначала новые.
Buff lists refreshed after import	Списки баффов обновлены после импорта
Buff log	Журнал баффов
Buff log cleared	Журнал баффов очищен
Buff, debuff or skill ID (a name from Custom entries also works). Type to filter, Enter or Add to track it.	ID баффа, дебаффа или навыка (подойдёт и имя из пользовательских записей). Вводите для фильтра, Enter или Add — отслеживать.
Buff/Debuff	Бафф/Дебафф
Buff/debuff ID, e.g. 800004. Required for Buff/Debuff entries.	ID баффа/дебаффа, например 800004. Обязателен для записей Buff/Debuff.
Buffs seen: %s (active %s)	Баффов замечено: %s (активных %s)
CD %s s	КД %s с
CD/D %s: CD=%s D=%s	КД/Д %s: КД=%s Д=%s
Cancel	Отмена
Canvas %s	Канвас %s
Canvas model ready: playerpet=%s player=%s target=%s	Модель канвасов готова: playerpet=%s player=%s target=%s
Canvas:	Канвас:
Canvas: %s	Канвас: %s
Canvas: one independent icon panel. A unit can own several canvases.	Канвас: одна независимая панель иконок. У юнита может быть несколько канвасов.
Canvases	Канвасы
Clear log	Очистить лог
Clear the %s of the selected unit.	Очистить %s выбранного юнита.
Close	Закрыть
Close the Record window.	Закрыть окно Record.
Close the icon search without changing the icon.	Закрыть поиск иконки, не меняя её.
Close the settings window (Esc).	Закрыть окно настроек (Esc).
Close the window (Esc).	Закрыть окно (Esc).
Close without deleting.	Закрыть без удаления.
Close without renaming.	Закрыть без переименования.
Close without saving.	Закрыть без сохранения.
Columns:	Столбцы:
Condition	Условие
Condition: %s (click to toggle). On target counts only while the aura is up.	Условие: %s (нажмите, чтобы переключить). On target учитывается, только пока аура висит.
Configuration imported from file - window closed	Конфигурация импортирована из файла - окно закрыто
Configuration imported successfully	Конфигурация успешно импортирована
Configuration saved to file: %s	Конфигурация сохранена в файл: %s
Containers not found!	Контейнеры не найдены!
Cooldown / Duration are seconds; 0 is valid. Icon is optional.	Cooldown / Duration в секундах; 0 допустим. Иконка необязательна.
Cooldown Buff Tracker	Трекер баффов и КД
Cooldown in seconds, 0 is allowed.	КД в секундах, 0 допустим.
Cooldown must be a number >= 0	КД должен быть числом >= 0
Cooldown:	КД:
Cooldown: %s s.	КД: %s с.
Could not read file: %s (put it into the CooldawnBuffTracker folder)	Не удалось прочитать файл: %s (положите его в папку CooldawnBuffTracker)
Could not save file: %s	Не удалось сохранить файл: %s
Countdown text colour. Click to open the palette.	Цвет текста таймера. Нажмите, чтобы открыть палитру.
Countdown text of the selected canvas.	Текст обратного отсчёта выбранного канваса.
Create the entry with these values and track it on the current canvas.	Создать запись с этими значениями и отслеживать её на текущем канвасе.
Custom entries:	Пользовательские записи:
Custom entries: ID, name, cooldown and duration used by the tracked list on every unit.	Пользовательские записи: ID, имя, КД и длительность, которые использует список отслеживания на всех юнитах.
Debug mode already initialized, skipping.	Режим отладки уже инициализирован, пропускаю.
Debug: OFF	Отладка: ВЫКЛ
Debug: ON	Отладка: ВКЛ
Debug: print buff IDs, combat-log details and the buff journal to chat; shows Record. Current: %s.	Отладка: печатать ID баффов, детали боевого лога и журнал баффов в чат; показывает Record. Сейчас: %s.
Delete	Удалить
Delete canvas	Удалить канвас
Delete canvas "%s"?	Удалить канвас "%s"?
Delete preset %s. Cannot be undone.	Удалить пресет %s. Отменить нельзя.
Delete the selected canvas and untrack its entries (asks first).	Удалить выбранный канвас и снять его записи с отслеживания (спросит подтверждение).
Delete this canvas and untrack the entries it holds. Cannot be undone.	Удалить этот канвас и снять с отслеживания его записи. Отменить нельзя.
Delete this custom entry and remove it from tracking on every unit.	Удалить эту пользовательскую запись и снять её с отслеживания на всех юнитах.
Donate EthereumX (ETX):	Донат EthereumX (ETX):
Donate USDT ERC20:	Донат USDT ERC20:
Donate USDT SOL:	Донат USDT SOL:
Donate USDT TON:	Донат USDT TON:
Donate USDT TRC20:	Донат USDT TRC20:
Donation address. Click the field, select it and copy with Ctrl+C.	Адрес для доната. Нажмите на поле, выделите и скопируйте через Ctrl+C.
Down	Вниз
Drag to move the window.	Перетащите, чтобы переместить окно.
Draw an additional compact overlay at the target's screen position. It does not hide the floating canvas; use Hide target canvas for that.	Рисовать дополнительный компактный оверлей у экранной позиции цели. Плавающий канвас он не скрывает — для этого есть Hide target canvas.
Dump scan started...	Скан дампа запущен...
Duration in seconds, 0 is allowed (Buff/Debuff only).	Длительность в секундах, 0 допустим (только бафф/дебафф).
Duration must be a number >= 0	Длительность должна быть числом >= 0
Duration:	Длительность:
Duration: %s s.	Длительность: %s с.
EXPORT - save your current setup to a file:	ЭКСПОРТ - сохранить текущую настройку в файл:
Edit	Изменить
Edit the Mount (pet) panel settings.	Настройки панели Mount (маунт).
Edit the Player panel settings.	Настройки панели Player.
Edit the Target panel settings, including the target overlay.	Настройки панели Target, включая оверлей цели.
Edit this entry: cooldown, duration, spell or mana, icon and effective CDs.	Изменить запись: КД, длительность, spell или ману, иконку и эффективные КД.
Effective CDs	Эффективные КД
Effective cooldown right now: max(0, base - flat) x (1 - percent / 100). '(no target)' means no aura snapshot, so only Always modifiers count.	Эффективный КД сейчас: max(0, base - flat) x (1 - percent / 100). '(no target)' означает, что снимка аур нет, поэтому считаются только модификаторы Always.
Effective now: %s	Эффективно сейчас: %s
Effective now: -	Эффективно сейчас: -
Empty preset name	Пустое имя пресета
Enable user-defined cooldown modifiers for this entry (target only).	Включить пользовательские модификаторы КД для этой записи (только цель).
Enter the name of the config file first	Сначала введите имя файла конфигурации
Entries drawn on the selected canvas of this unit. Up/Down change their order, Remove untracks them.	Записи, нарисованные на выбранном канвасе этого юнита. Up/Down меняют порядок, Remove снимает с отслеживания.
Entries in the current tab; buffs also show how many are active.	Записи на текущей вкладке; у баффов показано, сколько активно.
Entry ID (tracking key): %s.	ID записи (ключ отслеживания): %s.
Entry icon. Click to pick one from the buff dump; optional.	Иконка записи. Нажмите, чтобы выбрать из дампа баффов; необязательно.
Entry type, fixed at creation. Delete and re-create the entry to change it. Buff/Debuff has an aura, Skill is read from the combat log, Mana skill from pet mana.	Тип задаётся при создании. Чтобы изменить тип, удалите и создайте запись заново. У баффа/дебаффа есть аура, навык читается из боевого лога, навык маунта — по мане питомца.
Entry: cooldown / duration	Запись: КД / длительность
Error creating canvases for %s	Ошибка создания канвасов для %s
Error: %s	Ошибка: %s
Error: '%s' not found - add it as a custom buff first	Ошибка: '%s' не найдено - сначала добавьте это как пользовательскую запись
Error: Buff already tracked or error occurred	Ошибка: бафф уже отслеживается или произошла ошибка
Error: Configuration must be a table	Ошибка: конфигурация должна быть таблицей
Error: Custom buff at index %s is not a table	Ошибка: пользовательская запись с индексом %s не является таблицей
Error: Custom buff at index %s missing required fields	Ошибка: у пользовательской записи с индексом %s нет обязательных полей
Error: Failed to get current settings	Ошибка: не удалось получить текущие настройки
Error: ID, name, cooldown and duration are required	Ошибка: нужны ID, имя, КД и длительность
Error: Invalid JSON format	Ошибка: неверный формат JSON
Error: Missing required fields (customBuffs, trackedBuffs)	Ошибка: отсутствуют обязательные поля (customBuffs, trackedBuffs)
Error: Missing trackedBuffs fields (playerpet, player, target)	Ошибка: отсутствуют поля trackedBuffs (playerpet, player, target)
Error: cooldown must be 0 or more	Ошибка: КД должен быть 0 или больше
Error: customBuffs and trackedBuffs must be tables	Ошибка: customBuffs и trackedBuffs должны быть таблицами
Error: duration must be 0 or more	Ошибка: длительность должна быть 0 или больше
Error: enter a buff ID or the skill name	Ошибка: введите ID баффа или имя навыка
Error: entry with this ID already exists	Ошибка: запись с таким ID уже есть
Error: name, cooldown, mana cost and mount name are required	Ошибка: нужны имя, КД, стоимость маны и имя маунта
Error: spell name and cooldown are required	Ошибка: нужны имя навыка и КД
Error: the last canvas cannot be deleted	Ошибка: последний канвас удалить нельзя
Error: trackedBuffs.%s contains non-number at index %s	Ошибка: trackedBuffs.%s содержит не число по индексу %s
Error: trackedBuffs.%s is not a table	Ошибка: trackedBuffs.%s не является таблицей
Export the whole configuration to a file or import a received one.	Экспортировать всю конфигурацию в файл или импортировать полученную.
Failed to create settings window!	Не удалось создать окно настроек!
Failed to delete preset	Не удалось удалить пресет
Failed to encode configuration: %s	Не удалось закодировать конфигурацию: %s
Failed to get settings for export	Не удалось получить настройки для экспорта
Failed to load buff_helper.lua, using placeholder	Не удалось загрузить buff_helper.lua, использую заглушку
Failed to load buffs_to_track.lua, using settings	Не удалось загрузить buffs_to_track.lua, использую настройки
Failed to load preset	Не удалось загрузить пресет
Failed to read settings	Не удалось прочитать настройки
Failed to write config file: %s	Не удалось записать файл конфигурации: %s
Failed to write file	Не удалось записать файл
Failed: %s	Не удалось: %s
File has an unexpected format	Файл неожиданного формата
File name (file must be in the CooldawnBuffTracker folder):	Имя файла (файл должен лежать в папке CooldawnBuffTracker):
File name inside the CooldawnBuffTracker folder; the extension is optional.	Имя файла внутри папки CooldawnBuffTracker; расширение необязательно.
Filter by buff or skill name (English names). An empty field lists the whole dump.	Фильтр по имени баффа или навыка (английские имена). Пустое поле показывает весь дамп.
Flat	Плоский
Flat = seconds, Percent = %, Reset = zero the timer when the aura appears.	Flat = секунды, Percent = %, Reset = обнулить таймер при появлении ауры.
Flat modifiers counted right now, in seconds. Applied first, multiplied by aura stacks.	Плоские модификаторы, посчитанные сейчас, в секундах. Применяются первыми, умножаются на стаки ауры.
Flat total: %s	Плоско всего: %s
Flat total: -	Плоско всего: -
Font size:	Размер шрифта:
Found: %s (click a row to apply the icon)	Найдено: %s (нажмите строку, чтобы применить иконку)
Gap to the TrackThatPlease row, px (0-40).	Зазор до ряда TrackThatPlease, px (0-40).
Gap:	Зазор:
Grid (cols x rows):	Сетка (столбцы x строки):
Grid rows (1-10). Applies on Enter.	Строки сетки (1-10). Применяется по Enter.
Grid: icons per row, number of rows, the cap and the vertical gap.	Сетка: иконок в ряду, число рядов, лимит и вертикальный отступ.
Helpers module not loaded, using basic settings	Модуль helpers не загружен, использую базовые настройки
Hide every floating target canvas. Buff data keeps running and the Target Overlay still draws when it is on.	Скрыть все плавающие канвасы цели. Данные баффов продолжают идти, а Target Overlay рисуется, пока он включён.
Hide target canvas	Скрывать канвас цели
Horizontal gap between icons, px (0-40). Applies on Enter.	Горизонтальный отступ между иконками, px (0-40). Применяется по Enter.
ID/name:	ID/имя:
ID:	ID:
IMPORT - load a config you received	ИМПОРТ - загрузить полученный конфиг
Icon layout of the selected canvas: size, spacing, label and grid.	Раскладка иконок выбранного канваса: размер, отступ, подпись и сетка.
Icon position	Позиция иконок
Icon search	Поиск иконки
Icon settings	Настройки иконок
Icon size in pixels (16-64). Applies on Enter.	Размер иконки в пикселях (16-64). Применяется по Enter.
Icon size of the overlay, px (12-64).	Размер иконок оверлея, px (12-64).
Icon size:	Размер иконки:
Icon spacing:	Отступ иконок:
Icons per overlay row (1-12). Extra icons wrap downwards.	Иконок в ряду оверлея (1-12). Лишние переносятся вниз.
Icons per row (1-20). Applies on Enter.	Иконок в ряду (1-20). Применяется по Enter.
Import / Export Configuration	Импорт / Экспорт конфигурации
Import failed: configuration must be a table	Импорт не удался: конфигурация должна быть таблицей
Import failed: could not read the current settings	Импорт не удался: не удалось прочитать текущие настройки
Import failed: custom entry at index %s is not a table	Импорт не удался: пользовательская запись с индексом %s не является таблицей
Import failed: custom entry at index %s missing required fields	Импорт не удался: у пользовательской записи с индексом %s нет обязательных полей
Import failed: customBuffs and trackedBuffs must be tables	Импорт не удался: customBuffs и trackedBuffs должны быть таблицами
Import failed: invalid JSON format - %s	Импорт не удался: неверный формат JSON - %s
Import failed: missing required fields	Импорт не удался: отсутствуют обязательные поля
Import failed: missing trackedBuffs fields	Импорт не удался: отсутствуют поля trackedBuffs
Import failed: trackedBuffs.%s contains a non-number at index %s	Импорт не удался: trackedBuffs.%s содержит не число по индексу %s
Import failed: trackedBuffs.%s is not a table	Импорт не удался: trackedBuffs.%s не является таблицей
Import field is empty - paste a configuration into the lower field first	Поле импорта пустое - сначала вставьте конфигурацию в нижнее поле
Import from file failed: %s	Импорт из файла не удался: %s
Import from file: no file name entered	Импорт из файла: имя файла не введено
Import/Export	Импорт/Экспорт
Import: the Import field is empty - paste a configuration into the lower field first	Импорт: поле импорта пустое - сначала вставьте конфигурацию в нижнее поле
Interface language: the whole UI, every hover tooltip and all chat messages switch at once. The settings window rebuilds; no /reload needed.	Язык интерфейса: весь UI, все подсказки при наведении и все сообщения чата переключаются сразу. Окно настроек пересобирается; /reload не нужен.
Invalid buff ID	Неверный ID баффа
Invalid spell name	Неверное имя навыка
Keep the target overlay above TrackThatPlease's target row. Anchors to its real target canvas (targetBuffCanvas) when it can be found, otherwise places the row with targetBuffVerticalOffset, targetIconSize and the UI scale. Turn off to use the canvas offsets instead.	Держать оверлей цели над рядом цели TrackThatPlease. Прикрепляется к его настоящему канвасу цели (targetBuffCanvas), если он найден, иначе ставит ряд по targetBuffVerticalOffset, targetIconSize и масштабу UI. Выключите, чтобы ставить оверлей по смещениям канваса.
Label color:	Цвет названий:
Language	Язык
Language changed to %s	Язык изменён на %s
Language: %s	Язык: %s
Learned for this target (+%s%%)	Выучено для этой цели (+%s%%)
Load	Загрузить
Load config from file	Загрузить конфиг из файла
Load preset %s: position, size, colours and tracked entries.	Загрузить пресет %s: позиция, размер, цвета и отслеживаемые записи.
Loading CooldawnBuffTracker %s by %s	Загрузка CooldawnBuffTracker %s от %s
Lock: OFF	Блок: ВЫКЛ
Lock: ON	Блок: ВКЛ
Lock: ON disables dragging this panel with the mouse. Current: %s.	Блок: ВКЛ запрещает перетаскивание этой панели мышью. Сейчас: %s.
Log skills	Журнал навыков
Mana %s	Мана %s
Mana cost must be > 0	Стоимость маны должна быть > 0
Mana cost of the mount skill, used to detect the spend (Mana skill only).	Стоимость маны навыка маунта, по ней определяется трата (только навык маунта).
Mana skill	Навык маунта
Mana skill: mount skill tracked by the pet's mana spend. Fields: Name, Cooldown, Mana, Mount, icon.	Навык маунта: отслеживается по трате маны питомца. Поля: Name, Cooldown, Mana, Mount, иконка.
Mana:	Мана:
Matches for the current query. Click a row to apply its icon.	Совпадения по текущему запросу. Нажмите строку, чтобы применить иконку.
Max icons drawn on this canvas (1 to Columns x Rows). Applies on Enter.	Максимум иконок на канвасе (1 до Столбцы x Строки). Применяется по Enter.
Max icons:	Макс. иконок:
Mir OFF	Mir ВЫКЛ
Mir ON	Mir ВКЛ
Mirror this player aura on the Target panel (buff/debuff only). Current: %s.	Зеркалить эту ауру игрока на панели Target (только бафф/дебафф). Сейчас: %s.
Modifier source: %s.	Источник модификатора: %s.
Modifier source: buff ID, name or spell of a custom entry. Its aura is checked on the target.	Источник модификатора: ID, имя или spell пользовательской записи. Его аура проверяется на цели.
Modifiers	Модификаторы
Mount	Маунт
Mount %s	Маунт %s
Mount buff list updated: was %s, now %s	Список баффов маунта обновлён: было %s, стало %s
Mount name is required	Нужно имя маунта
Mount name the skill belongs to (Mana skill only).	Имя маунта, которому принадлежит навык (только навык маунта).
Mount:	Маунт:
Move entry to canvas	Перенос записи на канвас
Move the entry to this canvas.	Перенести запись на этот канвас.
Move this entry one place down inside the canvas.	Опустить запись на одну позицию вниз внутри канваса.
Move this entry one place up inside the canvas.	Поднять запись на одну позицию вверх внутри канваса.
Move this entry to another canvas of the same unit.	Перенести запись на другой канвас этого же юнита.
Mv	Перенос
NOT saved (api.File unavailable)	НЕ сохранено (api.File недоступен)
Name for the new preset, up to 40 characters. Must be unique.	Имя нового пресета, до 40 символов. Должно быть уникальным.
Name is required	Нужно имя
Name label colour under the icons. Click to open the palette.	Цвет названия под иконками. Нажмите, чтобы открыть палитру.
Name shown on the canvas instead of the ID.	Имя на канвасе вместо ID.
Name shown on the canvas: %s.	Имя на канвасе: %s.
Name:	Название:
Native frame display	Показ на нативных фреймах
New canvas name, up to 24 characters. Enter saves.	Новое имя канваса, до 24 символов. Enter сохраняет.
New preset name:	Имя нового пресета:
Next page of custom entries.	Следующая страница пользовательских записей.
Next page of presets.	Следующая страница пресетов.
Next page of results.	Следующая страница результатов.
Next page of tracked entries.	Следующая страница отслеживаемых записей.
Next page.	Следующая страница.
No active buffs	Активных баффов нет
No active debuffs	Активных дебаффов нет
No custom entries yet	Пользовательских записей пока нет
No presets saved	Сохранённых пресетов нет
No target selected	Цель не выбрана
Not learned	Не выучено
Nothing found. Press Scan dump or change the query.	Ничего не найдено. Нажмите Scan dump или измените запрос.
Nothing tracked yet	Пока ничего не отслеживается
OFF	ВЫКЛ
ON	ВКЛ
On target	На цели
On target = only while the aura is on the target; Always = always counts.	On target = только пока аура на цели; Always = считается всегда.
Open the support window (donation addresses).	Открыть окно поддержки (адреса для донатов).
Open the support window with the donation addresses.	Открыть окно поддержки с адресами для донатов.
Overlay X offset from the target's anchor (ignored while Avoid TrackThatPlease is on).	Смещение X оверлея от якоря цели (игнорируется при включённом Avoid TrackThatPlease).
Overlay X offset from the target's anchor, px.	Смещение X оверлея от якоря цели, px.
Overlay Y offset from the target's anchor, px (negative = above).	Смещение Y оверлея от якоря цели, px (отрицательное = выше).
Overlay around target	Оверлей вокруг цели
Overlay icon size, px (12-64).	Размер иконки оверлея, px (12-64).
Page %s - 7 presets per page.	Страница %s - 7 пресетов на странице.
Page %s - 8 entries per page.	Страница %s - 8 записей на странице.
Page %s - 9 entries per page.	Страница %s - 9 записей на странице.
Page %s - 9 icons per page.	Страница %s - 9 иконок на странице.
Panel X on screen, px from the left edge (negative values are allowed).	X панели на экране, px от левого края (отрицательные значения допустимы).
Panel Y on screen, px from the top edge (negative values are allowed).	Y панели на экране, px от верхнего края (отрицательные значения допустимы).
Panel position on screen, in pixels from the top-left corner.	Позиция панели на экране в пикселях от верхнего левого угла.
Per row:	В ряду:
Percent	Процент
Percent modifiers counted right now plus the learned Smart %, added together. Applied second.	Процентные модификаторы, посчитанные сейчас, плюс выученный Smart %, вместе. Применяются вторыми.
Percent total: %s	Процент всего: %s
Percent total: -	Процент всего: -
Place the overlay above TrackThatPlease's target row (anchored to its row when it can be found).	Ставить оверлей над рядом цели TrackThatPlease (при найденном ряде — якорем к нему).
Player	Игрок
Player buff list updated: was %s, now %s	Список баффов игрока обновлён: было %s, стало %s
Position X:	Позиция X:
Position Y:	Позиция Y:
Potential: %s s	Потенциал: %s с
Potential: -	Потенциал: -
Potential: every modifier counted with stacks 1 and auras assumed up - the best case for this build.	Потенциал: каждый модификатор с 1 стаком и все ауры считаются висящими - лучший случай для этой сборки.
Preset %s%s: Load applies its layout to all units, Delete removes it.	Пресет %s%s: Load применяет его раскладку ко всем юнитам, Delete удаляет.
Preset already exists: %s	Пресет уже существует: %s
Preset currently applied to all three units.	Пресет, применённый сейчас ко всем трём юнитам.
Preset deleted: %s	Пресет удалён: %s
Preset loaded: %s	Пресет загружен: %s
Preset name cannot be empty	Имя пресета не может быть пустым
Preset not found	Пресет не найден
Preset not found: %s	Пресет не найден: %s
Preset saved: %s	Пресет сохранён: %s
Presets	Пресеты
Presets *	Пресеты *
Previous page of custom entries.	Предыдущая страница пользовательских записей.
Previous page of presets.	Предыдущая страница пресетов.
Previous page of results.	Предыдущая страница результатов.
Previous page of tracked entries.	Предыдущая страница отслеживаемых записей.
Previous page.	Предыдущая страница.
Re-apply the active preset %s.	Применить активный пресет %s заново.
Read the file and apply it: replaces custom entries, tracked lists and unit layouts.	Прочитать файл и применить: заменяет пользовательские записи, списки отслеживания и раскладки юнитов.
Received buff list update event	Получено событие обновления списка баффов
Record (Debug)	Record (Отладка)
Record window (needs Debug: ON): buffs seen and skills from the combat log, with one-click Add.	Окно Record (нужен Debug: ON): увиденные баффы и навыки из боевого лога, добавление одним кликом.
Reference	Справка
Remove	Убрать
Remove this modifier from the entry.	Убрать этот модификатор из записи.
Rename	Переименовать
Rename canvas	Переименовать канвас
Rename the selected canvas (up to 24 characters).	Переименовать выбранный канвас (до 24 символов).
Repeated error creating canvases for %s	Повторная ошибка создания канвасов для %s
Rescan dump	Пересканировать дамп
Reset	Сброс
Row spacing:	Отступ строк:
Rows:	Строки:
Save	Сохранить
Save current	Сохранить текущие
Save my config to a file	Сохранить мой конфиг в файл
Save the current layout as a preset, load or delete presets.	Сохранить текущую раскладку как пресет, загрузить или удалить пресеты.
Save the current layout of all units (position, size, colours, grid, tracked entries) as a preset.	Сохранить текущую раскладку всех юнитов (позиция, размер, цвета, сетка, отслеживаемые записи) как пресет.
Save the entry and refresh both lists and the panels.	Сохранить запись и обновить оба списка и панели.
Save the new name and rebuild the panels.	Сохранить новое имя и пересобрать панели.
Saved	Сохранено
Saved presets:	Сохранённые пресеты:
Saved to: %s	Сохранено в: %s
Scan dump	Сканировать дамп
Scan started... the database will refresh when done	Скан запущен... база обновится по завершении
Scan the client buff table again and rebuild the icon/name dump.	Снова просканировать таблицу баффов клиента и пересобрать дамп иконок/имён.
Scan the client buff table and rebuild the icon dump (takes a moment).	Просканировать таблицу баффов клиента и пересобрать дамп иконок (займёт момент).
Seconds or percent; multiplied by the aura's stack count (1 if none).	Секунды или проценты; умножается на число стаков ауры (1, если их нет).
Select address above and copy it manually (Ctrl+C)	Выделите адрес выше и скопируйте его вручную (Ctrl+C)
Select canvas:	Выберите канвас:
Select language:	Выберите язык:
Show label: OFF	Подписи: ВЫКЛ
Show label: ON	Подписи: ВКЛ
Show the %s journal.	Показать журнал %s.
Show the entry name under each icon of this canvas. Current: %s.	Показывать имя записи под каждой иконкой этого канваса. Сейчас: %s.
Show this canvas in the settings column (entries and layout).	Показать этот канвас в колонке настроек (записи и раскладка).
Size:	Размер:
Skill	Навык
Skill log cleared	Журнал навыков очищен
Skill: tracked from the combat log by its spell name. Fields: Name, Cooldown, Spell, icon.	Навык: отслеживается по имени в боевом логе. Поля: Name, Cooldown, Spell, иконка.
Skills seen in combat log: %s	Навыков в боевом логе: %s
Skills seen in the combat log for the selected unit, newest first.	Навыки из боевого лога для выбранного юнита, сначала новые.
Smart	Smart
Smart %:	Smart %:
Smart %: extra reduction learned for this target when the skill returns earlier than predicted (0-100).	Smart %: дополнительное сокращение, выученное для этой цели, когда навык возвращается раньше предсказанного (0-100).
Smart learning state for the current target: learned after an early re-use, never learned otherwise.	Состояние smart для текущей цели: выучивается после раннего повторного применения, иначе остаётся невыученным.
Smart reduction % must be a number 0..100	Smart-сокращение % должно быть числом 0..100
Source	Источник
Space between our overlay row and TrackThatPlease's row, px.	Зазор между нашим рядом оверлея и рядом TrackThatPlease, px.
Spell %s	Spell %s
Spell name exactly as the combat log reports it (Skill only).	Имя навыка точно как в боевом логе (только навык).
Spell name is required	Нужно имя навыка
Spell:	Spell:
Spell: OFF	Spell: ВЫКЛ
Spell: ON	Spell: ВКЛ
Start typing a skill or buff name...	Начните вводить название навыка или баффа...
Stop tracking this entry on every canvas of this unit. The custom entry stays in the list.	Снять запись с отслеживания на всех канвасах этого юнита. Пользовательская запись остаётся в списке.
Support	Поддержать
Support the Addon Developer	Поддержать разработчика аддона
Switch the canvas edited below. Shown: %s.	Переключить канвас, редактируемый ниже. Показан: %s.
Switch the interface, every hover tooltip and all chat messages to this language.	Переключить интерфейс, все подсказки и все сообщения чата на этот язык.
TTP canvas found: %s	Канвас TTP найден: %s
TTP canvas not found, fallback: %s	Канвас TTP не найден, запасной вариант: %s
Target	Цель
Target cache cleaned: %s	Кэш цели очищен: %s
Target display modes: overlay at the target's screen position, hide the floating canvas, avoid TrackThatPlease.	Режимы показа цели: оверлей у экранной позиции цели, скрыть плавающий канвас, не наезжать на TrackThatPlease.
Target only. Stacks are read from the target's aura (1 if none).	Только цель. Стаки читаются из ауры цели (1, если её нет).
Text color:	Цвет текста:
Thank you for supporting the development!	Спасибо за поддержку разработки!
Thank you for your hard work!	Спасибо за вашу работу!
Timer font size in pixels (8-40). Applies on Enter.	Размер шрифта таймера в пикселях (8-40). Применяется по Enter.
Timer settings	Настройки таймера
Track this ID/name on the current unit and canvas.	Отслеживать этот ID/имя на текущем юните и канвасе.
Tracked entries:	Отслеживаемые записи:
Tracking key of this entry; it cannot be changed here.	Ключ отслеживания этой записи; здесь его изменить нельзя.
Type	Тип
Type:	Тип:
Type: %s. Click to cycle Flat -> Percent -> Reset.	Тип: %s. Нажмите, чтобы переключить Flat -> Percent -> Reset.
UI initialization for %s: %s	Инициализация UI для %s: %s
Unconditional %s	Без источника %s
Unit whose journal is listed below.	Юнит, чей журнал показан ниже.
Unit whose panel is edited below. Every unit has its own canvases and tracked list.	Юнит, чья панель редактируется ниже. У каждого юнита свои канвасы и свой список записей.
Unit:	Юнит:
Unknown	Неизвестно
Up	Вверх
Use this canvas.	Использовать этот канвас.
Use this custom entry.	Использовать эту запись.
Use this custom entry: %s.	Использовать эту запись: %s.
Value	Значение
Value for an unconditional modifier: seconds for +Flat, percent for +Percent (0 or more).	Значение для безусловного модификатора: секунды для +Flat, проценты для +Percent (0 и больше).
Value: %s %%.	Значение: %s %%.
Value: %s s.	Значение: %s с.
Vertical gap between grid rows, px (0-40). Applies on Enter.	Вертикальный отступ между рядами сетки, px (0-40). Применяется по Enter.
Write the whole configuration (custom entries, tracked lists, layouts) to a JSON file in the addon folder.	Записать всю конфигурацию (пользовательские записи, списки отслеживания, раскладки) в JSON-файл в папке аддона.
active	активен
always value must be a number >= 0	значение always должно быть числом >= 0
aura dump -> %s	дамп аур -> %s
aura dump: write failed	дамп аур: запись не удалась
buff dump: %s buffs loaded from %s	дамп баффов: загружено %s баффов из %s
buff dump: %s buffs, %s skill icons	дамп баффов: %s баффов, %s иконок навыков
buff dump: %s buffs, %s; tables=%s named=%s errors=%s%s	дамп баффов: %s баффов, %s; tables=%s named=%s errors=%s%s
buff dump: '%s' -> id=%s path=%s (entries updated: %s)	дамп баффов: '%s' -> id=%s path=%s (обновлено записей: %s)
buff dump: '%s' not found	дамп баффов: '%s' не найден
buff journal	журнал баффов
buff scan: dumping all buffs%s (1..50000, 8000000..8001000)	скан баффов: выгружаю все баффы%s (1..50000, 8000000..8001000)
cast %s by %s (%sms)	каст %s от %s (%s мс)
custom entry removed: %s	пользовательская запись удалена: %s
custom: id=%s name=%s spell=%s CD=%s D=%s	custom: id=%s name=%s spell=%s CD=%s D=%s
effective CD: reset '%s' zeroed %s on target %s	эффективный КД: сброс '%s' обнулил %s на цели %s
effective CD: smart %.1f%% learned for %s on target %s (applied after %.2f s < %.2f s)	эффективный КД: smart %.1f%% выучен для %s на цели %s (сработало через %.2f с < %.2f с)
effective CD: target %s class %s -> %s, smart reset for this target	эффективный КД: у цели %s класс %s -> %s, smart сброшен для этой цели
enter a buff ID or name	введите ID или имя баффа
entry %s: type=%s CD=%s D=%s%s	запись %s: type=%s CD=%s D=%s%s
faded	снят
hide	скрыть
icon from dump: %s -> %s	иконка из дампа: %s -> %s
icon learned for spell %s: %s	иконка выучена для навыка %s: %s
icon lookup id=%s -> path=%s name=%s%s	поиск иконки id=%s -> path=%s name=%s%s
icon picked: %s -> %s	иконка выбрана: %s -> %s
icon: no spellId in event for '%s'	иконка: в событии нет spellId для '%s'
invalid modifier source	неверный источник модификатора
mana cast %s cost=%s spend=%.1f regen=%.1f mount=%s	каст маны %s cost=%s spend=%.1f regen=%.1f mount=%s
mana drop %.1f (regen %.1f) — no match; pet='%s'; mount-blocked=%d cd-blocked=%d; entries: %s	падение маны %.1f (regen %.1f) — нет совпадения; pet='%s'; mount-blocked=%d cd-blocked=%d; записи: %s
modifier %s: value must be a number >= 0	модификатор %s: значение должно быть числом >= 0
msg %s src=%s tgt=%s spell=%s id=%s	msg %s src=%s tgt=%s spell=%s id=%s
parsed: spellId=%s spellName=%s	разбор: spellId=%s spellName=%s
saved to buff_dump.tbl	сохранено в buff_dump.tbl
settings window rebuild failed: %s	не удалось пересобрать окно настроек: %s
show	показать
skill icon: %s	иконка навыка: %s
skill log	журнал навыков
timer %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s	таймер %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s
too many modifiers	слишком много модификаторов
updateVisibleItems not found!	updateVisibleItems не найден!
]==]
dict.zh = [==[
 (active)	 (当前)
 (no target)	 (无目标)
 (was %s)	 (原为 %s)
 + search '%s'	 + 搜索 '%s'
 | first error: %s	 | 首个错误: %s
%d. buff ID: %s	%d. 增益 ID: %s
%d. debuff ID: %s	%d. 减益 ID: %s
%s (id %s) - %s, seen %s time(s).	%s (ID %s) - %s，出现 %s 次。
%s (id %s) on canvas %s.	%s (ID %s)，画布 %s。
%s - %s. Click to apply this icon.	%s - %s。点击应用此图标。
%s - buff ID: %s, unit: %s	%s - 增益 ID: %s，单位: %s
%s - seen %s time(s) in the combat log.	%s - 战斗日志中出现 %s 次。
%s args: %s	%s 参数: %s
%s buff added for tracking: %s (%s)	%s 增益已加入追踪: %s (%s)
%s buff removed from tracking: %s	%s 增益已取消追踪: %s
%s tracked entries will be removed from this unit.	将从此单位移除 %s 个追踪条目。
'%s': cooldown recorded for %s (unit %s)	'%s': 已记录 %s 的冷却 (单位 %s)
'%s': no source in the event	'%s': 事件中没有来源
'%s': repeat trigger after %.1f s - ignored (window %s)	'%s': %.1f 秒后重复触发 - 已忽略 (窗口 %s)
'%s': self cast -> Player/Mount panels: %s	'%s': 自身施放 -> Player/Mount 面板: %s
'%s': self cast, but the buff is not tracked on Player/Mount	'%s': 自身施放，但该增益未在 Player/Mount 上追踪
'%s': source %s unknown, waiting for the first target	'%s': 来源 %s 未知，等待第一个目标
'%s': you are the current target -> recorded to Target	'%s': 你是当前目标 -> 已记录到 Target
(no target)	(无目标)
(set at creation, cannot be changed)	(创建时设定，无法更改)
* Mount	* 坐骑
* Player	* 玩家
* Target	* 目标
+Flat	+固定
+Flat: subtract N seconds, applied before the percentages.	+Flat: 减去 N 秒，在百分比之前应用。
+Percent	+百分比
+Percent: subtract N %, applied after all flat reductions.	+Percent: 减去 N %，在所有固定缩减之后应用。
Active	当前
Active buffs for %s (%d):	%s 的当前增益 (%d):
Active debuffs for %s (%d):	%s 的当前减益 (%d):
Active preset: %s	当前预设: %s
Active preset: None	当前预设: 无
Add	添加
Add a canvas: copies this layout and places the copy below it.	添加画布: 复制当前布局并把副本放在下方。
Add a custom entry: pick the type first, the fields below follow it, then Add entry.	添加自定义条目: 先选择类型，下方字段随类型变化，然后 Add entry。
Add custom entry:	添加自定义条目:
Add entry	添加条目
Add this entry to tracking on the current unit and canvas.	将条目加入当前单位与画布的追踪。
Add this source as a modifier (condition On target, type Flat, value 0).	将此来源添加为修正 (条件 On target，类型 Flat，值 0)。
Add to tracking on the current unit (creates a custom entry with a default CD/D when needed).	加入当前单位的追踪 (必要时创建默认 CD/D 的自定义条目)。
Add: buff -> custom entry + tracking. Skill -> custom entry with Spell filled.	Add: 增益 -> 自定义条目 + 追踪。技能 -> 已填 Spell 的条目。
Added skill: %s	已添加技能: %s
Added to %s	已添加到 %s
Added: %s	已添加: %s
Addon Options	插件选项
Already tracked (%s)	已在追踪 (%s)
Already tracked: %s	已在追踪: %s
Also fill the entry's Spell field with the picked buff name.	同时用所选增益名称填写条目的 Spell 字段。
Always	总是
Always:	总是:
Apply icon, grid, position and timer values. Enter inside a field applies it too.	应用图标、网格、位置和倒计时数值。在字段中按 Enter 也会应用。
Apply the modifiers below to this entry's cooldown (buff/debuff and skill, target only).	对此条目的冷却应用下方修正 (增益/减益与技能，仅目标)。
Aura (or entry) the modifier counts for; stacks are read from the target.	修正所依据的光环 (或条目)；层数从目标读取。
Avoid TrackThatPlease	避开 TrackThatPlease
Base CD: %s s	基础冷却: %s 秒
Base CD: -	基础冷却: -
Base cooldown of the entry, seconds (the Cooldown field).	条目的基础冷却(秒)，即 Cooldown 字段。
Buff debug mode disabled.	增益调试模式已关闭。
Buff debug mode enabled. Buff IDs will be displayed in chat.	增益调试模式已开启。增益 ID 会显示在聊天中。
Buff debug mode is disabled. Enable it in settings.	增益调试模式已关闭。请在设置中启用。
Buff journal: every buff/debuff seen while Debug is ON, active and faded, newest first.	增益日志: Debug 开启期间见到的所有增益/减益，包括激活和已结束的，最新在前。
Buff lists refreshed after import	导入后增益列表已刷新
Buff log	增益日志
Buff log cleared	增益日志已清空
Buff, debuff or skill ID (a name from Custom entries also works). Type to filter, Enter or Add to track it.	增益、减益或技能 ID (也可用自定义条目的名称)。输入以筛选，Enter 或 Add 开始追踪。
Buff/Debuff	增益/减益
Buff/debuff ID, e.g. 800004. Required for Buff/Debuff entries.	增益/减益 ID，例如 800004。Buff/Debuff 条目必填。
Buffs seen: %s (active %s)	已见增益: %s (当前 %s)
CD %s s	CD %s 秒
CD/D %s: CD=%s D=%s	CD/D %s: CD=%s D=%s
Cancel	取消
Canvas %s	画布 %s
Canvas model ready: playerpet=%s player=%s target=%s	画布模型就绪: playerpet=%s player=%s target=%s
Canvas:	画布:
Canvas: %s	画布: %s
Canvas: one independent icon panel. A unit can own several canvases.	画布: 一个独立的图标面板。一个单位可以有多个画布。
Canvases	画布
Clear log	清空日志
Clear the %s of the selected unit.	清空所选单位的%s。
Close	关闭
Close the Record window.	关闭 Record 窗口。
Close the icon search without changing the icon.	关闭图标搜索，不更改图标。
Close the settings window (Esc).	关闭设置窗口 (Esc)。
Close the window (Esc).	关闭窗口 (Esc)。
Close without deleting.	关闭但不删除。
Close without renaming.	关闭但不重命名。
Close without saving.	关闭但不保存。
Columns:	列:
Condition	条件
Condition: %s (click to toggle). On target counts only while the aura is up.	条件: %s (点击切换)。On target 仅在光环存在时计入。
Configuration imported from file - window closed	配置已从文件导入 - 窗口已关闭
Configuration imported successfully	配置导入成功
Configuration saved to file: %s	配置已保存到文件: %s
Containers not found!	未找到容器!
Cooldown / Duration are seconds; 0 is valid. Icon is optional.	Cooldown / Duration 以秒为单位；0 有效。图标可选。
Cooldown Buff Tracker	增益与冷却追踪
Cooldown in seconds, 0 is allowed.	冷却时间(秒)，0 有效。
Cooldown must be a number >= 0	冷却必须是不小于 0 的数字
Cooldown:	冷却:
Cooldown: %s s.	冷却: %s 秒。
Could not read file: %s (put it into the CooldawnBuffTracker folder)	无法读取文件: %s (请放入 CooldawnBuffTracker 文件夹)
Could not save file: %s	无法保存文件: %s
Countdown text colour. Click to open the palette.	倒计时文字颜色。点击打开调色板。
Countdown text of the selected canvas.	所选画布的倒计时文字。
Create the entry with these values and track it on the current canvas.	用这些值创建条目并在当前画布追踪。
Custom entries:	自定义条目:
Custom entries: ID, name, cooldown and duration used by the tracked list on every unit.	自定义条目: 所有单位的追踪列表使用的 ID、名称、冷却和持续时间。
Debug mode already initialized, skipping.	调试模式已初始化，跳过。
Debug: OFF	调试: 关
Debug: ON	调试: 开
Debug: print buff IDs, combat-log details and the buff journal to chat; shows Record. Current: %s.	调试: 将增益 ID、战斗日志细节和增益日志输出到聊天；显示 Record。当前: %s。
Delete	删除
Delete canvas	删除画布
Delete canvas "%s"?	删除画布 "%s"?
Delete preset %s. Cannot be undone.	删除预设 %s。无法撤销。
Delete the selected canvas and untrack its entries (asks first).	删除所选画布并取消其条目追踪 (会先确认)。
Delete this canvas and untrack the entries it holds. Cannot be undone.	删除此画布并取消其条目追踪。无法撤销。
Delete this custom entry and remove it from tracking on every unit.	删除此自定义条目并在所有单位取消追踪。
Donate EthereumX (ETX):	捐赠 EthereumX (ETX):
Donate USDT ERC20:	捐赠 USDT ERC20:
Donate USDT SOL:	捐赠 USDT SOL:
Donate USDT TON:	捐赠 USDT TON:
Donate USDT TRC20:	捐赠 USDT TRC20:
Donation address. Click the field, select it and copy with Ctrl+C.	捐赠地址。点击该字段，选中后用 Ctrl+C 复制。
Down	下移
Drag to move the window.	拖动以移动窗口。
Draw an additional compact overlay at the target's screen position. It does not hide the floating canvas; use Hide target canvas for that.	在目标的屏幕位置额外绘制一个紧凑叠加层。它不会隐藏浮动画布；要隐藏请使用 Hide target canvas。
Dump scan started...	扫描已开始...
Duration in seconds, 0 is allowed (Buff/Debuff only).	持续时间(秒)，0 有效 (仅增益/减益)。
Duration must be a number >= 0	持续时间必须是不小于 0 的数字
Duration:	持续时间:
Duration: %s s.	持续时间: %s 秒。
EXPORT - save your current setup to a file:	导出 - 将当前配置保存到文件:
Edit	编辑
Edit the Mount (pet) panel settings.	编辑 Mount (坐骑) 面板设置。
Edit the Player panel settings.	编辑 Player 面板设置。
Edit the Target panel settings, including the target overlay.	编辑 Target 面板设置，包括目标叠加层。
Edit this entry: cooldown, duration, spell or mana, icon and effective CDs.	编辑此条目: 冷却、持续时间、spell 或法力、图标和有效冷却。
Effective CDs	有效冷却
Effective cooldown right now: max(0, base - flat) x (1 - percent / 100). '(no target)' means no aura snapshot, so only Always modifiers count.	当前有效冷却: max(0, base - flat) x (1 - percent / 100)。'(no target)' 表示没有光环快照，因此只计入 Always 修正。
Effective now: %s	当前有效: %s
Effective now: -	当前有效: -
Empty preset name	预设名称为空
Enable user-defined cooldown modifiers for this entry (target only).	为此条目启用自定义冷却修正 (仅目标)。
Enter the name of the config file first	请先输入配置文件名
Entries drawn on the selected canvas of this unit. Up/Down change their order, Remove untracks them.	此单位所选画布上绘制的条目。Up/Down 调整顺序，Remove 取消追踪。
Entries in the current tab; buffs also show how many are active.	当前标签页的条目；增益还会显示多少个处于激活状态。
Entry ID (tracking key): %s.	条目 ID (追踪键): %s。
Entry icon. Click to pick one from the buff dump; optional.	条目图标。点击从增益转储中选择；可选。
Entry type, fixed at creation. Delete and re-create the entry to change it. Buff/Debuff has an aura, Skill is read from the combat log, Mana skill from pet mana.	类型在创建时固定。要更改类型，请删除并重新创建条目。增益/减益有光环，技能从战斗日志读取，坐骑技能根据宠物法力识别。
Entry: cooldown / duration	条目: 冷却 / 持续时间
Error creating canvases for %s	为 %s 创建画布时出错
Error: %s	错误: %s
Error: '%s' not found - add it as a custom buff first	错误: 找不到 '%s' - 请先将其添加为自定义条目
Error: Buff already tracked or error occurred	错误: 增益已在追踪或发生错误
Error: Configuration must be a table	错误: 配置必须是一个表
Error: Custom buff at index %s is not a table	错误: 索引 %s 的自定义条目不是表
Error: Custom buff at index %s missing required fields	错误: 索引 %s 的自定义条目缺少必填字段
Error: Failed to get current settings	错误: 无法获取当前设置
Error: ID, name, cooldown and duration are required	错误: 需要 ID、名称、冷却和持续时间
Error: Invalid JSON format	错误: JSON 格式无效
Error: Missing required fields (customBuffs, trackedBuffs)	错误: 缺少必填字段 (customBuffs, trackedBuffs)
Error: Missing trackedBuffs fields (playerpet, player, target)	错误: 缺少 trackedBuffs 字段 (playerpet, player, target)
Error: cooldown must be 0 or more	错误: 冷却必须不小于 0
Error: customBuffs and trackedBuffs must be tables	错误: customBuffs 与 trackedBuffs 必须是表
Error: duration must be 0 or more	错误: 持续时间必须不小于 0
Error: enter a buff ID or the skill name	错误: 请输入增益 ID 或技能名称
Error: entry with this ID already exists	错误: 该 ID 的条目已存在
Error: name, cooldown, mana cost and mount name are required	错误: 需要名称、冷却、法力消耗和坐骑名称
Error: spell name and cooldown are required	错误: 需要技能名称和冷却
Error: the last canvas cannot be deleted	错误: 无法删除最后一个画布
Error: trackedBuffs.%s contains non-number at index %s	错误: trackedBuffs.%s 的索引 %s 不是数字
Error: trackedBuffs.%s is not a table	错误: trackedBuffs.%s 不是表
Export the whole configuration to a file or import a received one.	将整个配置导出到文件，或导入收到的配置。
Failed to create settings window!	无法创建设置窗口!
Failed to delete preset	删除预设失败
Failed to encode configuration: %s	无法编码配置: %s
Failed to get settings for export	无法获取导出所需的设置
Failed to load buff_helper.lua, using placeholder	无法加载 buff_helper.lua，改用占位实现
Failed to load buffs_to_track.lua, using settings	无法加载 buffs_to_track.lua，改用设置
Failed to load preset	加载预设失败
Failed to read settings	无法读取设置
Failed to write config file: %s	无法写入配置文件: %s
Failed to write file	无法写入文件
Failed: %s	失败: %s
File has an unexpected format	文件格式不符
File name (file must be in the CooldawnBuffTracker folder):	文件名 (文件必须位于 CooldawnBuffTracker 文件夹):
File name inside the CooldawnBuffTracker folder; the extension is optional.	CooldawnBuffTracker 文件夹内的文件名；扩展名可选。
Filter by buff or skill name (English names). An empty field lists the whole dump.	按增益或技能名称筛选 (英文名)。空字段会列出整个转储。
Flat	固定
Flat = seconds, Percent = %, Reset = zero the timer when the aura appears.	Flat = 秒，Percent = %，Reset = 光环出现时将计时归零。
Flat modifiers counted right now, in seconds. Applied first, multiplied by aura stacks.	当前计入的固定修正(秒)。先应用，并乘以光环层数。
Flat total: %s	固定总计: %s
Flat total: -	固定总计: -
Font size:	字体大小:
Found: %s (click a row to apply the icon)	找到: %s (点击行应用图标)
Gap to the TrackThatPlease row, px (0-40).	与 TrackThatPlease 行的间距(像素，0-40)。
Gap:	间距:
Grid (cols x rows):	网格 (列 x 行):
Grid rows (1-10). Applies on Enter.	网格行数 (1-10)。按 Enter 应用。
Grid: icons per row, number of rows, the cap and the vertical gap.	网格: 每行图标数、行数、上限和垂直间距。
Helpers module not loaded, using basic settings	helpers 模块未加载，使用基础设置
Hide every floating target canvas. Buff data keeps running and the Target Overlay still draws when it is on.	隐藏所有浮动的目标画布。增益数据继续运行，叠加层开启时仍会绘制。
Hide target canvas	隐藏目标画布
Horizontal gap between icons, px (0-40). Applies on Enter.	图标之间的水平间距(像素，0-40)。按 Enter 应用。
ID/name:	ID/名称:
ID:	ID:
IMPORT - load a config you received	导入 - 加载收到的配置
Icon layout of the selected canvas: size, spacing, label and grid.	所选画布的图标布局: 大小、间距、标签和网格。
Icon position	图标位置
Icon search	图标搜索
Icon settings	图标设置
Icon size in pixels (16-64). Applies on Enter.	图标大小(像素，16-64)。按 Enter 应用。
Icon size of the overlay, px (12-64).	叠加层的图标大小(像素，12-64)。
Icon size:	图标大小:
Icon spacing:	图标间距:
Icons per overlay row (1-12). Extra icons wrap downwards.	每行叠加图标数 (1-12)。多余的换行向下。
Icons per row (1-20). Applies on Enter.	每行图标数 (1-20)。按 Enter 应用。
Import / Export Configuration	导入 / 导出配置
Import failed: configuration must be a table	导入失败: 配置必须是一个表
Import failed: could not read the current settings	导入失败: 无法读取当前设置
Import failed: custom entry at index %s is not a table	导入失败: 索引 %s 的自定义条目不是表
Import failed: custom entry at index %s missing required fields	导入失败: 索引 %s 的自定义条目缺少必填字段
Import failed: customBuffs and trackedBuffs must be tables	导入失败: customBuffs 与 trackedBuffs 必须是表
Import failed: invalid JSON format - %s	导入失败: JSON 格式无效 - %s
Import failed: missing required fields	导入失败: 缺少必填字段
Import failed: missing trackedBuffs fields	导入失败: 缺少 trackedBuffs 字段
Import failed: trackedBuffs.%s contains a non-number at index %s	导入失败: trackedBuffs.%s 的索引 %s 不是数字
Import failed: trackedBuffs.%s is not a table	导入失败: trackedBuffs.%s 不是表
Import field is empty - paste a configuration into the lower field first	导入字段为空 - 请先把配置粘贴到下方字段
Import from file failed: %s	从文件导入失败: %s
Import from file: no file name entered	文件导入: 未输入文件名
Import/Export	导入/导出
Import: the Import field is empty - paste a configuration into the lower field first	导入: 导入字段为空 - 请先把配置粘贴到下方字段
Interface language: the whole UI, every hover tooltip and all chat messages switch at once. The settings window rebuilds; no /reload needed.	界面语言: 整个界面、所有悬停提示和所有聊天消息会一起切换。设置窗口会重建；无需 /reload。
Invalid buff ID	无效的增益 ID
Invalid spell name	无效的技能名称
Keep the target overlay above TrackThatPlease's target row. Anchors to its real target canvas (targetBuffCanvas) when it can be found, otherwise places the row with targetBuffVerticalOffset, targetIconSize and the UI scale. Turn off to use the canvas offsets instead.	将目标叠加层保持在 TrackThatPlease 目标行上方。找到其真实目标画布 (targetBuffCanvas) 时直接锚定，否则用 targetBuffVerticalOffset、targetIconSize 和 UI 缩放放置。关闭后改用画布偏移。
Label color:	名称颜色:
Language	语言
Language changed to %s	语言已切换为 %s
Language: %s	语言: %s
Learned for this target (+%s%%)	已为此目标学习 (+%s%%)
Load	加载
Load config from file	从文件加载配置
Load preset %s: position, size, colours and tracked entries.	加载预设 %s: 位置、大小、颜色和追踪条目。
Loading CooldawnBuffTracker %s by %s	正在加载 CooldawnBuffTracker %s，作者 %s
Lock: OFF	锁定: 关
Lock: ON	锁定: 开
Lock: ON disables dragging this panel with the mouse. Current: %s.	锁定: 开 会禁止用鼠标拖动此面板。当前: %s。
Log skills	技能日志
Mana %s	法力 %s
Mana cost must be > 0	法力消耗必须 > 0
Mana cost of the mount skill, used to detect the spend (Mana skill only).	坐骑技能的法力消耗，用于识别消耗 (仅坐骑技能)。
Mana skill	坐骑技能
Mana skill: mount skill tracked by the pet's mana spend. Fields: Name, Cooldown, Mana, Mount, icon.	坐骑技能: 根据宠物法力消耗追踪。字段: Name、Cooldown、Mana、Mount、图标。
Mana:	法力:
Matches for the current query. Click a row to apply its icon.	当前查询的匹配项。点击行应用其图标。
Max icons drawn on this canvas (1 to Columns x Rows). Applies on Enter.	画布上最多图标数 (1 到 列 x 行)。按 Enter 应用。
Max icons:	最大图标:
Mir OFF	Mir 关
Mir ON	Mir 开
Mirror this player aura on the Target panel (buff/debuff only). Current: %s.	在 Target 面板镜像此玩家光环 (仅增益/减益)。当前: %s。
Modifier source: %s.	修正来源: %s。
Modifier source: buff ID, name or spell of a custom entry. Its aura is checked on the target.	修正来源: 自定义条目的增益 ID、名称或 spell。会在目标身上检查其光环。
Modifiers	修正
Mount	坐骑
Mount %s	坐骑 %s
Mount buff list updated: was %s, now %s	坐骑增益列表已更新: 原 %s，现 %s
Mount name is required	需要坐骑名称
Mount name the skill belongs to (Mana skill only).	技能所属的坐骑名称 (仅坐骑技能)。
Mount:	坐骑:
Move entry to canvas	将条目移到画布
Move the entry to this canvas.	将条目移到此画布。
Move this entry one place down inside the canvas.	在画布内将条目下移一位。
Move this entry one place up inside the canvas.	在画布内将条目上移一位。
Move this entry to another canvas of the same unit.	将条目移到同一单位的其他画布。
Mv	이동
NOT saved (api.File unavailable)	未保存 (api.File 不可用)
Name for the new preset, up to 40 characters. Must be unique.	新预设名称，最多 40 个字符。必须唯一。
Name is required	需要名称
Name label colour under the icons. Click to open the palette.	图标下方名称的颜色。点击打开调色板。
Name shown on the canvas instead of the ID.	在画布上显示的名称，替代 ID。
Name shown on the canvas: %s.	画布上的名称: %s。
Name:	名称:
Native frame display	原生框体显示
New canvas name, up to 24 characters. Enter saves.	新画布名称，最多 24 个字符。按 Enter 保存。
New preset name:	新预设名称:
Next page of custom entries.	下一页自定义条目。
Next page of presets.	下一页预设。
Next page of results.	下一页结果。
Next page of tracked entries.	下一页追踪条目。
Next page.	下一页。
No active buffs	没有激活的增益
No active debuffs	没有激活的减益
No custom entries yet	还没有自定义条目
No presets saved	没有已保存的预设
No target selected	未选择目标
Not learned	未学习
Nothing found. Press Scan dump or change the query.	没有找到。按 Scan dump 或修改查询。
Nothing tracked yet	还没有追踪任何条目
OFF	关
ON	开
On target	目标身上
On target = only while the aura is on the target; Always = always counts.	On target = 仅在目标身上有光环时；Always = 始终计入。
Open the support window (donation addresses).	打开支持窗口 (捐赠地址)。
Open the support window with the donation addresses.	打开带捐赠地址的支持窗口。
Overlay X offset from the target's anchor (ignored while Avoid TrackThatPlease is on).	叠加层相对目标锚点的 X 偏移 (开启 Avoid TrackThatPlease 时忽略)。
Overlay X offset from the target's anchor, px.	叠加层相对目标锚点的 X 偏移(像素)。
Overlay Y offset from the target's anchor, px (negative = above).	叠加层相对目标锚点的 Y 偏移(像素，负数 = 上方)。
Overlay around target	目标周围叠加层
Overlay icon size, px (12-64).	叠加层图标大小(像素，12-64)。
Page %s - 7 presets per page.	第 %s 页 - 每页 7 个预设。
Page %s - 8 entries per page.	第 %s 页 - 每页 8 个条目。
Page %s - 9 entries per page.	第 %s 页 - 每页 9 个条目。
Page %s - 9 icons per page.	第 %s 页 - 每页 9 个图标。
Panel X on screen, px from the left edge (negative values are allowed).	面板 X，距左边缘的像素 (允许负值)。
Panel Y on screen, px from the top edge (negative values are allowed).	面板 Y，距上边缘的像素 (允许负值)。
Panel position on screen, in pixels from the top-left corner.	面板在屏幕上的位置，从左上角算起的像素。
Per row:	每行:
Percent	百分比
Percent modifiers counted right now plus the learned Smart %, added together. Applied second.	当前计入的百分比修正加上已学习的 Smart %，合并计算。其次应用。
Percent total: %s	百分比总计: %s
Percent total: -	百分比总计: -
Place the overlay above TrackThatPlease's target row (anchored to its row when it can be found).	将叠加层放在 TrackThatPlease 目标行上方 (找到其行时直接锚定)。
Player	玩家
Player buff list updated: was %s, now %s	玩家增益列表已更新: 原 %s，现 %s
Position X:	位置 X:
Position Y:	位置 Y:
Potential: %s s	潜在: %s 秒
Potential: -	潜在: -
Potential: every modifier counted with stacks 1 and auras assumed up - the best case for this build.	潜在: 每个修正按 1 层计算并假设所有光环存在 - 此配置的最佳情况。
Preset %s%s: Load applies its layout to all units, Delete removes it.	预设 %s%s: Load 将布局应用到所有单位，Delete 删除它。
Preset already exists: %s	预设已存在: %s
Preset currently applied to all three units.	当前应用于全部三个单位的预设。
Preset deleted: %s	预设已删除: %s
Preset loaded: %s	预设已加载: %s
Preset name cannot be empty	预设名称不能为空
Preset not found	预设未找到
Preset not found: %s	预设未找到: %s
Preset saved: %s	预设已保存: %s
Presets	预设
Presets *	预设 *
Previous page of custom entries.	上一页自定义条目。
Previous page of presets.	上一页预设。
Previous page of results.	上一页结果。
Previous page of tracked entries.	上一页追踪条目。
Previous page.	上一页。
Re-apply the active preset %s.	重新应用当前预设 %s。
Read the file and apply it: replaces custom entries, tracked lists and unit layouts.	读取文件并应用: 替换自定义条目、追踪列表和单位布局。
Received buff list update event	收到增益列表更新事件
Record (Debug)	Record (调试)
Record window (needs Debug: ON): buffs seen and skills from the combat log, with one-click Add.	Record 窗口 (需 Debug: ON): 已见增益与战斗日志技能，一键 Add。
Reference	参考
Remove	移除
Remove this modifier from the entry.	从条目中移除此修正。
Rename	重命名
Rename canvas	重命名画布
Rename the selected canvas (up to 24 characters).	重命名所选画布 (最多 24 个字符)。
Repeated error creating canvases for %s	再次为 %s 创建画布失败
Rescan dump	重新扫描转储
Reset	重置
Row spacing:	行间距:
Rows:	行:
Save	保存
Save current	保存当前
Save my config to a file	将我的配置保存到文件
Save the current layout as a preset, load or delete presets.	将当前布局保存为预设，或加载、删除预设。
Save the current layout of all units (position, size, colours, grid, tracked entries) as a preset.	将全部单位的当前布局 (位置、大小、颜色、网格、追踪条目) 保存为预设。
Save the entry and refresh both lists and the panels.	保存条目并刷新两个列表与面板。
Save the new name and rebuild the panels.	保存新名称并重建面板。
Saved	已保存
Saved presets:	已保存的预设:
Saved to: %s	已保存到: %s
Scan dump	扫描转储
Scan started... the database will refresh when done	扫描已开始... 完成后数据库会刷新
Scan the client buff table again and rebuild the icon/name dump.	重新扫描客户端增益表并重建图标/名称转储。
Scan the client buff table and rebuild the icon dump (takes a moment).	扫描客户端增益表并重建图标转储 (需要一点时间)。
Seconds or percent; multiplied by the aura's stack count (1 if none).	秒或百分比；乘以光环层数 (没有则为 1)。
Select address above and copy it manually (Ctrl+C)	选择上方地址并手动复制 (Ctrl+C)
Select canvas:	选择画布:
Select language:	选择语言:
Show label: OFF	显示标签: 关
Show label: ON	显示标签: 开
Show the %s journal.	显示 %s 日志。
Show the entry name under each icon of this canvas. Current: %s.	在此画布的每个图标下显示条目名称。当前: %s。
Show this canvas in the settings column (entries and layout).	在设置栏中显示此画布 (条目和布局)。
Size:	大小:
Skill	技能
Skill log cleared	技能日志已清空
Skill: tracked from the combat log by its spell name. Fields: Name, Cooldown, Spell, icon.	技能: 根据战斗日志中的技能名称追踪。字段: Name、Cooldown、Spell、图标。
Skills seen in combat log: %s	战斗日志中的技能: %s
Skills seen in the combat log for the selected unit, newest first.	所选单位在战斗日志中的技能，最新在前。
Smart	Smart
Smart %:	Smart %:
Smart %: extra reduction learned for this target when the skill returns earlier than predicted (0-100).	Smart %: 当技能比预测更早恢复时，为此目标学习到的额外缩短 (0-100)。
Smart learning state for the current target: learned after an early re-use, never learned otherwise.	当前目标的 Smart 学习状态: 技能提前再次使用时学习，否则不会学习。
Smart reduction % must be a number 0..100	Smart 缩减 % 必须是 0..100 的数字
Source	来源
Space between our overlay row and TrackThatPlease's row, px.	我们的叠加行与 TrackThatPlease 行之间的间距(像素)。
Spell %s	Spell %s
Spell name exactly as the combat log reports it (Skill only).	技能名称，必须与战斗日志完全一致 (仅技能)。
Spell name is required	需要技能名称
Spell:	Spell:
Spell: OFF	Spell: 关
Spell: ON	Spell: 开
Start typing a skill or buff name...	开始输入技能或增益名称...
Stop tracking this entry on every canvas of this unit. The custom entry stays in the list.	在此单位的所有画布取消追踪。自定义条目仍保留在列表中。
Support	支持
Support the Addon Developer	支持插件开发者
Switch the canvas edited below. Shown: %s.	切换下方编辑的画布。当前: %s。
Switch the interface, every hover tooltip and all chat messages to this language.	将界面、所有悬停提示和所有聊天消息切换为此语言。
TTP canvas found: %s	找到 TTP 画布: %s
TTP canvas not found, fallback: %s	未找到 TTP 画布，改用回退: %s
Target	目标
Target cache cleaned: %s	目标缓存已清理: %s
Target display modes: overlay at the target's screen position, hide the floating canvas, avoid TrackThatPlease.	目标显示模式: 在目标屏幕位置叠加、隐藏浮动画布、避开 TrackThatPlease。
Target only. Stacks are read from the target's aura (1 if none).	仅目标。层数从目标光环读取 (没有则为 1)。
Text color:	文字颜色:
Thank you for supporting the development!	感谢支持开发!
Thank you for your hard work!	感谢您的辛勤付出!
Timer font size in pixels (8-40). Applies on Enter.	倒计时字体大小(像素，8-40)。按 Enter 应用。
Timer settings	倒计时设置
Track this ID/name on the current unit and canvas.	在当前单位与画布追踪此 ID/名称。
Tracked entries:	追踪条目:
Tracking key of this entry; it cannot be changed here.	此条目的追踪键；此处无法更改。
Type	类型
Type:	类型:
Type: %s. Click to cycle Flat -> Percent -> Reset.	类型: %s。点击切换 Flat -> Percent -> Reset。
UI initialization for %s: %s	%s 的界面初始化: %s
Unconditional %s	无条件 %s
Unit whose journal is listed below.	下方列出其日志的单位。
Unit whose panel is edited below. Every unit has its own canvases and tracked list.	下方编辑其面板的单位。每个单位都有自己的画布和追踪列表。
Unit:	单位:
Unknown	未知
Up	上移
Use this canvas.	使用此画布。
Use this custom entry.	使用此自定义条目。
Use this custom entry: %s.	使用此自定义条目: %s。
Value	值
Value for an unconditional modifier: seconds for +Flat, percent for +Percent (0 or more).	无条件修正的值: +Flat 为秒数，+Percent 为百分比 (不小于 0)。
Value: %s %%.	值: %s %%。
Value: %s s.	值: %s 秒。
Vertical gap between grid rows, px (0-40). Applies on Enter.	网格行之间的垂直间距(像素，0-40)。按 Enter 应用。
Write the whole configuration (custom entries, tracked lists, layouts) to a JSON file in the addon folder.	将整个配置 (自定义条目、追踪列表、布局) 写入插件文件夹中的 JSON 文件。
active	当前
always value must be a number >= 0	always 值必须是不小于 0 的数字
aura dump -> %s	光环转储 -> %s
aura dump: write failed	光环转储: 写入失败
buff dump: %s buffs loaded from %s	增益转储: 已从 %s 加载 %s 个增益
buff dump: %s buffs, %s skill icons	增益转储: %s 个增益，%s 个技能图标
buff dump: %s buffs, %s; tables=%s named=%s errors=%s%s	增益转储: %s 个增益，%s；tables=%s named=%s errors=%s%s
buff dump: '%s' -> id=%s path=%s (entries updated: %s)	增益转储: '%s' -> id=%s path=%s (已更新条目: %s)
buff dump: '%s' not found	增益转储: 未找到 '%s'
buff journal	增益日志
buff scan: dumping all buffs%s (1..50000, 8000000..8001000)	增益扫描: 正在导出所有增益%s (1..50000, 8000000..8001000)
cast %s by %s (%sms)	施放 %s 由 %s (%s 毫秒)
custom entry removed: %s	自定义条目已删除: %s
custom: id=%s name=%s spell=%s CD=%s D=%s	custom: id=%s name=%s spell=%s CD=%s D=%s
effective CD: reset '%s' zeroed %s on target %s	有效冷却: 重置 '%s' 将 %s 在目标 %s 上归零
effective CD: smart %.1f%% learned for %s on target %s (applied after %.2f s < %.2f s)	有效冷却: 已为 %s 在目标 %s 学习 smart %.1f%% (间隔 %.2f 秒 < %.2f 秒)
effective CD: target %s class %s -> %s, smart reset for this target	有效冷却: 目标 %s 的类别 %s -> %s，已为此目标重置 smart
enter a buff ID or name	请输入增益 ID 或名称
entry %s: type=%s CD=%s D=%s%s	条目 %s: type=%s CD=%s D=%s%s
faded	已结束
hide	隐藏
icon from dump: %s -> %s	来自转储的图标: %s -> %s
icon learned for spell %s: %s	已为技能 %s 学习图标: %s
icon lookup id=%s -> path=%s name=%s%s	图标查找 id=%s -> path=%s name=%s%s
icon picked: %s -> %s	已选图标: %s -> %s
icon: no spellId in event for '%s'	图标: 事件中没有 '%s' 的 spellId
invalid modifier source	修正来源无效
mana cast %s cost=%s spend=%.1f regen=%.1f mount=%s	法力施放 %s cost=%s spend=%.1f regen=%.1f mount=%s
mana drop %.1f (regen %.1f) — no match; pet='%s'; mount-blocked=%d cd-blocked=%d; entries: %s	法力下降 %.1f (regen %.1f) — 无匹配；pet='%s'；mount-blocked=%d cd-blocked=%d；条目: %s
modifier %s: value must be a number >= 0	修正 %s: 值必须是不小于 0 的数字
msg %s src=%s tgt=%s spell=%s id=%s	msg %s src=%s tgt=%s spell=%s id=%s
parsed: spellId=%s spellName=%s	解析: spellId=%s spellName=%s
saved to buff_dump.tbl	已保存到 buff_dump.tbl
settings window rebuild failed: %s	设置窗口重建失败: %s
show	显示
skill icon: %s	技能图标: %s
skill log	技能日志
timer %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s	计时 %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s
too many modifiers	修正过多
updateVisibleItems not found!	未找到 updateVisibleItems!
]==]
dict.tr = [==[
 (active)	 (etkin)
 (no target)	 (hedef yok)
 (was %s)	 (önceki: %s)
 + search '%s'	 + arama '%s'
 | first error: %s	 | ilk hata: %s
%d. buff ID: %s	%d. buff ID: %s
%d. debuff ID: %s	%d. debuff ID: %s
%s (id %s) - %s, seen %s time(s).	%s (id %s) - %s, %s kez görüldü.
%s (id %s) on canvas %s.	%s (id %s), tuval %s.
%s - %s. Click to apply this icon.	%s - %s. Bu simgeyi uygulamak için tıklayın.
%s - buff ID: %s, unit: %s	%s - buff ID: %s, birim: %s
%s - seen %s time(s) in the combat log.	%s - savaş kaydında %s kez görüldü.
%s args: %s	%s parametreler: %s
%s buff added for tracking: %s (%s)	%s buff izlemeye eklendi: %s (%s)
%s buff removed from tracking: %s	%s buff izlemeden çıkarıldı: %s
%s tracked entries will be removed from this unit.	Bu birimden %s izlenen kayıt kaldırılacak.
'%s': cooldown recorded for %s (unit %s)	'%s': %s için bekleme süresi kaydedildi (birim %s)
'%s': no source in the event	'%s': olayda kaynak yok
'%s': repeat trigger after %.1f s - ignored (window %s)	'%s': %.1f s sonra tekrar tetiklendi - yok sayıldı (pencere %s)
'%s': self cast -> Player/Mount panels: %s	'%s': kendine kullanım -> Player/Mount panelleri: %s
'%s': self cast, but the buff is not tracked on Player/Mount	'%s': kendine kullanım, ancak buff Player/Mount'ta izlenmiyor
'%s': source %s unknown, waiting for the first target	'%s': kaynak %s bilinmiyor, ilk hedef bekleniyor
'%s': you are the current target -> recorded to Target	'%s': geçerli hedef sizsiniz -> Target'a kaydedildi
(no target)	(hedef yok)
(set at creation, cannot be changed)	(oluştururken belirlenir, değiştirilemez)
* Mount	* Binek
* Player	* Oyuncu
* Target	* Hedef
+Flat	+Sabit
+Flat: subtract N seconds, applied before the percentages.	+Flat: N saniye çıkarır, yüzdelerden önce uygulanır.
+Percent	+Yüzde
+Percent: subtract N %, applied after all flat reductions.	+Percent: N % çıkarır, tüm sabit indirimlerden sonra uygulanır.
Active	Etkin
Active buffs for %s (%d):	%s için etkin bufflar (%d):
Active debuffs for %s (%d):	%s için etkin debufflar (%d):
Active preset: %s	Etkin ön ayar: %s
Active preset: None	Etkin ön ayar: yok
Add	Ekle
Add a canvas: copies this layout and places the copy below it.	Tuval ekle: bu yerleşimi kopyalar ve kopyayı altına koyar.
Add a custom entry: pick the type first, the fields below follow it, then Add entry.	Özel kayıt ekle: önce türü seçin, alttaki alanlar ona göre değişir, sonra Add entry.
Add custom entry:	Özel kayıt ekle:
Add entry	Kayıt ekle
Add this entry to tracking on the current unit and canvas.	Kaydı geçerli birim ve tuvalde izlemeye ekler.
Add this source as a modifier (condition On target, type Flat, value 0).	Bu kaynağı değiştirici olarak ekle (koşul On target, tür Flat, değer 0).
Add to tracking on the current unit (creates a custom entry with a default CD/D when needed).	Geçerli birimde izlemeye ekler (gerekirse varsayılan CD/D ile özel kayıt oluşturur).
Add: buff -> custom entry + tracking. Skill -> custom entry with Spell filled.	Add: buff -> özel kayıt + izleme. Skill -> Spell doldurulmuş kayıt.
Added skill: %s	Beceri eklendi: %s
Added to %s	%s birimine eklendi
Added: %s	Eklendi: %s
Addon Options	Eklenti Seçenekleri
Already tracked (%s)	Zaten izleniyor (%s)
Already tracked: %s	Zaten izleniyor: %s
Also fill the entry's Spell field with the picked buff name.	Seçilen buff adını kaydın Spell alanına da yazar.
Always	Her zaman
Always:	Her zaman:
Apply icon, grid, position and timer values. Enter inside a field applies it too.	Simge, ızgara, konum ve geri sayım değerlerini uygular. Alanda Enter da uygular.
Apply the modifiers below to this entry's cooldown (buff/debuff and skill, target only).	Aşağıdaki değiştiricileri bu kaydın bekleme süresine uygula (buff/debuff ve beceri, yalnızca hedef).
Aura (or entry) the modifier counts for; stacks are read from the target.	Değiştiricinin sayıldığı aura (veya kayıt); yığınlar hedeften okunur.
Avoid TrackThatPlease	TrackThatPlease'ten kaçın
Base CD: %s s	Temel CD: %s s
Base CD: -	Temel CD: -
Base cooldown of the entry, seconds (the Cooldown field).	Kaydın temel bekleme süresi, saniye (Cooldown alanı).
Buff debug mode disabled.	Buff hata ayıklama modu kapatıldı.
Buff debug mode enabled. Buff IDs will be displayed in chat.	Buff hata ayıklama modu açık. Buff ID'leri sohbete yazılacak.
Buff debug mode is disabled. Enable it in settings.	Buff hata ayıklama modu kapalı. Ayarlardan açın.
Buff journal: every buff/debuff seen while Debug is ON, active and faded, newest first.	Buff kaydı: Debug açıkken görülen tüm buff/debuff'lar, etkin ve sönmüş, en yenisi önce.
Buff lists refreshed after import	İçe aktarmadan sonra buff listeleri yenilendi
Buff log	Buff kaydı
Buff log cleared	Buff kaydı temizlendi
Buff, debuff or skill ID (a name from Custom entries also works). Type to filter, Enter or Add to track it.	Buff, debuff veya beceri ID'si (Custom entries içindeki bir ad da olur). Filtrelemek için yazın, izlemek için Enter veya Add.
Buff/Debuff	Buff/Debuff
Buff/debuff ID, e.g. 800004. Required for Buff/Debuff entries.	Buff/debuff ID'si, örn. 800004. Buff/Debuff kayıtları için zorunlu.
Buffs seen: %s (active %s)	Görülen bufflar: %s (etkin %s)
CD %s s	CD %s s
CD/D %s: CD=%s D=%s	CD/D %s: CD=%s D=%s
Cancel	İptal
Canvas %s	Tuval %s
Canvas model ready: playerpet=%s player=%s target=%s	Tuval modeli hazır: playerpet=%s player=%s target=%s
Canvas:	Tuval:
Canvas: %s	Tuval: %s
Canvas: one independent icon panel. A unit can own several canvases.	Tuval: bağımsız bir simge paneli. Bir birimin birden fazla tuvası olabilir.
Canvases	Tuvaller
Clear log	Kaydı temizle
Clear the %s of the selected unit.	Seçili birimin %s temizlenir.
Close	Kapat
Close the Record window.	Record penceresini kapat.
Close the icon search without changing the icon.	Simgeyi değiştirmeden simge aramayı kapatır.
Close the settings window (Esc).	Ayarlar penceresini kapat (Esc).
Close the window (Esc).	Pencereyi kapat (Esc).
Close without deleting.	Silmeden kapat.
Close without renaming.	Yeniden adlandırmadan kapat.
Close without saving.	Kaydetmeden kapat.
Columns:	Sütunlar:
Condition	Koşul
Condition: %s (click to toggle). On target counts only while the aura is up.	Koşul: %s (geçiş için tıklayın). On target yalnızca aura varken sayılır.
Configuration imported from file - window closed	Yapılandırma dosyadan içe aktarıldı - pencere kapatıldı
Configuration imported successfully	Yapılandırma başarıyla içe aktarıldı
Configuration saved to file: %s	Yapılandırma dosyaya kaydedildi: %s
Containers not found!	Kapsayıcılar bulunamadı!
Cooldown / Duration are seconds; 0 is valid. Icon is optional.	Cooldown / Duration saniyedir; 0 geçerlidir. Simge isteğe bağlıdır.
Cooldown Buff Tracker	Buff ve Bekleme Takipçisi
Cooldown in seconds, 0 is allowed.	Bekleme süresi saniye, 0 geçerlidir.
Cooldown must be a number >= 0	Bekleme süresi 0 veya daha büyük bir sayı olmalı
Cooldown:	Bekleme:
Cooldown: %s s.	CD: %s s.
Could not read file: %s (put it into the CooldawnBuffTracker folder)	Dosya okunamadı: %s (CooldawnBuffTracker klasörüne koyun)
Could not save file: %s	Dosya kaydedilemedi: %s
Countdown text colour. Click to open the palette.	Geri sayım metin rengi. Paleti açmak için tıklayın.
Countdown text of the selected canvas.	Seçili tuvalin geri sayım metni.
Create the entry with these values and track it on the current canvas.	Kaydı bu değerlerle oluştur ve geçerli tuvalde izle.
Custom entries:	Özel kayıtlar:
Custom entries: ID, name, cooldown and duration used by the tracked list on every unit.	Özel kayıtlar: tüm birimlerdeki izleme listesinin kullandığı ID, ad, bekleme ve süre.
Debug mode already initialized, skipping.	Hata ayıklama modu zaten başlatıldı, atlanıyor.
Debug: OFF	Debug: KAPALI
Debug: ON	Debug: AÇIK
Debug: print buff IDs, combat-log details and the buff journal to chat; shows Record. Current: %s.	Debug: buff ID'lerini, savaş kaydı ayrıntılarını ve buff kaydını sohbete yazar; Record'u gösterir. Şu an: %s.
Delete	Sil
Delete canvas	Tuvayı sil
Delete canvas "%s"?	"%s" tuvası silinsin mi?
Delete preset %s. Cannot be undone.	%s ön ayarı silinsin. Geri alınamaz.
Delete the selected canvas and untrack its entries (asks first).	Seçili tuvayı siler ve kayıtlarını izlemeden çıkarır (önce sorar).
Delete this canvas and untrack the entries it holds. Cannot be undone.	Bu tuvayı siler ve kayıtlarını izlemeden çıkarır. Geri alınamaz.
Delete this custom entry and remove it from tracking on every unit.	Bu özel kaydı siler ve tüm birimlerde izlemeden çıkarır.
Donate EthereumX (ETX):	EthereumX (ETX) bağışı:
Donate USDT ERC20:	USDT ERC20 bağışı:
Donate USDT SOL:	USDT SOL bağışı:
Donate USDT TON:	USDT TON bağışı:
Donate USDT TRC20:	USDT TRC20 bağışı:
Donation address. Click the field, select it and copy with Ctrl+C.	Bağış adresi. Alana tıklayın, seçin ve Ctrl+C ile kopyalayın.
Down	Aşağı
Drag to move the window.	Pencereyi taşımak için sürükleyin.
Draw an additional compact overlay at the target's screen position. It does not hide the floating canvas; use Hide target canvas for that.	Hedefin ekran konumunda ek bir kompakt kaplama çizer. Yüzen tuvayı gizlemez; bunun için Hide target canvas kullanın.
Dump scan started...	Döküm taraması başladı...
Duration in seconds, 0 is allowed (Buff/Debuff only).	Süre saniye, 0 geçerlidir (yalnızca Buff/Debuff).
Duration must be a number >= 0	Süre 0 veya daha büyük bir sayı olmalı
Duration:	Süre:
Duration: %s s.	Süre: %s s.
EXPORT - save your current setup to a file:	DIŞA AKTAR - mevcut kurulumu dosyaya kaydet:
Edit	Düzenle
Edit the Mount (pet) panel settings.	Mount (binek) paneli ayarlarını düzenle.
Edit the Player panel settings.	Player paneli ayarlarını düzenle.
Edit the Target panel settings, including the target overlay.	Target paneli ayarlarını, hedef kaplaması dahil düzenle.
Edit this entry: cooldown, duration, spell or mana, icon and effective CDs.	Bu kaydı düzenle: bekleme, süre, spell veya mana, simge ve etkin CD'ler.
Effective CDs	Etkin CD'ler
Effective cooldown right now: max(0, base - flat) x (1 - percent / 100). '(no target)' means no aura snapshot, so only Always modifiers count.	Şu anki etkin bekleme: max(0, base - flat) x (1 - percent / 100). '(no target)' aura anlık görüntüsü yok demektir, bu yüzden yalnızca Always değiştiricileri sayılır.
Effective now: %s	Şu an etkin: %s
Effective now: -	Şu an etkin: -
Empty preset name	Ön ayar adı boş
Enable user-defined cooldown modifiers for this entry (target only).	Bu kayıt için özel CD değiştiricilerini aç (yalnızca hedef).
Enter the name of the config file first	Önce yapılandırma dosyasının adını girin
Entries drawn on the selected canvas of this unit. Up/Down change their order, Remove untracks them.	Bu birimin seçili tuvalinde çizilen kayıtlar. Up/Down sırayı değiştirir, Remove izlemeyi bırakır.
Entries in the current tab; buffs also show how many are active.	Geçerli sekmedeki kayıtlar; bufflarda kaçının etkin olduğu da görünür.
Entry ID (tracking key): %s.	Kayıt ID'si (izleme anahtarı): %s.
Entry icon. Click to pick one from the buff dump; optional.	Kayıt simgesi. Buff dökümünden seçmek için tıklayın; isteğe bağlı.
Entry type, fixed at creation. Delete and re-create the entry to change it. Buff/Debuff has an aura, Skill is read from the combat log, Mana skill from pet mana.	Tür oluştururken sabitlenir. Değiştirmek için kaydı silip yeniden oluşturun. Buff/Debuff aurası vardır, Skill savaş kaydından okunur, Mana skill evcil hayvan manasından izlenir.
Entry: cooldown / duration	Kayıt: bekleme / süre
Error creating canvases for %s	%s için tuval oluşturma hatası
Error: %s	Hata: %s
Error: '%s' not found - add it as a custom buff first	Hata: '%s' bulunamadı - önce özel kayıt olarak ekleyin
Error: Buff already tracked or error occurred	Hata: buff zaten izleniyor veya bir hata oluştu
Error: Configuration must be a table	Hata: yapılandırma bir tablo olmalı
Error: Custom buff at index %s is not a table	Hata: %s indeksli özel kayıt tablo değil
Error: Custom buff at index %s missing required fields	Hata: %s indeksli özel kayıtta zorunlu alanlar eksik
Error: Failed to get current settings	Hata: geçerli ayarlar alınamadı
Error: ID, name, cooldown and duration are required	Hata: ID, ad, bekleme ve süre gerekli
Error: Invalid JSON format	Hata: Geçersiz JSON biçimi
Error: Missing required fields (customBuffs, trackedBuffs)	Hata: zorunlu alanlar eksik (customBuffs, trackedBuffs)
Error: Missing trackedBuffs fields (playerpet, player, target)	Hata: trackedBuffs alanları eksik (playerpet, player, target)
Error: cooldown must be 0 or more	Hata: bekleme süresi 0 veya daha büyük olmalı
Error: customBuffs and trackedBuffs must be tables	Hata: customBuffs ve trackedBuffs tablo olmalı
Error: duration must be 0 or more	Hata: süre 0 veya daha büyük olmalı
Error: enter a buff ID or the skill name	Hata: bir buff ID'si veya beceri adı girin
Error: entry with this ID already exists	Hata: bu ID'ye sahip kayıt zaten var
Error: name, cooldown, mana cost and mount name are required	Hata: ad, bekleme, mana maliyeti ve binek adı gerekli
Error: spell name and cooldown are required	Hata: beceri adı ve bekleme süresi gerekli
Error: the last canvas cannot be deleted	Hata: son tuval silinemez
Error: trackedBuffs.%s contains non-number at index %s	Hata: trackedBuffs.%s içinde %s indeksinde sayı olmayan değer var
Error: trackedBuffs.%s is not a table	Hata: trackedBuffs.%s bir tablo değil
Export the whole configuration to a file or import a received one.	Tüm yapılandırmayı dosyaya aktar veya alınanı içe aktar.
Failed to create settings window!	Ayarlar penceresi oluşturulamadı!
Failed to delete preset	Ön ayar silinemedi
Failed to encode configuration: %s	Yapılandırma kodlanamadı: %s
Failed to get settings for export	Dışa aktarma için ayarlar alınamadı
Failed to load buff_helper.lua, using placeholder	buff_helper.lua yüklenemedi, yer tutucu kullanılıyor
Failed to load buffs_to_track.lua, using settings	buffs_to_track.lua yüklenemedi, ayarlar kullanılıyor
Failed to load preset	Ön ayar yüklenemedi
Failed to read settings	Ayarlar okunamadı
Failed to write config file: %s	Yapılandırma dosyası yazılamadı: %s
Failed to write file	Dosya yazılamadı
Failed: %s	Başarısız: %s
File has an unexpected format	Dosya beklenmeyen biçimde
File name (file must be in the CooldawnBuffTracker folder):	Dosya adı (dosya CooldawnBuffTracker klasöründe olmalı):
File name inside the CooldawnBuffTracker folder; the extension is optional.	CooldawnBuffTracker klasörü içindeki dosya adı; uzantı isteğe bağlı.
Filter by buff or skill name (English names). An empty field lists the whole dump.	Buff veya beceri adına göre filtrele (İngilizce adlar). Boş alan tüm dökümü listeler.
Flat	Sabit
Flat = seconds, Percent = %, Reset = zero the timer when the aura appears.	Flat = saniye, Percent = %, Reset = aura göründüğünde zamanlayıcıyı sıfırlar.
Flat modifiers counted right now, in seconds. Applied first, multiplied by aura stacks.	Şu anda sayılan sabit değiştiriciler, saniye. Önce uygulanır, aura yığınlarıyla çarpılır.
Flat total: %s	Sabit toplam: %s
Flat total: -	Sabit toplam: -
Font size:	Yazı boyutu:
Found: %s (click a row to apply the icon)	Bulunan: %s (simgeyi uygulamak için satıra tıklayın)
Gap to the TrackThatPlease row, px (0-40).	TrackThatPlease satırına boşluk, px (0-40).
Gap:	Boşluk:
Grid (cols x rows):	Izgara (sütun x satır):
Grid rows (1-10). Applies on Enter.	Izgara satırları (1-10). Enter ile uygulanır.
Grid: icons per row, number of rows, the cap and the vertical gap.	Izgara: satır başına simge, satır sayısı, üst sınır ve dikey boşluk.
Helpers module not loaded, using basic settings	Helpers modülü yüklenmedi, temel ayarlar kullanılıyor
Hide every floating target canvas. Buff data keeps running and the Target Overlay still draws when it is on.	Tüm yüzen hedef tuvallerini gizler. Buff verisi çalışmaya devam eder ve Target Overlay açıksa çizilir.
Hide target canvas	Hedef tuvalini gizle
Horizontal gap between icons, px (0-40). Applies on Enter.	Simgeler arası yatay boşluk, px (0-40). Enter ile uygulanır.
ID/name:	ID/ad:
ID:	ID:
IMPORT - load a config you received	İÇE AKTAR - alınan yapılandırmayı yükle
Icon layout of the selected canvas: size, spacing, label and grid.	Seçili tuvalin simge yerleşimi: boyut, aralık, etiket ve ızgara.
Icon position	Simge konumu
Icon search	Simge arama
Icon settings	Simge ayarları
Icon size in pixels (16-64). Applies on Enter.	Simge boyutu piksel (16-64). Enter ile uygulanır.
Icon size of the overlay, px (12-64).	Kaplamanın simge boyutu, px (12-64).
Icon size:	Simge boyutu:
Icon spacing:	Simge aralığı:
Icons per overlay row (1-12). Extra icons wrap downwards.	Kaplama satırında simge (1-12). Fazlalar alta sarılır.
Icons per row (1-20). Applies on Enter.	Satırda simge (1-20). Enter ile uygulanır.
Import / Export Configuration	Yapılandırma İçe / Dışa Aktarma
Import failed: configuration must be a table	İçe aktarma başarısız: yapılandırma tablo olmalı
Import failed: could not read the current settings	İçe aktarma başarısız: geçerli ayarlar okunamadı
Import failed: custom entry at index %s is not a table	İçe aktarma başarısız: %s indeksli özel kayıt tablo değil
Import failed: custom entry at index %s missing required fields	İçe aktarma başarısız: %s indeksli özel kayıtta zorunlu alanlar eksik
Import failed: customBuffs and trackedBuffs must be tables	İçe aktarma başarısız: customBuffs ve trackedBuffs tablo olmalı
Import failed: invalid JSON format - %s	İçe aktarma başarısız: geçersiz JSON biçimi - %s
Import failed: missing required fields	İçe aktarma başarısız: zorunlu alanlar eksik
Import failed: missing trackedBuffs fields	İçe aktarma başarısız: trackedBuffs alanları eksik
Import failed: trackedBuffs.%s contains a non-number at index %s	İçe aktarma başarısız: trackedBuffs.%s içinde %s indeksinde sayı olmayan değer var
Import failed: trackedBuffs.%s is not a table	İçe aktarma başarısız: trackedBuffs.%s tablo değil
Import field is empty - paste a configuration into the lower field first	İçe aktarma alanı boş - önce yapılandırmayı alt alana yapıştırın
Import from file failed: %s	Dosyadan içe aktarma başarısız: %s
Import from file: no file name entered	Dosyadan içe aktarma: dosya adı girilmedi
Import/Export	İçe/Dışa Aktar
Import: the Import field is empty - paste a configuration into the lower field first	İçe aktarma: alan boş - önce yapılandırmayı alt alana yapıştırın
Interface language: the whole UI, every hover tooltip and all chat messages switch at once. The settings window rebuilds; no /reload needed.	Arayüz dili: tüm arayüz, tüm ipuçları ve tüm sohbet mesajları birden değişir. Ayarlar penceresi yeniden kurulur; /reload gerekmez.
Invalid buff ID	Geçersiz buff ID'si
Invalid spell name	Geçersiz beceri adı
Keep the target overlay above TrackThatPlease's target row. Anchors to its real target canvas (targetBuffCanvas) when it can be found, otherwise places the row with targetBuffVerticalOffset, targetIconSize and the UI scale. Turn off to use the canvas offsets instead.	Hedef kaplamasını TrackThatPlease hedef satırının üstünde tutar. Gerçek hedef tuvali (targetBuffCanvas) bulunursa ona bağlanır, bulunamazsa satırı targetBuffVerticalOffset, targetIconSize ve arayüz ölçeğiyle yerleştirir. Kapatırsanız kaplama tuval kaymalarıyla yerleşir.
Label color:	Etiket rengi:
Language	Dil
Language changed to %s	Dil %s olarak değiştirildi
Language: %s	Dil: %s
Learned for this target (+%s%%)	Bu hedef için öğrenildi (+%s%%)
Load	Yükle
Load config from file	Yapılandırmayı dosyadan yükle
Load preset %s: position, size, colours and tracked entries.	%s ön ayarını yükle: konum, boyut, renkler ve izlenen kayıtlar.
Loading CooldawnBuffTracker %s by %s	CooldawnBuffTracker %s yükleniyor, yazar %s
Lock: OFF	Kilit: KAPALI
Lock: ON	Kilit: AÇIK
Lock: ON disables dragging this panel with the mouse. Current: %s.	Kilit: AÇIK bu panelin fareyle taşınmasını engeller. Şu an: %s.
Log skills	Beceri kaydı
Mana %s	Mana %s
Mana cost must be > 0	Mana maliyeti > 0 olmalı
Mana cost of the mount skill, used to detect the spend (Mana skill only).	Binek becerisinin mana maliyeti; harcamayı algılamak için kullanılır (yalnızca binek becerisi).
Mana skill	Binek becerisi
Mana skill: mount skill tracked by the pet's mana spend. Fields: Name, Cooldown, Mana, Mount, icon.	Binek becerisi: evcil hayvanın mana harcamasıyla izlenir. Alanlar: Name, Cooldown, Mana, Mount, simge.
Mana:	Mana:
Matches for the current query. Click a row to apply its icon.	Geçerli sorgunun eşleşmeleri. Simgesini uygulamak için satıra tıklayın.
Max icons drawn on this canvas (1 to Columns x Rows). Applies on Enter.	Bu tuvalde en fazla simge (1 ile Sütun x Satır). Enter ile uygulanır.
Max icons:	Maks. simge:
Mir OFF	Mir KAPALI
Mir ON	Mir AÇIK
Mirror this player aura on the Target panel (buff/debuff only). Current: %s.	Bu oyuncu aurasını Target panelinde yansıla (yalnızca buff/debuff). Şu an: %s.
Modifier source: %s.	Değiştirici kaynağı: %s.
Modifier source: buff ID, name or spell of a custom entry. Its aura is checked on the target.	Değiştirici kaynağı: özel kaydın buff ID'si, adı veya spell'i. Aurası hedefte kontrol edilir.
Modifiers	Değiştiriciler
Mount	Binek
Mount %s	Binek %s
Mount buff list updated: was %s, now %s	Binek buff listesi güncellendi: önce %s, şimdi %s
Mount name is required	Binek adı gerekli
Mount name the skill belongs to (Mana skill only).	Becerinin ait olduğu binek adı (yalnızca binek becerisi).
Mount:	Binek:
Move entry to canvas	Kaydı tuvale taşı
Move the entry to this canvas.	Kaydı bu tuvale taşır.
Move this entry one place down inside the canvas.	Kaydı tuval içinde bir sıra aşağı taşır.
Move this entry one place up inside the canvas.	Kaydı tuval içinde bir sıra yukarı taşır.
Move this entry to another canvas of the same unit.	Kaydı aynı birimin başka bir tuvaline taşır.
Mv	Taşı
NOT saved (api.File unavailable)	KAYDEDİLMEDİ (api.File kullanılamıyor)
Name for the new preset, up to 40 characters. Must be unique.	Yeni ön ayar adı, en fazla 40 karakter. Benzersiz olmalı.
Name is required	Ad gerekli
Name label colour under the icons. Click to open the palette.	Simgelerin altındaki ad rengi. Paleti açmak için tıklayın.
Name shown on the canvas instead of the ID.	ID yerine tuvalde gösterilen ad.
Name shown on the canvas: %s.	Tuvaldeki ad: %s.
Name:	Ad:
Native frame display	Yerel çerçeve görünümü
New canvas name, up to 24 characters. Enter saves.	Yeni tuval adı, en fazla 24 karakter. Enter kaydeder.
New preset name:	Yeni ön ayar adı:
Next page of custom entries.	Sonraki özel kayıt sayfası.
Next page of presets.	Sonraki ön ayar sayfası.
Next page of results.	Sonraki sonuç sayfası.
Next page of tracked entries.	Sonraki izlenen kayıt sayfası.
Next page.	Sonraki sayfa.
No active buffs	Etkin buff yok
No active debuffs	Etkin debuff yok
No custom entries yet	Henüz özel kayıt yok
No presets saved	Kayıtlı ön ayar yok
No target selected	Hedef seçilmedi
Not learned	Öğrenilmedi
Nothing found. Press Scan dump or change the query.	Bulunamadı. Scan dump'a basın veya sorguyu değiştirin.
Nothing tracked yet	Henüz hiçbir şey izlenmiyor
OFF	KAPALI
ON	AÇIK
On target	Hedefte
On target = only while the aura is on the target; Always = always counts.	On target = yalnızca aura hedefteyken; Always = her zaman sayılır.
Open the support window (donation addresses).	Destek penceresini aç (bağış adresleri).
Open the support window with the donation addresses.	Bağış adreslerinin olduğu destek penceresini açar.
Overlay X offset from the target's anchor (ignored while Avoid TrackThatPlease is on).	Kaplamanın hedef çapasından X kayması (Avoid TrackThatPlease açıkken yok sayılır).
Overlay X offset from the target's anchor, px.	Kaplamanın hedef çapasından X kayması, px.
Overlay Y offset from the target's anchor, px (negative = above).	Kaplamanın hedef çapasından Y kayması, px (negatif = yukarı).
Overlay around target	Hedef çevresinde kaplama
Overlay icon size, px (12-64).	Kaplama simge boyutu, px (12-64).
Page %s - 7 presets per page.	Sayfa %s - sayfa başına 7 ön ayar.
Page %s - 8 entries per page.	Sayfa %s - sayfa başına 8 kayıt.
Page %s - 9 entries per page.	Sayfa %s - sayfa başına 9 kayıt.
Page %s - 9 icons per page.	Sayfa %s - sayfa başına 9 simge.
Panel X on screen, px from the left edge (negative values are allowed).	Panelin X'i, sol kenardan px (negatif değerler olabilir).
Panel Y on screen, px from the top edge (negative values are allowed).	Panelin Y'si, üst kenardan px (negatif değerler olabilir).
Panel position on screen, in pixels from the top-left corner.	Panelin ekrandaki konumu, sol üst köşeden piksel.
Per row:	Satırda:
Percent	Yüzde
Percent modifiers counted right now plus the learned Smart %, added together. Applied second.	Şu anda sayılan yüzde değiştiricileri ve öğrenilen Smart % toplanır. İkinci olarak uygulanır.
Percent total: %s	Yüzde toplam: %s
Percent total: -	Yüzde toplam: -
Place the overlay above TrackThatPlease's target row (anchored to its row when it can be found).	Kaplamayı TrackThatPlease hedef satırının üstüne koyar (satır bulunursa ona bağlanır).
Player	Oyuncu
Player buff list updated: was %s, now %s	Oyuncu buff listesi güncellendi: önce %s, şimdi %s
Position X:	Konum X:
Position Y:	Konum Y:
Potential: %s s	Potansiyel: %s s
Potential: -	Potansiyel: -
Potential: every modifier counted with stacks 1 and auras assumed up - the best case for this build.	Potansiyel: her değiştirici 1 yığın ve tüm auralar açık varsayılır - bu yapı için en iyi durum.
Preset %s%s: Load applies its layout to all units, Delete removes it.	Ön ayar %s%s: Load yerleşimini tüm birimlere uygular, Delete siler.
Preset already exists: %s	Ön ayar zaten var: %s
Preset currently applied to all three units.	Şu anda üç birime de uygulanan ön ayar.
Preset deleted: %s	Ön ayar silindi: %s
Preset loaded: %s	Ön ayar yüklendi: %s
Preset name cannot be empty	Ön ayar adı boş olamaz
Preset not found	Ön ayar bulunamadı
Preset not found: %s	Ön ayar bulunamadı: %s
Preset saved: %s	Ön ayar kaydedildi: %s
Presets	Ön ayarlar
Presets *	Ön ayarlar *
Previous page of custom entries.	Önceki özel kayıt sayfası.
Previous page of presets.	Önceki ön ayar sayfası.
Previous page of results.	Önceki sonuç sayfası.
Previous page of tracked entries.	Önceki izlenen kayıt sayfası.
Previous page.	Önceki sayfa.
Re-apply the active preset %s.	Etkin ön ayarı %s yeniden uygula.
Read the file and apply it: replaces custom entries, tracked lists and unit layouts.	Dosyayı oku ve uygula: özel kayıtları, izleme listelerini ve birim yerleşimlerini değiştirir.
Received buff list update event	Buff listesi güncelleme olayı alındı
Record (Debug)	Record (Hata ayıklama)
Record window (needs Debug: ON): buffs seen and skills from the combat log, with one-click Add.	Record penceresi (Debug: ON gerekir): görülen bufflar ve savaş kaydından beceriler, tek tıkla Add.
Reference	Referans
Remove	Kaldır
Remove this modifier from the entry.	Bu değiştiriciyi kayıttan kaldırır.
Rename	Yeniden adlandır
Rename canvas	Tuvayı yeniden adlandır
Rename the selected canvas (up to 24 characters).	Seçili tuvayı yeniden adlandırır (en fazla 24 karakter).
Repeated error creating canvases for %s	%s için tuval oluşturma hatası tekrarladı
Rescan dump	Dökümü yeniden tara
Reset	Sıfırla
Row spacing:	Satır aralığı:
Rows:	Satırlar:
Save	Kaydet
Save current	Mevcutu kaydet
Save my config to a file	Yapılandırmamı dosyaya kaydet
Save the current layout as a preset, load or delete presets.	Mevcut yerleşimi ön ayar olarak kaydet, ön ayarları yükle veya sil.
Save the current layout of all units (position, size, colours, grid, tracked entries) as a preset.	Tüm birimlerin mevcut yerleşimini (konum, boyut, renkler, ızgara, izlenen kayıtlar) ön ayar olarak kaydeder.
Save the entry and refresh both lists and the panels.	Kaydı kaydeder, iki listeyi ve panelleri yeniler.
Save the new name and rebuild the panels.	Yeni adı kaydeder ve panelleri yeniden kurar.
Saved	Kaydedildi
Saved presets:	Kayıtlı ön ayarlar:
Saved to: %s	Kaydedildi: %s
Scan dump	Dökümü tara
Scan started... the database will refresh when done	Tarama başladı... bitince veritabanı yenilenecek
Scan the client buff table again and rebuild the icon/name dump.	İstemci buff tablosunu yeniden tarar ve simge/ad dökümünü yeniden kurar.
Scan the client buff table and rebuild the icon dump (takes a moment).	İstemci buff tablosunu tarar ve simge dökümünü yeniden kurar (biraz sürer).
Seconds or percent; multiplied by the aura's stack count (1 if none).	Saniye veya yüzde; auranın yığın sayısıyla çarpılır (yoksa 1).
Select address above and copy it manually (Ctrl+C)	Yukarıdaki adresi seçip elle kopyalayın (Ctrl+C)
Select canvas:	Tuval seçin:
Select language:	Dil seçin:
Show label: OFF	Etiket: KAPALI
Show label: ON	Etiket: AÇIK
Show the %s journal.	%s kaydını gösterir.
Show the entry name under each icon of this canvas. Current: %s.	Bu tuvalde her simgenin altında kayıt adını gösterir. Şu an: %s.
Show this canvas in the settings column (entries and layout).	Bu tuvayı ayarlar sütununda gösterir (kayıtlar ve yerleşim).
Size:	Boyut:
Skill	Beceri
Skill log cleared	Beceri kaydı temizlendi
Skill: tracked from the combat log by its spell name. Fields: Name, Cooldown, Spell, icon.	Beceri: savaş kaydındaki spell adıyla izlenir. Alanlar: Name, Cooldown, Spell, simge.
Skills seen in combat log: %s	Savaş kaydındaki beceriler: %s
Skills seen in the combat log for the selected unit, newest first.	Seçili birim için savaş kaydında görülen beceriler, en yenisi önce.
Smart	Smart
Smart %:	Smart %:
Smart %: extra reduction learned for this target when the skill returns earlier than predicted (0-100).	Smart %: beceri tahmin edilenden erken döndüğünde bu hedef için öğrenilen ek kısalma (0-100).
Smart learning state for the current target: learned after an early re-use, never learned otherwise.	Geçerli hedef için Smart durumu: erken tekrar kullanımda öğrenilir, aksi halde öğrenilmez.
Smart reduction % must be a number 0..100	Smart azaltma % 0..100 arası bir sayı olmalı
Source	Kaynak
Space between our overlay row and TrackThatPlease's row, px.	Kaplama satırımız ile TrackThatPlease satırı arasındaki boşluk, px.
Spell %s	Spell %s
Spell name exactly as the combat log reports it (Skill only).	Beceri adı savaş kaydındakiyle tamamen aynı olmalı (yalnızca beceri).
Spell name is required	Beceri adı gerekli
Spell:	Spell:
Spell: OFF	Spell: KAPALI
Spell: ON	Spell: AÇIK
Start typing a skill or buff name...	Beceri veya buff adı yazmaya başlayın...
Stop tracking this entry on every canvas of this unit. The custom entry stays in the list.	Bu birimin tüm tuvallerinde izlemeyi bırakır. Özel kayıt listede kalır.
Support	Destek
Support the Addon Developer	Eklenti geliştiricisini destekleyin
Switch the canvas edited below. Shown: %s.	Aşağıda düzenlenen tuvayı değiştirir. Gösterilen: %s.
Switch the interface, every hover tooltip and all chat messages to this language.	Arayüzü, tüm ipuçlarını ve tüm sohbet mesajlarını bu dile geçirir.
TTP canvas found: %s	TTP tuvali bulundu: %s
TTP canvas not found, fallback: %s	TTP tuvali bulunamadı, yedek: %s
Target	Hedef
Target cache cleaned: %s	Hedef önbelleği temizlendi: %s
Target display modes: overlay at the target's screen position, hide the floating canvas, avoid TrackThatPlease.	Hedef görünüm modları: hedefin ekran konumunda kaplama, yüzen tuvayı gizle, TrackThatPlease'ten kaçın.
Target only. Stacks are read from the target's aura (1 if none).	Yalnızca hedef. Yığınlar hedefin aurasından okunur (yoksa 1).
Text color:	Metin rengi:
Thank you for supporting the development!	Geliştirmeyi desteklediğiniz için teşekkürler!
Thank you for your hard work!	Emeğiniz için teşekkürler!
Timer font size in pixels (8-40). Applies on Enter.	Geri sayım yazı boyutu piksel (8-40). Enter ile uygulanır.
Timer settings	Geri sayım ayarları
Track this ID/name on the current unit and canvas.	Bu ID/adı geçerli birim ve tuvalde izler.
Tracked entries:	İzlenen kayıtlar:
Tracking key of this entry; it cannot be changed here.	Bu kaydın izleme anahtarı; burada değiştirilemez.
Type	Tür
Type:	Tür:
Type: %s. Click to cycle Flat -> Percent -> Reset.	Tür: %s. Flat -> Percent -> Reset için tıklayın.
UI initialization for %s: %s	%s için arayüz başlatma: %s
Unconditional %s	Koşulsuz %s
Unit whose journal is listed below.	Kaydı aşağıda listelenen birim.
Unit whose panel is edited below. Every unit has its own canvases and tracked list.	Paneli aşağıda düzenlenen birim. Her birimin kendi tuvalleri ve izleme listesi vardır.
Unit:	Birim:
Unknown	Bilinmiyor
Up	Yukarı
Use this canvas.	Bu tuvayı kullan.
Use this custom entry.	Bu özel kaydı kullan.
Use this custom entry: %s.	Bu özel kaydı kullan: %s.
Value	Değer
Value for an unconditional modifier: seconds for +Flat, percent for +Percent (0 or more).	Koşulsuz değiştirici değeri: +Flat için saniye, +Percent için yüzde (0 veya daha fazla).
Value: %s %%.	Değer: %s %%.
Value: %s s.	Değer: %s s.
Vertical gap between grid rows, px (0-40). Applies on Enter.	Izgara satırları arası dikey boşluk, px (0-40). Enter ile uygulanır.
Write the whole configuration (custom entries, tracked lists, layouts) to a JSON file in the addon folder.	Tüm yapılandırmayı (özel kayıtlar, izleme listeleri, yerleşimler) eklenti klasöründeki bir JSON dosyasına yazar.
active	etkin
always value must be a number >= 0	always değeri 0 veya daha büyük bir sayı olmalı
aura dump -> %s	aura dökümü -> %s
aura dump: write failed	aura dökümü: yazma başarısız
buff dump: %s buffs loaded from %s	buff dökümü: %s bufflar %s kaynağından yüklendi
buff dump: %s buffs, %s skill icons	buff dökümü: %s buff, %s yetenek simgesi
buff dump: %s buffs, %s; tables=%s named=%s errors=%s%s	buff dökümü: %s buff, %s; tables=%s named=%s errors=%s%s
buff dump: '%s' -> id=%s path=%s (entries updated: %s)	buff dökümü: '%s' -> id=%s path=%s (güncellenen kayıt: %s)
buff dump: '%s' not found	buff dökümü: '%s' bulunamadı
buff journal	buff kaydı
buff scan: dumping all buffs%s (1..50000, 8000000..8001000)	buff taraması: tüm bufflar dökülüyor%s (1..50000, 8000000..8001000)
cast %s by %s (%sms)	%s kullanımı, %s (%s ms)
custom entry removed: %s	özel kayıt silindi: %s
custom: id=%s name=%s spell=%s CD=%s D=%s	custom: id=%s name=%s spell=%s CD=%s D=%s
effective CD: reset '%s' zeroed %s on target %s	etkin CD: '%s' sıfırlaması %s kaydını %s hedefinde sıfırladı
effective CD: smart %.1f%% learned for %s on target %s (applied after %.2f s < %.2f s)	etkin CD: %s için %s hedefinde smart %.1f%% öğrenildi (%.2f s < %.2f s sonra kullanıldı)
effective CD: target %s class %s -> %s, smart reset for this target	etkin CD: hedef %s sınıfı %s -> %s, bu hedef için smart sıfırlandı
enter a buff ID or name	bir buff ID'si veya adı girin
entry %s: type=%s CD=%s D=%s%s	kayıt %s: type=%s CD=%s D=%s%s
faded	soldu
hide	gizle
icon from dump: %s -> %s	dökümden simge: %s -> %s
icon learned for spell %s: %s	%s becerisi için simge öğrenildi: %s
icon lookup id=%s -> path=%s name=%s%s	simge arama id=%s -> path=%s name=%s%s
icon picked: %s -> %s	simge seçildi: %s -> %s
icon: no spellId in event for '%s'	simge: '%s' için olayda spellId yok
invalid modifier source	geçersiz değiştirici kaynağı
mana cast %s cost=%s spend=%.1f regen=%.1f mount=%s	mana kullanımı %s cost=%s spend=%.1f regen=%.1f mount=%s
mana drop %.1f (regen %.1f) — no match; pet='%s'; mount-blocked=%d cd-blocked=%d; entries: %s	mana düşüşü %.1f (regen %.1f) — eşleşme yok; pet='%s'; mount-blocked=%d cd-blocked=%d; kayıtlar: %s
modifier %s: value must be a number >= 0	değiştirici %s: değer 0'dan büyük veya eşit bir sayı olmalı
msg %s src=%s tgt=%s spell=%s id=%s	msg %s src=%s tgt=%s spell=%s id=%s
parsed: spellId=%s spellName=%s	ayrıştırma: spellId=%s spellName=%s
saved to buff_dump.tbl	buff_dump.tbl dosyasına kaydedildi
settings window rebuild failed: %s	ayarlar penceresi yeniden kurulamadı: %s
show	göster
skill icon: %s	beceri simgesi: %s
skill log	beceri kaydı
timer %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s	zamanlayıcı %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s
too many modifiers	çok fazla değiştirici
updateVisibleItems not found!	updateVisibleItems bulunamadı!
]==]
dict.ko = [==[
 (active)	 (활성)
 (no target)	 (대상 없음)
 (was %s)	 (이전: %s)
 + search '%s'	 + 검색 '%s'
 | first error: %s	 | 첫 오류: %s
%d. buff ID: %s	%d. 버프 ID: %s
%d. debuff ID: %s	%d. 디버프 ID: %s
%s (id %s) - %s, seen %s time(s).	%s (ID %s) - %s, %s회 확인됨.
%s (id %s) on canvas %s.	%s (ID %s), 캔버스 %s.
%s - %s. Click to apply this icon.	%s - %s. 이 아이콘을 적용하려면 클릭하세요.
%s - buff ID: %s, unit: %s	%s - 버프 ID: %s, 유닛: %s
%s - seen %s time(s) in the combat log.	%s - 전투 기록에서 %s회 확인됨.
%s args: %s	%s 인자: %s
%s buff added for tracking: %s (%s)	%s 버프 추적 추가됨: %s (%s)
%s buff removed from tracking: %s	%s 버프 추적 해제됨: %s
%s tracked entries will be removed from this unit.	이 유닛에서 추적 항목 %s개가 제거됩니다.
'%s': cooldown recorded for %s (unit %s)	'%s': %s의 재사용 대기시간 기록됨 (유닛 %s)
'%s': no source in the event	'%s': 이벤트에 시전자 없음
'%s': repeat trigger after %.1f s - ignored (window %s)	'%s': %.1f초 후 중복 트리거 - 무시됨 (창 %s)
'%s': self cast -> Player/Mount panels: %s	'%s': 자신에게 시전 -> Player/Mount 패널: %s
'%s': self cast, but the buff is not tracked on Player/Mount	'%s': 자신에게 시전했지만 버프가 Player/Mount에서 추적되지 않습니다
'%s': source %s unknown, waiting for the first target	'%s': 시전자 %s을(를) 알 수 없어 첫 대상을 기다립니다
'%s': you are the current target -> recorded to Target	'%s': 현재 대상이 자신 -> Target에 기록됨
(no target)	(대상 없음)
(set at creation, cannot be changed)	(생성 시 설정되며 변경할 수 없습니다)
* Mount	* 탈것
* Player	* 플레이어
* Target	* 대상
+Flat	+고정
+Flat: subtract N seconds, applied before the percentages.	+Flat: N초를 빼며, 퍼센트보다 먼저 적용됩니다.
+Percent	+퍼센트
+Percent: subtract N %, applied after all flat reductions.	+Percent: N %를 빼며, 모든 고정 감소 이후에 적용됩니다.
Active	활성
Active buffs for %s (%d):	%s의 활성 버프 (%d):
Active debuffs for %s (%d):	%s의 활성 디버프 (%d):
Active preset: %s	활성 프리셋: %s
Active preset: None	활성 프리셋: 없음
Add	추가
Add a canvas: copies this layout and places the copy below it.	캔버스 추가: 이 레이아웃을 복사해 아래에 배치합니다.
Add a custom entry: pick the type first, the fields below follow it, then Add entry.	사용자 지정 항목 추가: 먼저 유형을 선택하면 아래 필드가 따라 바뀌고, 그다음 Add entry를 누르세요.
Add custom entry:	사용자 지정 항목 추가:
Add entry	항목 추가
Add this entry to tracking on the current unit and canvas.	현재 유닛과 캔버스의 추적에 항목을 추가합니다.
Add this source as a modifier (condition On target, type Flat, value 0).	이 출처를 수정자로 추가 (조건 On target, 유형 Flat, 값 0).
Add to tracking on the current unit (creates a custom entry with a default CD/D when needed).	현재 유닛 추적에 추가 (필요하면 기본 CD/D로 사용자 지정 항목 생성).
Add: buff -> custom entry + tracking. Skill -> custom entry with Spell filled.	Add: 버프 -> 사용자 지정 항목 + 추적. 스킬 -> Spell이 채워진 항목.
Added skill: %s	스킬 추가됨: %s
Added to %s	%s에 추가됨
Added: %s	추가됨: %s
Addon Options	애드온 옵션
Already tracked (%s)	이미 추적 중 (%s)
Already tracked: %s	이미 추적 중: %s
Also fill the entry's Spell field with the picked buff name.	선택한 버프 이름을 항목의 Spell 필드에도 채웁니다.
Always	항상
Always:	항상:
Apply icon, grid, position and timer values. Enter inside a field applies it too.	아이콘, 그리드, 위치, 카운트다운 값을 적용합니다. 필드에서 Enter를 눌러도 적용됩니다.
Apply the modifiers below to this entry's cooldown (buff/debuff and skill, target only).	아래 수정자를 이 항목의 재사용 대기시간에 적용 (버프/디버프 및 스킬, 대상 전용).
Aura (or entry) the modifier counts for; stacks are read from the target.	수정자가 계산되는 오라(또는 항목)이며, 스택은 대상에서 읽습니다.
Avoid TrackThatPlease	TrackThatPlease 회피
Base CD: %s s	기본 CD: %s초
Base CD: -	기본 CD: -
Base cooldown of the entry, seconds (the Cooldown field).	항목의 기본 재사용 대기시간(초)이며 Cooldown 필드 값입니다.
Buff debug mode disabled.	버프 디버그 모드가 비활성화되었습니다.
Buff debug mode enabled. Buff IDs will be displayed in chat.	버프 디버그 모드가 활성화되었습니다. 버프 ID가 채팅에 표시됩니다.
Buff debug mode is disabled. Enable it in settings.	버프 디버그 모드가 꺼져 있습니다. 설정에서 켜세요.
Buff journal: every buff/debuff seen while Debug is ON, active and faded, newest first.	버프 기록: Debug가 켜져 있는 동안 확인된 모든 버프/디버프(활성 및 해제), 최신 순.
Buff lists refreshed after import	가져오기 후 버프 목록이 새로고침되었습니다
Buff log	버프 기록
Buff log cleared	버프 기록이 지워졌습니다
Buff, debuff or skill ID (a name from Custom entries also works). Type to filter, Enter or Add to track it.	버프, 디버프 또는 스킬 ID (사용자 지정 항목의 이름도 가능). 입력하면 필터링되고 Enter 또는 Add로 추적합니다.
Buff/Debuff	버프/디버프
Buff/debuff ID, e.g. 800004. Required for Buff/Debuff entries.	버프/디버프 ID (예: 800004). Buff/Debuff 항목에 필수입니다.
Buffs seen: %s (active %s)	확인된 버프: %s (활성 %s)
CD %s s	CD %s초
CD/D %s: CD=%s D=%s	CD/D %s: CD=%s D=%s
Cancel	취소
Canvas %s	캔버스 %s
Canvas model ready: playerpet=%s player=%s target=%s	캔버스 모델 준비됨: playerpet=%s player=%s target=%s
Canvas:	캔버스:
Canvas: %s	캔버스: %s
Canvas: one independent icon panel. A unit can own several canvases.	캔버스: 독립적인 아이콘 패널입니다. 한 유닛에 여러 캔버스를 둘 수 있습니다.
Canvases	캔버스
Clear log	기록 지우기
Clear the %s of the selected unit.	선택한 유닛의 %s을(를) 지웁니다.
Close	닫기
Close the Record window.	Record 창을 닫습니다.
Close the icon search without changing the icon.	아이콘을 바꾸지 않고 아이콘 검색을 닫습니다.
Close the settings window (Esc).	설정 창을 닫습니다 (Esc).
Close the window (Esc).	창을 닫습니다 (Esc).
Close without deleting.	삭제하지 않고 닫습니다.
Close without renaming.	이름을 바꾸지 않고 닫습니다.
Close without saving.	저장하지 않고 닫습니다.
Columns:	열:
Condition	조건
Condition: %s (click to toggle). On target counts only while the aura is up.	조건: %s (클릭하여 전환). On target은 오라가 있을 때만 계산됩니다.
Configuration imported from file - window closed	구성 파일을 가져왔습니다 - 창이 닫혔습니다
Configuration imported successfully	구성을 성공적으로 가져왔습니다
Configuration saved to file: %s	구성을 파일로 저장했습니다: %s
Containers not found!	컨테이너를 찾을 수 없습니다!
Cooldown / Duration are seconds; 0 is valid. Icon is optional.	Cooldown / Duration은 초 단위이며 0도 유효합니다. 아이콘은 선택 사항입니다.
Cooldown Buff Tracker	버프 및 재사용 대기시간 추적기
Cooldown in seconds, 0 is allowed.	재사용 대기시간(초), 0도 유효합니다.
Cooldown must be a number >= 0	재사용 대기시간은 0 이상의 숫자여야 합니다
Cooldown:	재사용 대기시간:
Cooldown: %s s.	재사용 대기시간: %s초.
Could not read file: %s (put it into the CooldawnBuffTracker folder)	파일을 읽을 수 없습니다: %s (CooldawnBuffTracker 폴더에 넣으세요)
Could not save file: %s	파일을 저장할 수 없습니다: %s
Countdown text colour. Click to open the palette.	카운트다운 텍스트 색상입니다. 클릭하면 팔레트가 열립니다.
Countdown text of the selected canvas.	선택한 캔버스의 카운트다운 텍스트입니다.
Create the entry with these values and track it on the current canvas.	이 값으로 항목을 만들어 현재 캔버스에서 추적합니다.
Custom entries:	사용자 지정 항목:
Custom entries: ID, name, cooldown and duration used by the tracked list on every unit.	사용자 지정 항목: 모든 유닛의 추적 목록이 사용하는 ID, 이름, 재사용 대기시간, 지속시간입니다.
Debug mode already initialized, skipping.	디버그 모드가 이미 초기화되어 건너뜁니다.
Debug: OFF	디버그: 끔
Debug: ON	디버그: 켬
Debug: print buff IDs, combat-log details and the buff journal to chat; shows Record. Current: %s.	디버그: 버프 ID, 전투 기록 세부 정보, 버프 기록을 채팅에 출력하고 Record를 표시합니다. 현재: %s.
Delete	삭제
Delete canvas	캔버스 삭제
Delete canvas "%s"?	캔버스 "%s"을(를) 삭제할까요?
Delete preset %s. Cannot be undone.	프리셋 %s을(를) 삭제합니다. 되돌릴 수 없습니다.
Delete the selected canvas and untrack its entries (asks first).	선택한 캔버스를 삭제하고 해당 항목 추적을 해제합니다 (먼저 확인).
Delete this canvas and untrack the entries it holds. Cannot be undone.	이 캔버스를 삭제하고 항목 추적을 해제합니다. 되돌릴 수 없습니다.
Delete this custom entry and remove it from tracking on every unit.	이 사용자 지정 항목을 삭제하고 모든 유닛에서 추적을 해제합니다.
Donate EthereumX (ETX):	EthereumX (ETX) 후원:
Donate USDT ERC20:	USDT ERC20 후원:
Donate USDT SOL:	USDT SOL 후원:
Donate USDT TON:	USDT TON 후원:
Donate USDT TRC20:	USDT TRC20 후원:
Donation address. Click the field, select it and copy with Ctrl+C.	후원 주소입니다. 필드를 클릭해 선택한 뒤 Ctrl+C로 복사하세요.
Down	아래로
Drag to move the window.	창을 옮기려면 드래그하세요.
Draw an additional compact overlay at the target's screen position. It does not hide the floating canvas; use Hide target canvas for that.	대상의 화면 위치에 추가로 간결한 오버레이를 그립니다. 부동 캔버스는 숨기지 않으며, 숨기려면 Hide target canvas를 사용하세요.
Dump scan started...	덤프 스캔이 시작되었습니다...
Duration in seconds, 0 is allowed (Buff/Debuff only).	지속시간(초), 0도 유효합니다 (버프/디버프 전용).
Duration must be a number >= 0	지속시간은 0 이상의 숫자여야 합니다
Duration:	지속시간:
Duration: %s s.	지속시간: %s초.
EXPORT - save your current setup to a file:	내보내기 - 현재 설정을 파일로 저장:
Edit	편집
Edit the Mount (pet) panel settings.	Mount(탈것) 패널 설정을 편집합니다.
Edit the Player panel settings.	Player 패널 설정을 편집합니다.
Edit the Target panel settings, including the target overlay.	Target 패널 설정을 편집합니다 (대상 오버레이 포함).
Edit this entry: cooldown, duration, spell or mana, icon and effective CDs.	이 항목 편집: 재사용 대기시간, 지속시간, spell 또는 마나, 아이콘, 유효 재사용 대기시간.
Effective CDs	유효 재사용 대기시간
Effective cooldown right now: max(0, base - flat) x (1 - percent / 100). '(no target)' means no aura snapshot, so only Always modifiers count.	현재 유효 재사용 대기시간: max(0, base - flat) x (1 - percent / 100). '(no target)'은 오라 스냅샷이 없어 Always 수정자만 계산된다는 뜻입니다.
Effective now: %s	현재 유효: %s
Effective now: -	현재 유효: -
Empty preset name	프리셋 이름이 비어 있습니다
Enable user-defined cooldown modifiers for this entry (target only).	이 항목에 사용자 지정 재사용 대기시간 수정자를 활성화합니다 (대상 전용).
Enter the name of the config file first	먼저 구성 파일 이름을 입력하세요
Entries drawn on the selected canvas of this unit. Up/Down change their order, Remove untracks them.	이 유닛의 선택한 캔버스에 표시되는 항목입니다. Up/Down은 순서를 바꾸고 Remove는 추적을 해제합니다.
Entries in the current tab; buffs also show how many are active.	현재 탭의 항목 수이며, 버프는 활성 개수도 표시합니다.
Entry ID (tracking key): %s.	항목 ID (추적 키): %s.
Entry icon. Click to pick one from the buff dump; optional.	항목 아이콘입니다. 클릭하면 버프 덤프에서 선택합니다. 선택 사항입니다.
Entry type, fixed at creation. Delete and re-create the entry to change it. Buff/Debuff has an aura, Skill is read from the combat log, Mana skill from pet mana.	유형은 생성 시 고정됩니다. 변경하려면 항목을 삭제하고 다시 만드세요. 버프/디버프는 오라로, 스킬은 전투 기록으로, 탈것 스킬은 펫 마나로 읽습니다.
Entry: cooldown / duration	항목: 재사용 대기시간 / 지속시간
Error creating canvases for %s	%s 캔버스 생성 오류
Error: %s	오류: %s
Error: '%s' not found - add it as a custom buff first	오류: '%s'을(를) 찾을 수 없습니다 - 먼저 사용자 지정 항목으로 추가하세요
Error: Buff already tracked or error occurred	오류: 버프가 이미 추적 중이거나 오류가 발생했습니다
Error: Configuration must be a table	오류: 구성이 테이블이어야 합니다
Error: Custom buff at index %s is not a table	오류: %s번째 사용자 지정 항목이 테이블이 아닙니다
Error: Custom buff at index %s missing required fields	오류: %s번째 사용자 지정 항목에 필수 필드가 없습니다
Error: Failed to get current settings	오류: 현재 설정을 가져올 수 없습니다
Error: ID, name, cooldown and duration are required	오류: ID, 이름, 재사용 대기시간, 지속시간이 필요합니다
Error: Invalid JSON format	오류: 잘못된 JSON 형식
Error: Missing required fields (customBuffs, trackedBuffs)	오류: 필수 필드가 없습니다 (customBuffs, trackedBuffs)
Error: Missing trackedBuffs fields (playerpet, player, target)	오류: trackedBuffs 필드가 없습니다 (playerpet, player, target)
Error: cooldown must be 0 or more	오류: 재사용 대기시간은 0 이상이어야 합니다
Error: customBuffs and trackedBuffs must be tables	오류: customBuffs와 trackedBuffs가 테이블이어야 합니다
Error: duration must be 0 or more	오류: 지속시간은 0 이상이어야 합니다
Error: enter a buff ID or the skill name	오류: 버프 ID 또는 스킬 이름을 입력하세요
Error: entry with this ID already exists	오류: 이 ID의 항목이 이미 있습니다
Error: name, cooldown, mana cost and mount name are required	오류: 이름, 재사용 대기시간, 마나 소모, 탈것 이름이 필요합니다
Error: spell name and cooldown are required	오류: 스킬 이름과 재사용 대기시간이 필요합니다
Error: the last canvas cannot be deleted	오류: 마지막 캔버스는 삭제할 수 없습니다
Error: trackedBuffs.%s contains non-number at index %s	오류: trackedBuffs.%s의 %s번째 값이 숫자가 아닙니다
Error: trackedBuffs.%s is not a table	오류: trackedBuffs.%s이(가) 테이블이 아닙니다
Export the whole configuration to a file or import a received one.	전체 구성을 파일로 내보내거나 받은 구성을 가져옵니다.
Failed to create settings window!	설정 창을 만들 수 없습니다!
Failed to delete preset	프리셋 삭제 실패
Failed to encode configuration: %s	구성을 인코딩할 수 없습니다: %s
Failed to get settings for export	내보낼 설정을 가져올 수 없습니다
Failed to load buff_helper.lua, using placeholder	buff_helper.lua를 불러오지 못해 자리표시자를 사용합니다
Failed to load buffs_to_track.lua, using settings	buffs_to_track.lua를 불러오지 못해 설정을 사용합니다
Failed to load preset	프리셋 불러오기 실패
Failed to read settings	설정을 읽을 수 없습니다
Failed to write config file: %s	구성 파일을 쓸 수 없습니다: %s
Failed to write file	파일을 쓸 수 없습니다
Failed: %s	실패: %s
File has an unexpected format	파일 형식이 예상과 다릅니다
File name (file must be in the CooldawnBuffTracker folder):	파일 이름 (파일은 CooldawnBuffTracker 폴더에 있어야 합니다):
File name inside the CooldawnBuffTracker folder; the extension is optional.	CooldawnBuffTracker 폴더 안의 파일 이름이며 확장자는 선택 사항입니다.
Filter by buff or skill name (English names). An empty field lists the whole dump.	버프 또는 스킬 이름(영문)으로 필터링합니다. 비어 있으면 전체 덤프를 표시합니다.
Flat	고정
Flat = seconds, Percent = %, Reset = zero the timer when the aura appears.	Flat = 초, Percent = %, Reset = 오라가 나타나면 타이머를 0으로 만듭니다.
Flat modifiers counted right now, in seconds. Applied first, multiplied by aura stacks.	현재 계산된 고정 수정자(초). 먼저 적용되며 오라 스택이 곱해집니다.
Flat total: %s	고정 합계: %s
Flat total: -	고정 합계: -
Font size:	글꼴 크기:
Found: %s (click a row to apply the icon)	찾음: %s (아이콘을 적용하려면 행을 클릭하세요)
Gap to the TrackThatPlease row, px (0-40).	TrackThatPlease 행까지의 간격(픽셀, 0-40).
Gap:	간격:
Grid (cols x rows):	그리드 (열 x 행):
Grid rows (1-10). Applies on Enter.	그리드 행 (1-10). Enter로 적용됩니다.
Grid: icons per row, number of rows, the cap and the vertical gap.	그리드: 행당 아이콘 수, 행 수, 최대치, 세로 간격.
Helpers module not loaded, using basic settings	helpers 모듈이 로드되지 않아 기본 설정을 사용합니다
Hide every floating target canvas. Buff data keeps running and the Target Overlay still draws when it is on.	모든 부동 대상 캔버스를 숨깁니다. 버프 데이터는 계속 동작하며 Target Overlay가 켜져 있으면 계속 그려집니다.
Hide target canvas	대상 캔버스 숨기기
Horizontal gap between icons, px (0-40). Applies on Enter.	아이콘 사이 가로 간격(픽셀, 0-40). Enter로 적용됩니다.
ID/name:	ID/이름:
ID:	ID:
IMPORT - load a config you received	가져오기 - 받은 구성 불러오기
Icon layout of the selected canvas: size, spacing, label and grid.	선택한 캔버스의 아이콘 레이아웃: 크기, 간격, 라벨, 그리드.
Icon position	아이콘 위치
Icon search	아이콘 검색
Icon settings	아이콘 설정
Icon size in pixels (16-64). Applies on Enter.	아이콘 크기(픽셀, 16-64). Enter로 적용됩니다.
Icon size of the overlay, px (12-64).	오버레이의 아이콘 크기(픽셀, 12-64).
Icon size:	아이콘 크기:
Icon spacing:	아이콘 간격:
Icons per overlay row (1-12). Extra icons wrap downwards.	오버레이 행당 아이콘 (1-12). 초과분은 아래로 줄바꿈됩니다.
Icons per row (1-20). Applies on Enter.	행당 아이콘 (1-20). Enter로 적용됩니다.
Import / Export Configuration	구성 가져오기 / 내보내기
Import failed: configuration must be a table	가져오기 실패: 구성이 테이블이어야 합니다
Import failed: could not read the current settings	가져오기 실패: 현재 설정을 읽을 수 없습니다
Import failed: custom entry at index %s is not a table	가져오기 실패: %s번째 사용자 지정 항목이 테이블이 아닙니다
Import failed: custom entry at index %s missing required fields	가져오기 실패: %s번째 사용자 지정 항목에 필수 필드가 없습니다
Import failed: customBuffs and trackedBuffs must be tables	가져오기 실패: customBuffs와 trackedBuffs가 테이블이어야 합니다
Import failed: invalid JSON format - %s	가져오기 실패: 잘못된 JSON 형식 - %s
Import failed: missing required fields	가져오기 실패: 필수 필드가 없습니다
Import failed: missing trackedBuffs fields	가져오기 실패: trackedBuffs 필드가 없습니다
Import failed: trackedBuffs.%s contains a non-number at index %s	가져오기 실패: trackedBuffs.%s의 %s번째 값이 숫자가 아닙니다
Import failed: trackedBuffs.%s is not a table	가져오기 실패: trackedBuffs.%s이(가) 테이블이 아닙니다
Import field is empty - paste a configuration into the lower field first	가져오기 필드가 비어 있습니다 - 먼저 아래 필드에 구성을 붙여넣으세요
Import from file failed: %s	파일 가져오기 실패: %s
Import from file: no file name entered	파일 가져오기: 파일 이름이 입력되지 않았습니다
Import/Export	가져오기/내보내기
Import: the Import field is empty - paste a configuration into the lower field first	가져오기: 필드가 비어 있습니다 - 먼저 아래 필드에 구성을 붙여넣으세요
Interface language: the whole UI, every hover tooltip and all chat messages switch at once. The settings window rebuilds; no /reload needed.	인터페이스 언어: 전체 UI, 모든 툴팁, 모든 채팅 메시지가 한 번에 전환됩니다. 설정 창이 다시 만들어지며 /reload는 필요 없습니다.
Invalid buff ID	잘못된 버프 ID
Invalid spell name	잘못된 스킬 이름
Keep the target overlay above TrackThatPlease's target row. Anchors to its real target canvas (targetBuffCanvas) when it can be found, otherwise places the row with targetBuffVerticalOffset, targetIconSize and the UI scale. Turn off to use the canvas offsets instead.	대상 오버레이를 TrackThatPlease 대상 행 위에 유지합니다. 실제 대상 캔버스(targetBuffCanvas)를 찾으면 거기에 고정하고, 없으면 targetBuffVerticalOffset, targetIconSize, UI 배율로 배치합니다. 끄면 캔버스 오프셋으로 배치합니다.
Label color:	이름 색상:
Language	언어
Language changed to %s	언어가 %s(으)로 변경되었습니다
Language: %s	언어: %s
Learned for this target (+%s%%)	이 대상에 대해 학습됨 (+%s%%)
Load	불러오기
Load config from file	파일에서 구성 불러오기
Load preset %s: position, size, colours and tracked entries.	프리셋 %s 불러오기: 위치, 크기, 색상, 추적 항목.
Loading CooldawnBuffTracker %s by %s	CooldawnBuffTracker %s 로드 중, 제작자 %s
Lock: OFF	잠금: 끔
Lock: ON	잠금: 켬
Lock: ON disables dragging this panel with the mouse. Current: %s.	잠금: 켬이면 이 패널을 마우스로 끌 수 없습니다. 현재: %s.
Log skills	스킬 기록
Mana %s	마나 %s
Mana cost must be > 0	마나 소모는 0보다 커야 합니다
Mana cost of the mount skill, used to detect the spend (Mana skill only).	탈것 스킬의 마나 소모량으로 사용 여부를 감지합니다 (탈것 스킬 전용).
Mana skill	탈것 스킬
Mana skill: mount skill tracked by the pet's mana spend. Fields: Name, Cooldown, Mana, Mount, icon.	탈것 스킬: 펫의 마나 소모로 추적합니다. 필드: Name, Cooldown, Mana, Mount, 아이콘.
Mana:	마나:
Matches for the current query. Click a row to apply its icon.	현재 검색어의 결과입니다. 행을 클릭하면 해당 아이콘이 적용됩니다.
Max icons drawn on this canvas (1 to Columns x Rows). Applies on Enter.	이 캔버스에 표시할 최대 아이콘 수 (1 ~ 열 x 행). Enter로 적용됩니다.
Max icons:	최대 아이콘:
Mir OFF	Mir 끔
Mir ON	Mir 켬
Mirror this player aura on the Target panel (buff/debuff only). Current: %s.	이 플레이어 오라를 Target 패널에 미러링합니다 (버프/디버프 전용). 현재: %s.
Modifier source: %s.	수정자 출처: %s.
Modifier source: buff ID, name or spell of a custom entry. Its aura is checked on the target.	수정자 출처: 사용자 지정 항목의 버프 ID, 이름 또는 spell입니다. 대상에서 해당 오라를 확인합니다.
Modifiers	수정자
Mount	탈것
Mount %s	탈것 %s
Mount buff list updated: was %s, now %s	탈것 버프 목록 갱신됨: 이전 %s, 현재 %s
Mount name is required	탈것 이름이 필요합니다
Mount name the skill belongs to (Mana skill only).	스킬이 속한 탈것 이름 (탈것 스킬 전용).
Mount:	탈것:
Move entry to canvas	항목을 캔버스로 이동
Move the entry to this canvas.	항목을 이 캔버스로 옮깁니다.
Move this entry one place down inside the canvas.	캔버스 안에서 항목을 한 칸 아래로 옮깁니다.
Move this entry one place up inside the canvas.	캔버스 안에서 항목을 한 칸 위로 옮깁니다.
Move this entry to another canvas of the same unit.	같은 유닛의 다른 캔버스로 항목을 옮깁니다.
Mv	이동
NOT saved (api.File unavailable)	저장되지 않음 (api.File 사용 불가)
Name for the new preset, up to 40 characters. Must be unique.	새 프리셋 이름(최대 40자). 고유해야 합니다.
Name is required	이름이 필요합니다
Name label colour under the icons. Click to open the palette.	아이콘 아래 이름 색상입니다. 클릭하면 팔레트가 열립니다.
Name shown on the canvas instead of the ID.	ID 대신 캔버스에 표시할 이름입니다.
Name shown on the canvas: %s.	캔버스에 표시되는 이름: %s.
Name:	이름:
Native frame display	기본 프레임 표시
New canvas name, up to 24 characters. Enter saves.	새 캔버스 이름(최대 24자). Enter로 저장합니다.
New preset name:	새 프리셋 이름:
Next page of custom entries.	다음 사용자 지정 항목 페이지.
Next page of presets.	다음 프리셋 페이지.
Next page of results.	다음 결과 페이지.
Next page of tracked entries.	다음 추적 항목 페이지.
Next page.	다음 페이지.
No active buffs	활성 버프 없음
No active debuffs	활성 디버프 없음
No custom entries yet	아직 사용자 지정 항목이 없습니다
No presets saved	저장된 프리셋이 없습니다
No target selected	선택된 대상 없음
Not learned	학습되지 않음
Nothing found. Press Scan dump or change the query.	찾은 결과가 없습니다. Scan dump를 누르거나 검색어를 변경하세요.
Nothing tracked yet	아직 추적 중인 항목이 없습니다
OFF	끔
ON	켬
On target	대상에게
On target = only while the aura is on the target; Always = always counts.	On target = 대상에게 오라가 있을 때만, Always = 항상 계산합니다.
Open the support window (donation addresses).	후원 창을 엽니다 (후원 주소).
Open the support window with the donation addresses.	후원 주소가 있는 지원 창을 엽니다.
Overlay X offset from the target's anchor (ignored while Avoid TrackThatPlease is on).	대상 기준점에서 오버레이 X 오프셋 (Avoid TrackThatPlease가 켜져 있으면 무시됨).
Overlay X offset from the target's anchor, px.	대상 기준점에서 오버레이 X 오프셋(픽셀).
Overlay Y offset from the target's anchor, px (negative = above).	대상 기준점에서 오버레이 Y 오프셋(픽셀, 음수 = 위).
Overlay around target	대상 주변 오버레이
Overlay icon size, px (12-64).	오버레이 아이콘 크기(픽셀, 12-64).
Page %s - 7 presets per page.	페이지 %s - 페이지당 프리셋 7개.
Page %s - 8 entries per page.	페이지 %s - 페이지당 8개 항목.
Page %s - 9 entries per page.	페이지 %s - 페이지당 9개 항목.
Page %s - 9 icons per page.	페이지 %s - 페이지당 아이콘 9개.
Panel X on screen, px from the left edge (negative values are allowed).	화면에서 패널 X(왼쪽 가장자리 기준 픽셀, 음수 허용).
Panel Y on screen, px from the top edge (negative values are allowed).	화면에서 패널 Y(위쪽 가장자리 기준 픽셀, 음수 허용).
Panel position on screen, in pixels from the top-left corner.	화면에서 패널 위치(왼쪽 위 모서리 기준 픽셀).
Per row:	행당:
Percent	퍼센트
Percent modifiers counted right now plus the learned Smart %, added together. Applied second.	현재 계산된 퍼센트 수정자와 학습된 Smart %를 합산합니다. 두 번째로 적용됩니다.
Percent total: %s	퍼센트 합계: %s
Percent total: -	퍼센트 합계: -
Place the overlay above TrackThatPlease's target row (anchored to its row when it can be found).	오버레이를 TrackThatPlease 대상 행 위에 배치합니다 (행을 찾으면 거기에 고정).
Player	플레이어
Player buff list updated: was %s, now %s	플레이어 버프 목록 갱신됨: 이전 %s, 현재 %s
Position X:	위치 X:
Position Y:	위치 Y:
Potential: %s s	잠재: %s초
Potential: -	잠재: -
Potential: every modifier counted with stacks 1 and auras assumed up - the best case for this build.	잠재: 모든 수정자를 1스택, 모든 오라가 걸려 있다고 가정한 최선의 경우입니다.
Preset %s%s: Load applies its layout to all units, Delete removes it.	프리셋 %s%s: Load는 모든 유닛에 레이아웃을 적용하고 Delete는 삭제합니다.
Preset already exists: %s	프리셋이 이미 있습니다: %s
Preset currently applied to all three units.	현재 세 유닛 모두에 적용된 프리셋입니다.
Preset deleted: %s	프리셋 삭제됨: %s
Preset loaded: %s	프리셋 불러옴: %s
Preset name cannot be empty	프리셋 이름은 비울 수 없습니다
Preset not found	프리셋을 찾을 수 없습니다
Preset not found: %s	프리셋을 찾을 수 없습니다: %s
Preset saved: %s	프리셋 저장됨: %s
Presets	프리셋
Presets *	프리셋 *
Previous page of custom entries.	이전 사용자 지정 항목 페이지.
Previous page of presets.	이전 프리셋 페이지.
Previous page of results.	이전 결과 페이지.
Previous page of tracked entries.	이전 추적 항목 페이지.
Previous page.	이전 페이지.
Re-apply the active preset %s.	활성 프리셋 %s을(를) 다시 적용합니다.
Read the file and apply it: replaces custom entries, tracked lists and unit layouts.	파일을 읽어 적용합니다: 사용자 지정 항목, 추적 목록, 유닛 레이아웃을 교체합니다.
Received buff list update event	버프 목록 업데이트 이벤트를 받았습니다
Record (Debug)	Record (디버그)
Record window (needs Debug: ON): buffs seen and skills from the combat log, with one-click Add.	Record 창 (Debug: ON 필요): 확인된 버프와 전투 기록의 스킬을 한 번의 클릭으로 Add.
Reference	참조
Remove	제거
Remove this modifier from the entry.	이 수정자를 항목에서 제거합니다.
Rename	이름 변경
Rename canvas	캔버스 이름 변경
Rename the selected canvas (up to 24 characters).	선택한 캔버스 이름을 바꿉니다 (최대 24자).
Repeated error creating canvases for %s	%s 캔버스 생성 오류가 반복되었습니다
Rescan dump	덤프 다시 스캔
Reset	초기화
Row spacing:	행 간격:
Rows:	행:
Save	저장
Save current	현재 저장
Save my config to a file	내 구성을 파일로 저장
Save the current layout as a preset, load or delete presets.	현재 레이아웃을 프리셋으로 저장하거나 프리셋을 불러오고 삭제합니다.
Save the current layout of all units (position, size, colours, grid, tracked entries) as a preset.	모든 유닛의 현재 레이아웃(위치, 크기, 색상, 그리드, 추적 항목)을 프리셋으로 저장합니다.
Save the entry and refresh both lists and the panels.	항목을 저장하고 두 목록과 패널을 새로고침합니다.
Save the new name and rebuild the panels.	새 이름을 저장하고 패널을 다시 구성합니다.
Saved	저장됨
Saved presets:	저장된 프리셋:
Saved to: %s	저장 위치: %s
Scan dump	덤프 스캔
Scan started... the database will refresh when done	스캔이 시작되었습니다... 완료되면 데이터베이스가 갱신됩니다
Scan the client buff table again and rebuild the icon/name dump.	클라이언트 버프 테이블을 다시 스캔해 아이콘/이름 덤프를 재구성합니다.
Scan the client buff table and rebuild the icon dump (takes a moment).	클라이언트 버프 테이블을 스캔해 아이콘 덤프를 다시 만듭니다 (잠시 걸립니다).
Seconds or percent; multiplied by the aura's stack count (1 if none).	초 또는 퍼센트이며, 오라 스택 수와 곱해집니다 (없으면 1).
Select address above and copy it manually (Ctrl+C)	위 주소를 선택해 직접 복사하세요 (Ctrl+C)
Select canvas:	캔버스를 선택하세요:
Select language:	언어를 선택하세요:
Show label: OFF	라벨 표시: 끔
Show label: ON	라벨 표시: 켬
Show the %s journal.	%s 기록을 표시합니다.
Show the entry name under each icon of this canvas. Current: %s.	이 캔버스의 각 아이콘 아래에 항목 이름을 표시합니다. 현재: %s.
Show this canvas in the settings column (entries and layout).	이 캔버스를 설정 열에 표시합니다 (항목과 레이아웃).
Size:	크기:
Skill	스킬
Skill log cleared	스킬 기록이 지워졌습니다
Skill: tracked from the combat log by its spell name. Fields: Name, Cooldown, Spell, icon.	스킬: 전투 기록의 spell 이름으로 추적합니다. 필드: Name, Cooldown, Spell, 아이콘.
Skills seen in combat log: %s	전투 기록의 스킬: %s
Skills seen in the combat log for the selected unit, newest first.	선택한 유닛의 전투 기록 스킬, 최신 순.
Smart	Smart
Smart %:	Smart %:
Smart %: extra reduction learned for this target when the skill returns earlier than predicted (0-100).	Smart %: 스킬이 예상보다 빨리 돌아올 때 이 대상에 대해 학습되는 추가 감소 (0-100).
Smart learning state for the current target: learned after an early re-use, never learned otherwise.	현재 대상의 Smart 학습 상태: 예상보다 빨리 다시 사용하면 학습되고, 그렇지 않으면 학습되지 않습니다.
Smart reduction % must be a number 0..100	Smart 감소 %는 0..100 사이의 숫자여야 합니다
Source	출처
Space between our overlay row and TrackThatPlease's row, px.	오버레이 행과 TrackThatPlease 행 사이 간격(픽셀).
Spell %s	Spell %s
Spell name exactly as the combat log reports it (Skill only).	전투 기록에 나오는 스킬 이름과 정확히 같아야 합니다 (스킬 전용).
Spell name is required	스킬 이름이 필요합니다
Spell:	Spell:
Spell: OFF	Spell: 끔
Spell: ON	Spell: 켬
Start typing a skill or buff name...	스킬 또는 버프 이름을 입력하세요...
Stop tracking this entry on every canvas of this unit. The custom entry stays in the list.	이 유닛의 모든 캔버스에서 추적을 중단합니다. 사용자 지정 항목은 목록에 남습니다.
Support	후원
Support the Addon Developer	애드온 개발자 후원
Switch the canvas edited below. Shown: %s.	아래에서 편집할 캔버스를 전환합니다. 표시 중: %s.
Switch the interface, every hover tooltip and all chat messages to this language.	인터페이스, 모든 툴팁, 모든 채팅 메시지를 이 언어로 전환합니다.
TTP canvas found: %s	TTP 캔버스를 찾았습니다: %s
TTP canvas not found, fallback: %s	TTP 캔버스를 찾지 못해 대체 배치: %s
Target	대상
Target cache cleaned: %s	대상 캐시 정리됨: %s
Target display modes: overlay at the target's screen position, hide the floating canvas, avoid TrackThatPlease.	대상 표시 모드: 대상 화면 위치에 오버레이, 부동 캔버스 숨기기, TrackThatPlease 회피.
Target only. Stacks are read from the target's aura (1 if none).	대상 전용. 스택은 대상의 오라에서 읽습니다 (없으면 1).
Text color:	텍스트 색상:
Thank you for supporting the development!	개발을 후원해 주셔서 감사합니다!
Thank you for your hard work!	노고에 감사드립니다!
Timer font size in pixels (8-40). Applies on Enter.	카운트다운 글꼴 크기(픽셀, 8-40). Enter로 적용됩니다.
Timer settings	카운트다운 설정
Track this ID/name on the current unit and canvas.	현재 유닛과 캔버스에서 이 ID/이름을 추적합니다.
Tracked entries:	추적 항목:
Tracking key of this entry; it cannot be changed here.	이 항목의 추적 키이며 여기서는 변경할 수 없습니다.
Type	유형
Type:	유형:
Type: %s. Click to cycle Flat -> Percent -> Reset.	유형: %s. 클릭하면 Flat -> Percent -> Reset으로 전환됩니다.
UI initialization for %s: %s	%s UI 초기화: %s
Unconditional %s	무조건 %s
Unit whose journal is listed below.	아래에 기록이 표시되는 유닛입니다.
Unit whose panel is edited below. Every unit has its own canvases and tracked list.	아래에서 패널을 편집할 유닛입니다. 각 유닛은 자체 캔버스와 추적 목록을 가집니다.
Unit:	유닛:
Unknown	알 수 없음
Up	위로
Use this canvas.	이 캔버스를 사용합니다.
Use this custom entry.	이 사용자 지정 항목을 사용합니다.
Use this custom entry: %s.	이 사용자 지정 항목을 사용: %s.
Value	값
Value for an unconditional modifier: seconds for +Flat, percent for +Percent (0 or more).	무조건 수정자 값: +Flat은 초, +Percent는 퍼센트 (0 이상).
Value: %s %%.	값: %s %%.
Value: %s s.	값: %s초.
Vertical gap between grid rows, px (0-40). Applies on Enter.	그리드 행 사이 세로 간격(픽셀, 0-40). Enter로 적용됩니다.
Write the whole configuration (custom entries, tracked lists, layouts) to a JSON file in the addon folder.	전체 구성(사용자 지정 항목, 추적 목록, 레이아웃)을 애드온 폴더의 JSON 파일로 기록합니다.
active	활성
always value must be a number >= 0	always 값은 0 이상의 숫자여야 합니다
aura dump -> %s	오라 덤프 -> %s
aura dump: write failed	오라 덤프: 쓰기 실패
buff dump: %s buffs loaded from %s	버프 덤프: %s개 버프를 %s에서 불러왔습니다
buff dump: %s buffs, %s skill icons	버프 덤프: %s개 버프, %s개 기술 아이콘
buff dump: %s buffs, %s; tables=%s named=%s errors=%s%s	버프 덤프: %s개 버프, %s; tables=%s named=%s errors=%s%s
buff dump: '%s' -> id=%s path=%s (entries updated: %s)	버프 덤프: '%s' -> id=%s path=%s (업데이트된 항목: %s)
buff dump: '%s' not found	버프 덤프: '%s'을(를) 찾을 수 없습니다
buff journal	버프 기록
buff scan: dumping all buffs%s (1..50000, 8000000..8001000)	버프 스캔: 모든 버프 덤프 중%s (1..50000, 8000000..8001000)
cast %s by %s (%sms)	%s 시전, %s (%s ms)
custom entry removed: %s	사용자 지정 항목 삭제됨: %s
custom: id=%s name=%s spell=%s CD=%s D=%s	custom: id=%s name=%s spell=%s CD=%s D=%s
effective CD: reset '%s' zeroed %s on target %s	유효 CD: '%s' 초기화로 %s이(가) 대상 %s에서 0이 되었습니다
effective CD: smart %.1f%% learned for %s on target %s (applied after %.2f s < %.2f s)	유효 CD: 대상 %s에서 %s에 대해 smart %.1f%% 학습됨 (%.2f초 < %.2f초 후 사용)
effective CD: target %s class %s -> %s, smart reset for this target	유효 CD: 대상 %s 클래스 %s -> %s, 이 대상의 smart 초기화됨
enter a buff ID or name	버프 ID 또는 이름을 입력하세요
entry %s: type=%s CD=%s D=%s%s	항목 %s: type=%s CD=%s D=%s%s
faded	해제됨
hide	숨김
icon from dump: %s -> %s	덤프에서 아이콘: %s -> %s
icon learned for spell %s: %s	스킬 %s의 아이콘 학습됨: %s
icon lookup id=%s -> path=%s name=%s%s	아이콘 조회 id=%s -> path=%s name=%s%s
icon picked: %s -> %s	아이콘 선택됨: %s -> %s
icon: no spellId in event for '%s'	아이콘: '%s' 이벤트에 spellId가 없습니다
invalid modifier source	잘못된 수정자 출처
mana cast %s cost=%s spend=%.1f regen=%.1f mount=%s	마나 시전 %s cost=%s spend=%.1f regen=%.1f mount=%s
mana drop %.1f (regen %.1f) — no match; pet='%s'; mount-blocked=%d cd-blocked=%d; entries: %s	마나 감소 %.1f (regen %.1f) — 일치 없음; pet='%s'; mount-blocked=%d cd-blocked=%d; 항목: %s
modifier %s: value must be a number >= 0	수정자 %s: 값은 0 이상의 숫자여야 합니다
msg %s src=%s tgt=%s spell=%s id=%s	msg %s src=%s tgt=%s spell=%s id=%s
parsed: spellId=%s spellName=%s	파싱: spellId=%s spellName=%s
saved to buff_dump.tbl	buff_dump.tbl에 저장됨
settings window rebuild failed: %s	설정 창을 다시 만들지 못했습니다: %s
show	표시
skill icon: %s	스킬 아이콘: %s
skill log	스킬 기록
timer %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s	타이머 %s %s->%s now=%.2f D=%s CD=%s fixed=%s ready=%s rem=%s
too many modifiers	수정자가 너무 많습니다
updateVisibleItems not found!	updateVisibleItems를 찾을 수 없습니다!
]==]
-- <<< DICT

local function loadBlock(text, target)
    for line in text:gmatch("[^\n]+") do
        local key, value = line:match("^(.-)\t(.*)$")
        if key and key ~= "" and value ~= nil then
            target[key] = value
        end
    end
    return target
end

-- Английский словарь — тождественный: собираем его из ключей всех остальных
-- языков, чтобы любой ключ, попавший в перевод, существовал и в en.
local function rebuildEnglish()
    local en = {}
    for _, code in ipairs(CODES) do
        if code ~= DEFAULT and type(dict[code]) == "table" then
            for key in pairs(dict[code]) do en[key] = key end
        end
    end
    dict[DEFAULT] = en
end

local loaded = false

local function ensureLoaded()
    if loaded then return end
    loaded = true
    for code, block in pairs(dict) do
        if type(block) == "string" then
            local target = {}
            loadBlock(block, target)
            dict[code] = target
        end
    end
    rebuildEnglish()
end
M.ensureLoaded = ensureLoaded

local current = DEFAULT

local function validCode(code)
    if type(code) ~= "string" then return nil end
    for _, c in ipairs(CODES) do
        if c == code then return code end
    end
    return nil
end
M.validCode = validCode

-- Текущий язык (code). Неизвестное/пустое значение -> en.
function M.current()
    ensureLoaded()
    return current
end

-- Установить язык в памяти (без записи в настройки).
function M.set(code)
    ensureLoaded()
    current = validCode(code) or DEFAULT
    return current
end

-- Прочитать язык из настроек аддона (миграция: нет поля -> en).
function M.applySettings(settings)
    ensureLoaded()
    local code = settings and settings.language
    current = validCode(code) or DEFAULT
    return current
end

-- Сохранить язык в настройках немедленно.
function M.persist(code, settings)
    ensureLoaded()
    local target = validCode(code) or DEFAULT
    current = target
    local s = settings or api.GetSettings(ADDON_ID)
    if s then
        s.language = target
        pcall(function() api.SaveSettings() end)
    end
    return target
end

-- Родное название языка для селектора (не переводится).
function M.native(code)
    for _, lang in ipairs(LANGS) do
        if lang.code == code then return lang.native end
    end
    return "English"
end

-- Словарь языка (для тестов): dict["ru"]["Tracked entries:"].
function M.tableFor(code)
    ensureLoaded()
    return dict[validCode(code) or DEFAULT] or {}
end

-- Список ключей мастера (английский словарь).
function M.keys()
    ensureLoaded()
    local out = {}
    for key in pairs(dict[DEFAULT] or {}) do out[#out + 1] = key end
    table.sort(out)
    return out
end

-- Главная функция: перевод текста и подстановка аргументов.
function M.L(text, ...)
    if type(text) ~= "string" or text == "" then return text end
    ensureLoaded()
    local source = dict[current] or dict[DEFAULT] or {}
    local value = source[text]
    if type(value) ~= "string" or value == "" then value = text end
    local args = { ... }
    if #args > 0 then
        local ok, formatted = pcall(string.format, value, unpack(args))
        if ok and type(formatted) == "string" then return formatted end
    end
    return value
end

return M

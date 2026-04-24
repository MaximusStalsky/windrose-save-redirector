# Windrose Save Redirector

Windows utility for moving Windrose save profiles to another drive while keeping the original game save path working through a junction link.

The main goal is to reduce frequent save writes on an SSD by moving the actively updated Windrose `SaveProfiles` folder to a user-selected location, usually on an HDD.

## What It Does

Windrose stores profile save data in:

```text
%LOCALAPPDATA%\R5\Saved\SaveProfiles
```

This utility moves only that folder, not the entire Unreal Engine `Saved` directory.

When you choose a destination folder, the utility creates:

```text
<selected folder>\Windrose Saves\SaveProfiles
```

Then it creates a Windows junction at the original location:

```text
%LOCALAPPDATA%\R5\Saved\SaveProfiles
    -> <selected folder>\Windrose Saves\SaveProfiles
```

To Windrose, the save path stays the same. Physically, the save profile files live in the selected folder.

## Features

- Finds the Steam installation of Windrose.
- Finds the Windrose save profile folder automatically.
- Moves only `SaveProfiles`, leaving the rest of `R5\Saved` untouched.
- Creates the destination folder automatically.
- Creates a backup before moving files.
- Uses `mklink /J` for the junction.
- Checks current redirect status.
- Restores saves back to the original location.
- Supports English and Russian UI.
- Requests administrator rights on launch.

## Backup

Before moving saves, the utility creates a backup next to the original game data:

```text
%LOCALAPPDATA%\R5\Windrose Saves Backup-YYYYMMDD-HHMMSS\SaveProfiles
```

The backup is not created inside the destination folder, so the moved save directory stays clean.

## Usage

1. Close Windrose.
2. Run `Launch Windrose Save Redirector.cmd`.
3. Approve the Windows administrator prompt.
4. Click `Find`.
5. Click `Browse` and choose the base folder where saves should be moved.
6. The utility will create `Windrose Saves\SaveProfiles` inside that folder automatically.
7. Click `Move saves`.

## Restore

Use `Restore` to:

- remove the junction;
- move `SaveProfiles` back to `%LOCALAPPDATA%\R5\Saved\SaveProfiles`.

The restore action also handles the older full-folder redirect layout where the whole `Saved` directory was linked.

## Verification

After moving, this command should show a junction:

```cmd
dir /AL "%LOCALAPPDATA%\R5\Saved"
```

Expected result:

```text
<JUNCTION> SaveProfiles [D:\...\Windrose Saves\SaveProfiles]
```

## VirusTotal

Release archive scan:

```text
https://www.virustotal.com/gui/file/22dbebe7a033b16e47b6bfdd0eb810acc96b43162ba7ed791ee45ea2e32d226d
```

## Notes

- The game must be closed before moving or restoring saves.
- The utility is designed for Windows.
- The destination folder should be on a reliable local drive.
- Do not delete the backup until you have confirmed that Windrose starts and saves correctly.

---

# Windrose Save Redirector на русском

Утилита для Windows, которая переносит профильные сохранения Windrose на другой диск, но оставляет для игры старый путь через junction-ссылку.

Главная цель: уменьшить частые записи сохранений на SSD, перенеся активно обновляемую папку `SaveProfiles` в выбранное пользователем место, обычно на HDD.

## Что делает утилита

Windrose хранит профильные сохранения здесь:

```text
%LOCALAPPDATA%\R5\Saved\SaveProfiles
```

Утилита переносит только эту папку, а не всю папку Unreal Engine `Saved`.

Когда пользователь выбирает папку назначения, утилита создает:

```text
<выбранная папка>\Windrose Saves\SaveProfiles
```

Затем на старом месте создается junction:

```text
%LOCALAPPDATA%\R5\Saved\SaveProfiles
    -> <выбранная папка>\Windrose Saves\SaveProfiles
```

Для Windrose путь сохранений остается прежним. Физически файлы сохранений лежат в выбранной папке.

## Возможности

- Автоматически ищет Windrose в Steam.
- Автоматически находит папку профильных сохранений.
- Переносит только `SaveProfiles`, не трогая остальную папку `R5\Saved`.
- Автоматически создает папку назначения.
- Создает резервную копию перед переносом.
- Использует `mklink /J` для junction-ссылки.
- Проверяет текущее состояние переноса.
- Возвращает сохранения обратно.
- Поддерживает русский и английский интерфейс.
- Сразу запускается с правами администратора.

## Резервная копия

Перед переносом утилита создает backup рядом с исходными данными игры:

```text
%LOCALAPPDATA%\R5\Windrose Saves Backup-YYYYMMDD-HHMMSS\SaveProfiles
```

Backup не создается внутри папки назначения, поэтому рабочая папка с перенесенными сохранениями остается чистой.

## Использование

1. Закройте Windrose.
2. Запустите `Launch Windrose Save Redirector.cmd`.
3. Подтвердите запрос прав администратора.
4. Нажмите `Найти`.
5. Нажмите `Выбрать` и укажите базовую папку, куда нужно перенести сохранения.
6. Утилита сама создаст внутри нее `Windrose Saves\SaveProfiles`.
7. Нажмите `Перенести`.

## Откат

Кнопка `Откат`:

- удаляет junction;
- возвращает `SaveProfiles` обратно в `%LOCALAPPDATA%\R5\Saved\SaveProfiles`.

Откат также умеет обработать старую схему, где ссылкой была вся папка `Saved`.

## Проверка

После переноса команда:

```cmd
dir /AL "%LOCALAPPDATA%\R5\Saved"
```

должна показать junction:

```text
<JUNCTION> SaveProfiles [D:\...\Windrose Saves\SaveProfiles]
```

## VirusTotal

Проверка release-архива:

```text
https://www.virustotal.com/gui/file/22dbebe7a033b16e47b6bfdd0eb810acc96b43162ba7ed791ee45ea2e32d226d
```

## Важно

- Перед переносом или откатом игра должна быть закрыта.
- Утилита предназначена для Windows.
- Папку назначения лучше выбирать на надежном локальном диске.
- Не удаляйте backup, пока не убедитесь, что Windrose запускается и корректно сохраняется.

## License

MIT License.

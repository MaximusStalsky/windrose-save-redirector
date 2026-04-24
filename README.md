# Windrose Save Redirector

A small Windows utility for moving Windrose save files to another folder and redirecting the original save path with a junction link.

## What It Does

Windrose stores local save data under the Windows user profile. If those saves are being written frequently, you may prefer to move them to another drive while keeping the game itself installed where it is.

This utility:

- finds the Steam installation of Windrose;
- finds the Windrose save folder automatically;
- lets you choose where saves should be moved;
- creates a `Windrose Saves` folder in the selected location;
- makes a backup before moving anything;
- moves the saves;
- creates a Windows junction at the original save path;
- can check the current redirect status;
- can restore the saves back to the original path.

## Usage

1. Run `Launch Windrose Save Redirector.cmd`.
2. Approve the Windows administrator prompt.
3. Click `Find`.
4. Click `Browse` and choose the base folder where saves should be moved.
5. The utility will create `Windrose Saves` inside that folder automatically.
6. Click `Move saves`.

The game must be closed before moving or restoring saves.

## Why Administrator Rights?

The launcher requests administrator rights immediately because Windows may require elevated permissions for moving protected save folders and creating junction links.

## Restore

Use `Restore` to remove the junction and move saves back to the original location.

## Russian

Утилита для Windows, которая переносит сохранения Windrose в выбранную папку и создает junction-ссылку на старом месте.

Возможности:

- автоматический поиск игры Windrose в Steam;
- автоматический поиск папки сохранений;
- выбор папки, куда перенести сохранения;
- автоматическое создание подпапки `Windrose Saves`;
- создание резервной копии перед переносом;
- перенос сохранений;
- создание junction-ссылки;
- проверка текущего состояния;
- откат изменений.

Запуск:

1. Запустите `Launch Windrose Save Redirector.cmd`.
2. Подтвердите запрос прав администратора.
3. Нажмите `Найти`.
4. Нажмите `Выбрать` и укажите папку для переноса.
5. Утилита сама создаст внутри нее папку `Windrose Saves`.
6. Нажмите `Перенести`.

Перед переносом или откатом игра должна быть закрыта.

## License

MIT License.

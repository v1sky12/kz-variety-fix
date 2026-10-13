# kz_variety_fix

Обновлённая Roblox-карта с движением в стиле CS2 KZ. Оружие, экономика и режим 5v5 не добавляются.

## Скачать

- [RBXL](https://github.com/v1sky12/kz-variety-fix/raw/upload/kz-variety-fix-updated/kz_variety_fix.rbxl)
- [ZIP с RBXL](https://github.com/v1sky12/kz-variety-fix/raw/upload/kz-variety-fix-updated/kz_variety_fix_updated.zip)

## Что включено

- один активный CKZ мотор с фиксированным шагом 128 Hz;
- ускорение, трение, prestrafe, air-strafe и перенос скорости в bunnyhop;
- сохранение горизонтальной скорости на surf-рампе и на переходах между плоскостями;
- обычные и горизонтальные лестницы, выход и LAJ;
- вода без принудительного прыжка, всплытие и выход;
- delayed push, абсолютные оси push, отмена после телепорта и сброс состояния;
- jumpstats LJ/BH/MBH/WJ/LAJ с дистанцией, sync, gain/loss и edge/fail;
- серверные атрибуты состояния земли и скорости для диагностики двух игроков;
- установщик с резервной копией и откатом.

`KZBrushFallback` отключён как второй контроллер. Его исходник и V5 остаются в place как резервные копии.

## Установка и откат

```bash
python3 install_kz_variety_fix.py install kz_variety_fix_updated.zip ./kz_variety_fix.rbxl
python3 install_kz_variety_fix.py rollback ./kz_variety_fix.rbxl.backup-YYYYMMDDTHHMMSSZ ./kz_variety_fix.rbxl
```

Автоматические проверки формул и surf проходят. Проверка на реальной рампе, лестнице и в Roblox Studio требует запуска place с двумя игроками.

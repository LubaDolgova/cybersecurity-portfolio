"""Размеры окна, частоты обновления и цвета.

Ничего игрового тут нет, вся логика в базе.
"""
import os

# Обычно реквизиты вводят на экране подключения. Это запасные
# значения, для скриптов без окна.
DB_USER = os.getenv("MC_USER", "")
DB_PASSWORD = os.getenv("MC_PASSWORD", "")
DB_DSN = os.getenv("MC_DSN", "")

# Толстый клиент Oracle нужен редко, только если на сервере
# какая-то особая авторизация.
USE_THICK_CLIENT = os.getenv("MC_THICK", "0") == "1"
ORACLE_CLIENT_LIB = os.getenv("MC_CLIENT_LIB") or None

WINDOW_W = 1280
WINDOW_H = 760
FPS = 60

# Как часто ходим в базу, в секундах
TICK_INTERVAL = 1.0      # museum_curator.process_time_tick
REFRESH_INTERVAL = 0.7   # перечитывание состояния для отрисовки

COL_BG = (24, 26, 33)
COL_PANEL = (33, 36, 46)
COL_PANEL_2 = (42, 46, 58)
COL_LINE = (62, 68, 84)
COL_TEXT = (228, 231, 238)
COL_DIM = (148, 156, 173)
COL_ACCENT = (233, 196, 106)
COL_OK = (106, 190, 140)
COL_WARN = (224, 122, 95)
COL_NIGHT = (18, 20, 30)

THEME_COLORS = {
    "История": (138, 120, 93),
    "Искусство": (122, 106, 160),
    "Наука": (86, 140, 158),
    "без темы": (78, 84, 100),
}
